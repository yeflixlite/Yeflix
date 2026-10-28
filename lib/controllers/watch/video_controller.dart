// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_orientation/auto_orientation.dart';
import 'package:dio/dio.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jiruhub/utils/exo_player_controller.dart';
import 'package:jiruhub/data/providers/anilist_provider.dart';
import 'package:jiruhub/data/providers/bt_server_provider.dart';
import 'package:jiruhub/models/index.dart';
import 'package:jiruhub/utils/log.dart';
import 'package:jiruhub/utils/request.dart';
import 'package:jiruhub/utils/router.dart';
import 'package:jiruhub/views/dialogs/bt_dialog.dart';
import 'package:jiruhub/controllers/home_controller.dart';
import 'package:jiruhub/controllers/main_controller.dart';
import 'package:jiruhub/router/router.dart';
import 'package:jiruhub/utils/bt_server.dart';
import 'package:jiruhub/data/services/database_service.dart';
import 'package:jiruhub/data/services/extension_service.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/utils/layout.dart';
import 'package:jiruhub/utils/jiruhub_directory.dart';
import 'package:jiruhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as path;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:crypto/crypto.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';
import 'package:flutter_hls_parser/flutter_hls_parser.dart';

class VideoPlayerController extends GetxController {
  final String title;
  final List<ExtensionEpisode> playList;
  final String detailUrl;
  final int playIndex;
  final int episodeGroupId;
  final ExtensionService? runtime;
  final String anilistID;

  VideoPlayerController({
    required this.title,
    required this.playList,
    required this.detailUrl,
    required this.playIndex,
    required this.episodeGroupId,
    this.runtime,
    required this.anilistID,
    this.localFilePath,
  }) {
    exo = ExoPlayerNativeController(tag: title);
  }

  /// Ruta de archivo local para reproduccion offline. Cuando se establece,
  /// [play] abre el archivo directamente sin consultar la extension.
  final String? localFilePath;

  // 播放器
  final player = Player();
  late final videoController = VideoController(player);

  /// Controlador nativo de ExoPlayer (solo Android).
  late final ExoPlayerNativeController exo;

  /// Indica si en esta plataforma se está usando ExoPlayer nativo (Android).
  bool get isExoPlayerActive => Platform.isAndroid;

  /// URL de fuente resuelta para ExoPlayer (Android).
  final RxString exoSourceUrl = ''.obs;

  /// Cabeceras autorizadas para la fuente de ExoPlayer.
  final Rx<Map<String, String>> exoHeaders = Rx(<String, String>{});

  // Estados de reproducción ExoPlayer (mirror para la UI).
  final RxBool exoIsPlaying = false.obs;
  final RxInt exoPlaybackState = 0.obs;
  final RxBool exoLoading = false.obs;
  final RxInt exoPositionMs = 0.obs;
  final RxInt exoDurationMs = 0.obs;
  Timer? _exoPositionTimer;

  /// Permite registrar el momento exacto en que mpv deja de buffear.
  bool _wasBuffering = false;

  final showSidebar = false.obs;
  final isOpenSidebar = false.obs;
  final isFullScreen = false.obs;
  late final index = playIndex.obs;

  // 快捷键
  late final keyboardShortcuts = <KeyboardKey, VoidCallback>{
    LogicalKeyboardKey.escape: () {
      if (isFullScreen.value) {
        WindowManager.instance.setFullScreen(false);
      }
      RouterUtils.pop();
    },
    LogicalKeyboardKey.keyF: () => this.toggleFullscreen(),
    LogicalKeyboardKey.mediaPlay: () => player.play(),
    LogicalKeyboardKey.mediaPause: () => player.pause(),
    LogicalKeyboardKey.mediaPlayPause: () => player.playOrPause(),
    LogicalKeyboardKey.mediaTrackNext: () => player.next(),
    LogicalKeyboardKey.mediaTrackPrevious: () => player.previous(),
    LogicalKeyboardKey.space: () => player.playOrPause(),
    LogicalKeyboardKey.keyJ: () {
      final rate = player.state.position +
          Duration(
            milliseconds:
                (JiruHubStorage.getSetting(SettingKey.keyJ) * 1000).toInt(),
          );
      player.seek(rate);
    },
    LogicalKeyboardKey.keyI: () {
      final rate = player.state.position +
          Duration(
              milliseconds:
                  (JiruHubStorage.getSetting(SettingKey.keyI) * 1000).toInt());
      player.seek(rate);
    },
    LogicalKeyboardKey.arrowLeft: () {
      final rate = player.state.position +
          Duration(
              milliseconds:
                  (JiruHubStorage.getSetting(SettingKey.arrowLeft) * 1000)
                      .toInt());
      player.seek(rate);
    },
    LogicalKeyboardKey.arrowRight: () {
      final rate = player.state.position +
          Duration(
              milliseconds:
                  (JiruHubStorage.getSetting(SettingKey.arrowRight) * 1000)
                      .toInt());
      player.seek(rate);
    },
    LogicalKeyboardKey.arrowUp: () {
      final volume = player.state.volume + 5.0;
      player.setVolume(volume.clamp(0.0, 100.0));
    },
    LogicalKeyboardKey.arrowDown: () {
      final volume = player.state.volume - 5.0;
      player.setVolume(volume.clamp(0.0, 100.0));
    },
  };

  // 字幕
  final subtitles = <SubtitleTrack>[].obs;

  // 画质
  final currentQuality = "".obs;
  final qualityMap = <String, String>{};

  // 是否已经自动跳转到上次播放进度
  bool _isAutoSeekPosition = false;

  // 信息列队
  final messageQueue = <Message>[];
  final Rx<Widget?> cuurentMessageWidget = Rx(null);

  // 播放速度
  final currentSpeed = 1.0.obs;
  final speedList = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  // torrent 媒体文件
  final torrentMediaFileList = <String>[].obs;
  final currentTorrentFile = ''.obs;
  String _torrenHash = "";

  // 调用 watch 方法获取到的数据
  ExtensionBangumiWatch? watchData;
  final error = "".obs;
  final isGettingWatchData = true.obs;
  int _playSessionId = 0;

  // Selector de servidores (llenado desde X-Servers header de la extensión)
  final availableServers = <String, String>{}.obs; // nombre → embed URL
  final serverReferers = <String, String>{}; // nombre → referer (no observable)
  final currentServerName = ''.obs;
  final serverFailedMessage = ''.obs;
  final currentLanguage = ''.obs;

  // 字幕配置
  final subtitleFontSize = 46.0.obs;
  final subtitleFontWeight = FontWeight.normal.obs;
  final subtitleTextAlign = TextAlign.center.obs;
  final subtitleFontColor = Colors.white.obs;
  final subtitleBackgroundColor = Colors.black.obs;
  final subtitleBackgroundOpacity = 0.5.obs;

  // 侧边栏初始化 tab
  final initSidebarTab = SidebarTab.episodes.obs;

  // 播放方式
  final playMode = PlaylistMode.none.obs;

  // 进度
  final position = Duration.zero.obs;

  // 总时长
  final duration = Duration.zero.obs;

  // 播放状态
  final isPlaying = false.obs;

  // dlna 设备
  final dlnaDevice = Rx<DLNADevice?>(null);

  // 定时器
  Timer? _dlnaTimer;

  @override
  void onInit() async {
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (LayoutUtils.isTablet) {
        // Tablet: la app sigue la rotación física del dispositivo (vertical u
        // horizontal) y respeta el bloqueo de giro del sistema.
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        await AutoOrientation.setScreenOrientationUser();
      } else {
        // Teléfono: se mantiene el video en horizontal.
        SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
        );
        await AutoOrientation.landscapeAutoMode(forceSensor: true);
      }
    }
    _initSettings();
    _initPlayer();
    // Inicializa el controlador nativo de ExoPlayer (Android).
    if (isExoPlayerActive) {
      exo.init();
      _bindExoStreams();
    }
    // Configurar libmpv para evitar crashes en Linux:
    // - hwdec=no: evita error vaapi not supported by libswscale
    // - reconnect=0: evita SIGSEGV ~16s post-EHOSTUNREACH cuando
    //   libmpv intenta reconectar HLS y falla en la limpieza interna
    // - network-timeout=30: red de seguridad sin abortar descargas lentas
    if (player.platform is NativePlayer) {
      final np = player.platform as NativePlayer;
      if (Platform.isLinux) {
        await np.setProperty('hwdec', 'no');
        await np.setProperty(
            'demuxer-lavf-o', 'reconnect=0,reconnect_delay_max=0');
      } else {
        await np.setProperty('hwdec', 'auto-safe');
        // reconnect=0: reconnect_streamed hace que FFmpeg interprete el EOF del
        // playlist HLS VOD como un corte y reintente en bucle durante ~20s
        // antes de abrir el primer segmento. En VOD no debe reconectar.
        await np.setProperty('demuxer-lavf-o', 'reconnect=0');
      }
      try {
        // Analizar 1s / 1MB: con 0.2s/64KB FFmpeg no detectaba los parámetros
        // del audio AAC ("Could not find codec parameters for stream 1").
        await np.setProperty('demuxer-lavf-analyzeduration', '1.0');
        await np.setProperty('demuxer-lavf-probesize', '1048576');
        await np.setProperty('demuxer-readahead-secs', '2');
        await np.setProperty('cache-pause-initial', 'no');
      } catch (_) {}
      // Timeout de red amplio: solo como red de seguridad. Un valor bajo
      // aborta descargas lentas pero válidas y provoca reintentos.
      await np.setProperty('network-timeout', '30');
    }
    play();

    super.onInit();
  }

  /// Vincula los streams de eventos del reproductor nativo ExoPlayer.
  void _bindExoStreams() {
    exo.onError.listen((message) {
      onExoError(message);
    });
    exo.onRenderedFirstFrame.listen((_) {
      logger.info('ExoPlayer: primer frame renderizado en pantalla');
      serverFailedMessage.value = '';
      error.value = '';
      isGettingWatchData.value = false;
      isPlaying.value = true;
      exoIsPlaying.value = true;
    });
    exo.onIsPlayingChanged.listen((playing) {
      exoIsPlaying.value = playing;
      isPlaying.value = playing;
      if (playing) {
        serverFailedMessage.value = '';
        error.value = '';
        isGettingWatchData.value = false;
      }
    });
    exo.onStateChanged.listen((args) {
      final playing = args['playWhenReady'] as bool? ?? false;
      final state = args['playbackState'] as int? ?? 0;
      final isPl = args['isPlaying'] as bool? ?? false;
      exoIsPlaying.value = playing || isPl;
      exoPlaybackState.value = state;
      isPlaying.value = playing || isPl;
      // Media3: STATE_IDLE = 1, STATE_BUFFERING = 2, STATE_READY = 3, STATE_ENDED = 4
      if (state == 3 || isPl || (state == 2 && playing)) {
        serverFailedMessage.value = '';
        error.value = '';
        isGettingWatchData.value = false;
      }
    });
    exo.onLoadingChanged.listen((loading) {
      exoLoading.value = loading;
    });
  }

  /// Callback de error del reproductor nativo ExoPlayer.
  void onExoError(String message) {
    logger.severe('ExoPlayer error: $message');
    // No mostrar error si hay reproducción activa (p.ej. errores de segmentos
    // de thumbnails en HLS de VidHide mientras el video principal está OK)
    if (isPlaying.value || exoIsPlaying.value || exoPositionMs.value > 0) {
      logger.warning('ExoPlayer error ignorado (reproducción activa): $message');
      return;
    }
    exoLoading.value = false;
    error.value = 'ExoPlayer: $message';
    serverFailedMessage.value = 'Error de reproducción: $message';
    isPlaying.value = false;
  }

  /// Callback de cambio de estado del reproductor nativo ExoPlayer.
  void onExoStateChanged(bool playing, int state) {
    exoIsPlaying.value = playing;
    isPlaying.value = playing;
    // Media3: STATE_READY = 3
    if (state == 3 || playing) {
      serverFailedMessage.value = '';
      error.value = '';
      isGettingWatchData.value = false;
    }
  }

  /// Callback de cambio de carga del reproductor nativo ExoPlayer.
  void onExoLoadingChanged(bool loading) {
    exoLoading.value = loading;
  }

  /// Abre una fuente en ExoPlayer nativo (Android).
  Future<bool> playExo({
    required String url,
    Map<String, String>? headers,
    int? positionMs,
    String? mimeType,
  }) async {
    if (!isExoPlayerActive) return false;
    exoSourceUrl.value = url;
    if (headers != null) exoHeaders.value = headers;
    exoLoading.value = true;
    try {
      await exo.setSource(
        url: url,
        headers: headers,
        positionMs: positionMs,
        mimeType: mimeType,
      );
      await exo.setPlayWhenReady(true);
      isPlaying.value = true;
      exoIsPlaying.value = true;
      _startExoPositionTimer();
      return true;
    } catch (e) {
      logger.severe('playExo error: $e');
      onExoError(e.toString());
      return false;
    }
  }

  /// Pausa/ reanuda en ExoPlayer nativo.
  Future<void> setExoPlayWhenReady(bool value) async {
    if (!isExoPlayerActive) return;
    await exo.setPlayWhenReady(value);
    exoIsPlaying.value = value;
    isPlaying.value = value;
  }

  /// Busca una posición en ExoPlayer nativo (ms).
  Future<void> seekExoMs(int positionMs) async {
    if (!isExoPlayerActive) return;
    await exo.seekToMs(positionMs);
    position.value = Duration(milliseconds: positionMs);
  }

  /// Inicia el temporizador de posición para ExoPlayer.
  void _startExoPositionTimer() {
    _exoPositionTimer?.cancel();
    _exoPositionTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!isExoPlayerActive) return;
      final pos = await exo.positionMs();
      if (pos >= 0) {
        exoPositionMs.value = pos;
        position.value = Duration(milliseconds: pos);
        if (pos > 0) {
          // Si la posición ya avanzó, el video se está reproduciendo con éxito
          if (serverFailedMessage.value.isNotEmpty) serverFailedMessage.value = '';
          if (error.value.isNotEmpty) error.value = '';
          if (isGettingWatchData.value) isGettingWatchData.value = false;
        }
      }
      final dur = await exo.durationMs();
      if (dur > 0) {
        exoDurationMs.value = dur;
        duration.value = Duration(milliseconds: dur);
      }
      final playing = await exo.isPlaying();
      exoIsPlaying.value = playing;
      isPlaying.value = playing;
      if (playing) {
        if (serverFailedMessage.value.isNotEmpty) serverFailedMessage.value = '';
        if (error.value.isNotEmpty) error.value = '';
        if (isGettingWatchData.value) isGettingWatchData.value = false;
      }
    });
  }

  @override
  void onClose() async {
    _exoPositionTimer?.cancel();
    if (isExoPlayerActive) {
      await exo.dispose();
    }
    if (JiruHubStorage.getSetting(SettingKey.autoTracking) && anilistID != "") {
      AniListProvider.editList(
        status: AnilistMediaListStatus.current,
        progress: playIndex + 1,
        mediaId: anilistID,
      );
    }
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );
      if (LayoutUtils.isTablet) {
        // Tablet: vuelve a seguir la rotación del dispositivo.
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        await AutoOrientation.setScreenOrientationUser();
      } else {
        // Teléfono: vuelve a vertical.
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
    _dlnaTimer?.cancel();
    try {
      player.pause();
    } catch (_) {}
    try {
      await player.stop();
      // Dar tiempo a libmpv para liquidar su estado antes de dispose
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (_) {}
    try {
      await _saveHistory();
    } catch (_) {}
    try {
      player.dispose();
    } catch (e) {
      logger.severe('player.dispose error: $e');
    }
    try {
      await _hlsServer?.close(force: true);
    } catch (_) {}
    _hlsServer = null;
    _hlsPlaylistBody = null;
    logger.info('dispose video controller');
    super.onClose();
  }

  _initSettings() {
    subtitleFontSize.value =
        JiruHubStorage.getSetting(SettingKey.subtitleFontSize);
    subtitleFontColor.value = Color(
      JiruHubStorage.getSetting(
        SettingKey.subtitleFontColor,
      ),
    );
    final fontWeightText =
        JiruHubStorage.getSetting(SettingKey.subtitleFontWeight);
    subtitleFontWeight.value =
        fontWeightText == 'bold' ? FontWeight.bold : FontWeight.normal;
    subtitleBackgroundColor.value = Color(JiruHubStorage.getSetting(
      SettingKey.subtitleBackgroundColor,
    ));
    subtitleBackgroundOpacity.value = JiruHubStorage.getSetting(
      SettingKey.subtitleBackgroundOpacity,
    );
    subtitleTextAlign.value = TextAlign.values[JiruHubStorage.getSetting(
      SettingKey.subtitleTextAlign,
    )];

    ever(subtitleFontSize, (callback) {
      JiruHubStorage.setSetting(SettingKey.subtitleFontSize, callback);
    });
    ever(subtitleFontColor, (callback) {
      JiruHubStorage.setSetting(
        SettingKey.subtitleFontColor,
        callback.value,
      );
    });
    ever(subtitleFontWeight, (callback) {
      JiruHubStorage.setSetting(
        SettingKey.subtitleFontWeight,
        callback == FontWeight.bold ? 'bold' : 'normal',
      );
    });
    ever(subtitleBackgroundColor, (callback) {
      JiruHubStorage.setSetting(
        SettingKey.subtitleBackgroundColor,
        callback.value,
      );
    });
    ever(subtitleBackgroundOpacity, (callback) {
      JiruHubStorage.setSetting(
        SettingKey.subtitleBackgroundOpacity,
        callback,
      );
    });
    ever(subtitleTextAlign, (callback) {
      JiruHubStorage.setSetting(
        SettingKey.subtitleTextAlign,
        callback.index,
      );
    });
  }

  _initPlayer() {
    // Log del momento exacto en que el video está listo (primer frame).
    player.stream.buffering.listen((buffering) {
      if (_wasBuffering && !buffering) {
        logger.info('⏱ buffering=false — primer frame listo');
      }
      _wasBuffering = buffering;
    });

    // 切换剧集
    ever(index, (callback) {
      play();
    });

    // 切换倍速
    ever(currentSpeed, (callback) {
      player.setRate(callback);
    });

    // 显示剧集列表
    ever(showSidebar, (callback) {
      if (!showSidebar.value) {
        isOpenSidebar.value = false;
      }
    });

    // 自动切换下一集
    player.stream.completed.listen((event) {
      if (!event || playMode.value == PlaylistMode.single) {
        return;
      }
      if (playMode.value == PlaylistMode.loop) {
        player.seek(Duration.zero);
        player.play();
        return;
      }

      if (index.value == playList.length - 1) {
        sendMessage(Message(Text('video.play-complete'.i18n)));
        return;
      }
      if (!player.state.buffering) {
        index.value++;
      }
    });

    // 讀取現在的畫質
    player.stream.height.listen((event) async {
      if (player.state.width != null) {
        final width = player.state.width;
        currentQuality.value = "${width}x$event";
      }
    });

    // 自动恢复上次播放进度
    player.stream.duration.listen((event) async {
      if (_isAutoSeekPosition || event.inSeconds == 0) {
        return;
      }

      // 获取上次播放进度
      final history = await DatabaseService.getHistoryByPackageAndUrl(
        runtime?.extension.package ?? 'local',
        detailUrl,
      );

      if (history != null &&
          history.progress.isNotEmpty &&
          history.episodeId == index.value &&
          history.episodeGroupId == episodeGroupId) {
        _isAutoSeekPosition = true;
        player.seek(Duration(seconds: int.parse(history.progress)));
        sendMessage(Message(Text('video.resume-last-playback'.i18n)));
      }
    });

    // 监听 track
    player.stream.tracks.listen((event) {
      if (event.subtitle.isEmpty) {
        return;
      }

      final latestLanguageSelected = JiruHubStorage.getSetting(
        SettingKey.subtitleLastLanguageSelected,
      );
      final latestTitleSelected = JiruHubStorage.getSetting(
        SettingKey.subtitleLastTitleSelected,
      );
      if (latestLanguageSelected == null && latestTitleSelected == null) {
        return;
      }

      final subtitle = [...event.subtitle, ...subtitles].firstWhereOrNull(
        (element) {
          if (element.id == "no" || element.id == "auto") {
            return false;
          }
          return element.language == latestLanguageSelected ||
              element.title == latestTitleSelected;
        },
      );

      if (subtitle != null) {
        player.setSubtitleTrack(subtitle);
      }
    });

    // 总时长监听
    player.stream.duration.listen((event) {
      if (dlnaDevice.value != null) {
        return;
      }
      duration.value = event;
    });

    // 监听播放状态
    player.stream.playing.listen((event) {
      if (dlnaDevice.value != null) {
        return;
      }
      isPlaying.value = event;
      if (event) {
        serverFailedMessage.value = '';
        error.value = '';
        isGettingWatchData.value = false;
      }
    });

    // 监听进度
    player.stream.position.listen((event) {
      if (dlnaDevice.value != null) {
        return;
      }
      position.value = event;
      if (event.inSeconds > 0) {
        serverFailedMessage.value = '';
        error.value = '';
        isGettingWatchData.value = false;
      }
    });

    // 错误监听 — detectar fallo de reproducción
    player.stream.error.listen((event) {
      logger.severe('media_kit error: $event');
      sendMessage(Message(Text(event)));
      // Si el error indica que el stream no es accesible, notificar solo si no hay reproducción activa
      final isAlreadyPlaying = player.state.playing ||
          player.state.position.inSeconds > 0 ||
          isPlaying.value;
      if (!isAlreadyPlaying &&
          (event.toLowerCase().contains('not found') ||
              event.toLowerCase().contains('403') ||
              event.toLowerCase().contains('500') ||
              event.toLowerCase().contains('no such') ||
              event.toLowerCase().contains('failed'))) {
        if (serverFailedMessage.value.isEmpty) {
          if (availableServers.length > 1) {
            serverFailedMessage.value =
                'Servidor "${currentServerName.value}" no disponible.\n'
                'Cambia de servidor con el botón Servidor.';
          } else {
            serverFailedMessage.value =
                'Error de reproducción. Intenta más tarde.';
          }
        }
      }
    });
  }

  // 播放
  play() async {
    // Si el controlador ya fue delete, no hacer nada.
    if (!Get.isRegistered<VideoPlayerController>(tag: title)) {
      return;
    }
    final sessionId = ++_playSessionId;
    // ── TIMING DIAGNÓSTICO ─────────────────────────────────────────────────
    final _t0 = DateTime.now();
    logger.info('⏱ [T+0ms] play() iniciado para index: ${index.value}');
    // ───────────────────────────────────────────────────────────────────────
    player.stop();
    isGettingWatchData.value = true;
    error.value = '';
    serverFailedMessage.value = '';

    // Reproduccion de archivo local (offline): se abre directamente con
    // ExoPlayer en Android o media_kit en desktop, sin consultar extension ni red.
    if (localFilePath != null && localFilePath!.isNotEmpty) {
      try {
        if (isExoPlayerActive) {
          await playExo(url: localFilePath!);
        } else {
          await player.open(Media(localFilePath!));
        }
        if (sessionId != _playSessionId) return;
        isGettingWatchData.value = false;
        return;
      } catch (e) {
        if (sessionId != _playSessionId) return;
        logger.severe('local file open error: $e');
        error.value = e.toString();
        serverFailedMessage.value = 'Error al abrir archivo local: $e';
        isGettingWatchData.value = false;
        if (!isExoPlayerActive) await _safePlayerInit();
        return;
      }
    }

    if (runtime == null) {
      error.value = 'No se encontró la extensión para cargar este video.';
      serverFailedMessage.value = error.value;
      isGettingWatchData.value = false;
      return;
    }

    logger.info('⏱ [T+${DateTime.now().difference(_t0).inMilliseconds}ms] getWatchData() START (runtime.watch)');
    try {
      await getWatchData();
    } catch (e) {
      if (sessionId != _playSessionId) return;
      logger.severe(e);
      error.value = e.toString();
      serverFailedMessage.value = 'Error al obtener fuentes: $e';
      isGettingWatchData.value = false;
      return;
    }
    final _urlPreview = (watchData?.url ?? '').substring(0, (watchData?.url?.length ?? 0).clamp(0, 80));
    logger.info('⏱ [T+${DateTime.now().difference(_t0).inMilliseconds}ms] getWatchData() END — url: $_urlPreview');

    if (sessionId != _playSessionId) return;

    if (watchData == null) {
      error.value = 'No se encontraron datos de reproducción.';
      serverFailedMessage.value = error.value;
      isGettingWatchData.value = false;
      return;
    }

    try {
      if (watchData!.type == ExtensionWatchBangumiType.torrent) {
        try {
          await getTorrentMediaFile();
        } catch (e) {
          logger.severe(e);
          error.value = e.toString();
          return;
        }

        playTorrentFile(torrentMediaFileList.first);
      } else {
        if (dlnaDevice.value != null) {
          await dlnaDevice.value!.setUrl(watchData!.url);
          await dlnaDevice.value!.play();
        } else {
          final primaryUrl = watchData!.url;

          logger.info('⏱ [T+${DateTime.now().difference(_t0).inMilliseconds}ms] _openStream() START — servidor: ${currentServerName.value}');
          logger.info('   URL: $primaryUrl');
          logger.info('   Headers: ${watchData!.headers}');
          bool worked = await _openStream(primaryUrl, watchData!.headers);
          
          if (worked) {
            // Solo si el video ya arrancó, cargamos la lista de calidades en background
            unawaited(getQuality());
          }
          logger.info('⏱ [T+${DateTime.now().difference(_t0).inMilliseconds}ms] _openStream() END — worked=$worked');
          if (sessionId != _playSessionId) return;

          if (!worked &&
              watchData!.headers != null &&
              watchData!.headers!.containsKey('X-Netu-Alts')) {
            try {
              final List<dynamic> alts =
                  jsonDecode(watchData!.headers!['X-Netu-Alts']!);
              for (final altUrlDyn in alts) {
                if (sessionId != _playSessionId) return;
                final altUrl = altUrlDyn.toString();
                logger.info('Intentando URL alternativa: $altUrl');
                worked = await _openStream(altUrl, watchData!.headers);
                if (sessionId != _playSessionId) return;
                if (worked) {
                  watchData = ExtensionBangumiWatch(
                    type: watchData!.type,
                    url: altUrl,
                    subtitles: watchData!.subtitles,
                    headers: watchData!.headers,
                    audioTrack: watchData!.audioTrack,
                  );
                  break;
                }
              }
            } catch (e) {
              logger.warning('Error parseando X-Netu-Alts: $e');
            }
          }

          if (sessionId != _playSessionId) return;

          if (!worked) {
            logger.severe(
                'Servidor primario fallido: ${currentServerName.value}');
            // Auto-failover: iterar servidores alternativos
            bool foundWorking = false;
            final serverEntries = availableServers.entries.toList();
            final serverErrors =
                <String, String>{}; // Para registrar errores por servidor
            logger.info(
                'Servidores disponibles para failover: ${serverEntries.map((e) => e.key).toList()}');
            for (final entry in serverEntries.take(3)) {
              if (sessionId != _playSessionId) return;
              if (entry.key == currentServerName.value) continue;
              try {
                logger.info('Failover → probando servidor: ${entry.key}');
                serverFailedMessage.value =
                    'Servidor "${currentServerName.value}" no disponible, '
                    'probando "${entry.key}"...';
                final rawAlt = await runtime!.watch(entry.value);
                if (sessionId != _playSessionId) return;
                if (rawAlt == null) continue;
                var alt = rawAlt as ExtensionBangumiWatch;
                logger.info('Failover ${entry.key} URL: ${alt.url}');
                if (alt.url.startsWith('error://')) {
                  final errorMsg = alt.url.replaceFirst('error://', '');
                  logger.severe(
                      'Failover ${entry.key}: error de extracción ($errorMsg)');
                  serverErrors[entry.key] = errorMsg;
                  continue;
                }

                bool altWorked = await _openStream(alt.url, alt.headers);
                if (sessionId != _playSessionId) return;

                if (!altWorked &&
                    alt.headers != null &&
                    alt.headers!.containsKey('X-Netu-Alts')) {
                  try {
                    final List<dynamic> alts =
                        jsonDecode(alt.headers!['X-Netu-Alts']!);
                    for (final altUrlDyn in alts) {
                      final altUrlStr = altUrlDyn.toString();
                      logger
                          .info('Failover probando alternativa: $altUrlStr');
                      altWorked =
                          await _openStream(altUrlStr, alt.headers);
                      if (altWorked) {
                        alt = ExtensionBangumiWatch(
                          type: alt.type,
                          url: altUrlStr,
                          subtitles: alt.subtitles,
                          headers: alt.headers,
                          audioTrack: alt.audioTrack,
                        );
                        break;
                      }
                    }
                  } catch (e) {
                    logger.warning(
                        'Error parseando X-Netu-Alts en failover: $e');
                  }
                }

                if (!altWorked) {
                  logger.severe(
                      'Failover ${entry.key}: no se pudo conectar a ningún host');
                  continue;
                }

                // Servidor alternativo alcanzable — usarlo
                currentServerName.value = entry.key;
                watchData = alt;
                serverFailedMessage.value = '';
                error.value = '';
                logger.info('Failover exitoso: ${entry.key}');
                foundWorking = true;
                break;
              } catch (e, stackTrace) {
                logger.severe('Failover ${entry.key} excepción: $e');
                logger.severe('Stack trace: $stackTrace');
              }
            }
            if (!foundWorking) {
              final errorDetails = serverErrors.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join(', ');
              logger.severe(
                  'Todos los servidores fallaron. Errores: $errorDetails');
              serverFailedMessage.value =
                  'Ningún servidor disponible desde tu red.\n'
                  '${errorDetails.isNotEmpty ? 'Errores: $errorDetails\n' : ''}'
                  'Cambia de servidor o intenta más tarde.';
              error.value = serverFailedMessage.value;
              logger.severe('Todos los servidores fallaron');
              if (!isExoPlayerActive) await _safePlayerInit();
              isGettingWatchData.value = false;
              return;
            }
          }
          isGettingWatchData.value = false;
          serverFailedMessage.value = '';
          error.value = '';
          if (watchData?.audioTrack != null) {
            await player.setAudioTrack(
              AudioTrack.uri(watchData!.audioTrack!),
            );
          }
        }
      }
      isGettingWatchData.value = false;
      // 添加来自扩展的字幕
      if (watchData != null && watchData!.subtitles != null) {
        subtitles.addAll(
          watchData!.subtitles!.map(
            (e) => SubtitleTrack.uri(
              e.url,
              language: e.language,
              title: e.title,
            ),
          ),
        );
      }
      player.setSubtitleTrack(SubtitleTrack.no());
    } on StartServerException catch (_) {
      // 如果是 启动 bt server 失败
      if (Platform.isAndroid) {
        await showDialog(
          context: currentContext,
          builder: (context) => const BTDialog(),
        );
      } else {
        await fluent.showDialog(
          context: currentContext,
          builder: (context) => const BTDialog(),
        );
      }

      // 延时 3 秒再重试
      await Future.delayed(const Duration(seconds: 3));
      play();
      return;
    } catch (e) {
      isGettingWatchData.value = false;
      error.value = e.toString();
      serverFailedMessage.value = e.toString();
      sendMessage(
        Message(
          Text(e.toString()),
          time: const Duration(seconds: 5),
        ),
      );
    }
  }

  // 获取 watch 数据
  getWatchData() async {
    watchData = null;
    subtitles.clear();
    availableServers.clear();
    serverReferers.clear();
    serverFailedMessage.value = '';
    final playUrl = playList[index.value].url;
    final _tw0 = DateTime.now();
    logger.info('⏱ [watch] runtime.watch() START → $playUrl');
    final res = await runtime!.watch(playUrl);
    logger.info('⏱ [watch] runtime.watch() DONE — ${DateTime.now().difference(_tw0).inMilliseconds}ms — resultado: ${res == null ? 'null' : 'ok'}');
    if (res == null) {
      throw 'No se pudo obtener información del video.';
    }
    watchData = res as ExtensionBangumiWatch;

    final headers = watchData?.headers;
    if (headers != null) {
      // Parsear lista de servidores (embed URLs crudos)
      if (headers.containsKey('X-Servers')) {
        try {
          final Map<String, dynamic> parsed = jsonDecode(headers['X-Servers']!);
          availableServers.value =
              parsed.map((k, v) => MapEntry(k, v.toString()));
        } catch (_) {}
      }
      // Parsear referers por servidor
      if (headers.containsKey('X-Server-Referers')) {
        try {
          final Map<String, dynamic> parsed =
              jsonDecode(headers['X-Server-Referers']!);
          serverReferers
              .addAll(parsed.map((k, v) => MapEntry(k, v.toString())));
        } catch (_) {}
      }
      // Servidor actual
      currentServerName.value = headers['X-Primary-Server'] ??
          (availableServers.isNotEmpty ? availableServers.keys.first : '');
      currentLanguage.value = headers['X-Language'] ?? '';
      // Limpiar cabeceras especiales — no enviar al player
      watchData!.headers = Map.from(headers)
        ..remove('X-Servers')
        ..remove('X-Server-Referers')
        ..remove('X-Primary-Server')
        ..remove('X-Language');
    }
  }

  // Cambia al servidor — extrae su stream URL on-demand llamando watch(embedUrl)
  switchServer(String name) async {
    if (!availableServers.containsKey(name) || runtime == null) return;
    serverFailedMessage.value = '';
    error.value = '';
    isGettingWatchData.value = true;

    final embedUrl = availableServers[name]!;
    ExtensionBangumiWatch newWatch;
    try {
      // Mode 2: la extensión detecta que es un embed URL y extrae directamente
      final res = await runtime!.watch(embedUrl);
      if (res == null) throw 'Servidor no disponible';
      newWatch = res as ExtensionBangumiWatch;
    } catch (e) {
      logger.severe(e);
      serverFailedMessage.value =
          'No se pudo extraer el servidor "$name". Intenta otro.';
      isGettingWatchData.value = false;
      return;
    }

    if (newWatch.url.startsWith('error://')) {
      final msg = newWatch.url.replaceFirst('error://', '');
      serverFailedMessage.value =
          'Servidor "$name" no disponible: $msg. Intenta otro.';
      isGettingWatchData.value = false;
      return;
    }

    currentServerName.value = name;
    // Si la extensión no devolvió Referer, intentar del mapa local
    final headers = <String, String>{};
    final referer = newWatch.headers?['Referer'] ?? serverReferers[name];
    if (referer != null) headers['Referer'] = referer;
    if (newWatch.headers != null) {
      headers.addAll(newWatch.headers!);
    }

    watchData = ExtensionBangumiWatch(
      type: newWatch.type,
      url: newWatch.url,
      subtitles: newWatch.subtitles ?? watchData?.subtitles,
      headers: headers.isEmpty ? null : headers,
      audioTrack: newWatch.audioTrack ?? watchData?.audioTrack,
    );
    _isAutoSeekPosition = true;

    final worked = await _openStream(newWatch.url, watchData?.headers);
    if (!worked) {
      serverFailedMessage.value =
          'No se pudo conectar al servidor "$name". Intenta otro.';
    } else {
      serverFailedMessage.value = '';
      error.value = '';
    }
    isGettingWatchData.value = false;
  }

  // 获取 torrent 媒体文件
  getTorrentMediaFile() async {
    if (Get.find<MainController>().btServerisRunning.value == false) {
      await BTServerUtils.startServer();
    }
    sendMessage(
      Message(
        Text('video.torrent-downloading'.i18n),
      ),
    );
    // 下载 torrent
    final torrentFile = path.join(
      JiruHubDirectory.getCacheDirectory,
      'temp.torrent',
    );
    await dio.download(watchData!.url, torrentFile);

    final file = File(torrentFile);
    _torrenHash = await BTServerApi.addTorrent(file.readAsBytesSync());
    final files = await BTServerApi.getFileList(_torrenHash);

    torrentMediaFileList.clear();

    for (final file in files) {
      if (_isSubtitle(file)) {
        subtitles.add(
          SubtitleTrack.uri(
            '${BTServerApi.baseApi}/torrent/$_torrenHash/$file',
            title: path.basename(file),
          ),
        );
      } else {
        torrentMediaFileList.add(file);
      }
    }
  }

  // 获取画质
  getQuality() async {
    final url = watchData!.url;
    final headers = watchData!.headers;
    logger.info(url);

    late dynamic response;
    try {
      response = await dio.get(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );
    } on DioException catch (e) {
      // getQuality solo llena el menú manual de calidades.
      // NO alterar serverFailedMessage para no interrumpir la reproducción en curso de ExoPlayer.
      logger.warning('getQuality DioException (ignorado): $e');
      return;
    } catch (e) {
      logger.warning('getQuality error (ignorado): $e');
      return;
    }

    // 请求判断 content-type 是否为 m3u8
    final contentType = response.headers.value('content-type')?.toLowerCase();
    if (contentType == null ||
        !contentType.contains('mpegurl') &&
            !contentType.contains('m3u8') &&
            !contentType.contains('mp2t')) {
      logger.info('not m3u8');
      return;
    }

    // 接收数据到变量
    final completer = Completer<String>();
    final stream = response.data.stream;
    final buffer = StringBuffer();

    stream.listen(
      (data) {
        buffer.write(utf8.decode(data));
      },
      onDone: () {
        completer.complete(buffer.toString());
      },
      onError: (error) {
        completer.completeError(error);
      },
    );

    final m3u8Content = await completer.future;
    if (m3u8Content.isEmpty) {
      return;
    }

    late HlsPlaylist playlist;
    try {
      playlist = await HlsPlaylistParser.create().parseString(
        response.realUri,
        m3u8Content,
      );
    } on ParserException catch (e) {
      logger.severe(e);
      return;
    }

    if (playlist is HlsMasterPlaylist) {
      final urlList = playlist.mediaPlaylistUrls
          .map(
            (e) => e.toString(),
          )
          .toList();
      final resolution = playlist.variants.map(
        (it) => "${it.format.width}x${it.format.height}",
      );
      qualityMap.addAll(
        Map.fromIterables(
          resolution,
          urlList,
        ),
      );
    }
  }

  // 播放 torrent 媒体文件
  playTorrentFile(String file) {
    currentTorrentFile.value = file;
    (player.platform as NativePlayer).setProperty("network-timeout", "60");
    player.open(Media('${BTServerApi.baseApi}/torrent/$_torrenHash/$file'));
  }

  // 切换全屏
  toggleFullscreen() async {
    await WindowManager.instance.setFullScreen(!isFullScreen.value);
    isFullScreen.value = !isFullScreen.value;
  }

  // 切换画质
  switchQuality(String qualityUrl) async {
    final currentMs = isExoPlayerActive
        ? exoPositionMs.value
        : player.state.position.inMilliseconds;
    final headers = watchData?.headers;
    final cleanHeaders = headers == null
        ? null
        : (Map<String, String>.from(headers)
          ..removeWhere((k, _) => k.startsWith('X-Netu-')));
    if (isExoPlayerActive) {
      await playExo(
        url: qualityUrl,
        headers: headers,
        positionMs: currentMs,
      );
    } else {
      try {
        final nativePlayer = player.platform as NativePlayer;
        final referer = cleanHeaders?['Referer'] ?? cleanHeaders?['referer'];
        final ua = cleanHeaders?['User-Agent'] ?? cleanHeaders?['user-agent'];
        if (referer != null && referer.isNotEmpty) {
          await nativePlayer.setProperty('referrer', referer);
        }
        if (ua != null && ua.isNotEmpty) {
          await nativePlayer.setProperty('user-agent', ua);
        }
      } catch (_) {}
      await player.open(
        Media(qualityUrl, httpHeaders: cleanHeaders),
      );
      final currentSecond = currentMs ~/ 1000;
      Timer.periodic(const Duration(seconds: 1), (timer) {
        player.seek(Duration(seconds: currentSecond));
        if (player.state.position.inSeconds == currentSecond) {
          timer.cancel();
        }
      });
    }
  }

  // 设置字幕
  setSubtitleTrack(SubtitleTrack subtitle) {
    player.setSubtitleTrack(subtitle);
    JiruHubStorage.setSetting(
      SettingKey.subtitleLastLanguageSelected,
      subtitle.language,
    );
    JiruHubStorage.setSetting(
      SettingKey.subtitleLastTitleSelected,
      subtitle.title,
    );
  }

  // 保存历史记录
  _saveHistory() async {
    if (duration.value.inSeconds == 0) {
      return;
    }

    final tempDir = JiruHubDirectory.getCacheDirectory;
    final coverDir = path.join(tempDir, 'history_cover');
    Directory(coverDir).createSync(recursive: true);
    final epName = playList[index.value].name;
    final filename = '${title}_$epName';
    final file = File(
        path.join(coverDir, md5.convert(utf8.encode(filename)).toString()));
    if (file.existsSync()) {
      file.deleteSync(recursive: true);
    }

    final data = await player.screenshot();
    if (data == null) {
      return;
    }
    await file.writeAsBytes(data);

    logger.info('save history');

    await DatabaseService.putHistory(
      History()
        ..url = detailUrl
        ..cover = file.path
        ..episodeGroupId = episodeGroupId
        ..package = runtime?.extension.package ?? 'local'
        ..type = runtime?.extension.type ?? ExtensionType.bangumi
        ..episodeId = index.value
        ..episodeTitle = epName
        ..title = title
        ..progress = position.value.inSeconds.toString()
        ..totalProgress = duration.value.inSeconds.toString(),
    );
    await Get.find<HomePageController>().onRefresh();
  }

  // 判断文件是否是字幕
  _isSubtitle(String file) {
    return file.endsWith('.srt') ||
        file.endsWith('.vtt') ||
        file.endsWith(".ass");
  }

  // 发送消息
  sendMessage(Message message) {
    messageQueue.add(message);

    if (messageQueue.length == 1) {
      _processNextMessage();
    }
  }

  // 处理消息提示
  _processNextMessage() async {
    if (messageQueue.isEmpty) {
      cuurentMessageWidget.value = null;
      return;
    }

    final message = messageQueue.first;
    cuurentMessageWidget.value = message.child;
    // 等待消息显示完毕
    await Future.delayed(message.time);
    messageQueue.removeAt(0);
    _processNextMessage();
  }

  // 切换侧边栏
  toggleSideBar(SidebarTab tab) {
    if (showSidebar.value) {
      showSidebar.value = false;
      return;
    }
    initSidebarTab.value = tab;
    showSidebar.value = true;
  }

  // 添加本地字幕文件
  addSubtitleFile() async {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt'],
      allowMultiple: false,
    );
    if (file == null) {
      return;
    }
    final data = File(file.files.first.path!).readAsStringSync();
    subtitles.add(
      SubtitleTrack.data(
        data,
        title: file.files.first.name,
      ),
    );
  }

  // 连接 DLNA 设备
  connectDLNADevice(DLNADevice device) async {
    if (watchData == null) {
      sendMessage(Message(Text('等待视频加载'.i18n)));
      return;
    }
    final url = watchData!.url;
    dlnaDevice.value = device;
    await device.setUrl(url);
    await device.play();
    await player.stop();
    _dlnaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _getDLNAStatus();
    });
  }

  // 断开 DLNA 设备
  disconnectDLNADevice() async {
    if (dlnaDevice.value == null) {
      return;
    }
    final device = dlnaDevice.value!;
    dlnaDevice.value = null;
    device.stop();
    _dlnaTimer?.cancel();
  }

  // 获取 DLNA 播放状态
  _getDLNAStatus() async {
    final device = dlnaDevice.value;
    if (device == null) {
      return;
    }
    final transportInfo = await device.getTransportInfo();
    if (transportInfo.contains("PLAYING")) {
      isPlaying.value = true;
    } else {
      isPlaying.value = false;
    }
    final dlnaPosition = await device.position();
    final positionParser = PositionParser(dlnaPosition);
    final absTimeArr = positionParser.AbsTime.split(":");
    final absTime = Duration(
      hours: int.parse(absTimeArr[0]),
      minutes: int.parse(absTimeArr[1]),
      seconds: int.parse(absTimeArr[2]),
    );
    position.value = absTime;
    positionParser.TrackDurationInt;
    duration.value = Duration(seconds: positionParser.TrackDurationInt);
  }

  // Verifica si el host de una URL es alcanzable vía TCP.
  // Dart maneja EHOSTUNREACH (errno 113) limpiamente;
  // libmpv/libavformat tienen un bug que causa SIGSEGV con ese errno.
  Future<bool> _isHostReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasAuthority || uri.host.isEmpty) return true;
      final port = (uri.hasPort && uri.port > 0)
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(
        uri.host,
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      logger.info('Host alcanzable: ${uri.host}:$port');
      return true;
    } on SocketException catch (e) {
      logger.severe('Host inalcanzable: $url — ${e.message}');
      return false;
    } catch (_) {
      return true; // Error desconocido: dejar que libmpv lo intente
    }
  }

  // Intenta abrir el stream con ExoPlayer (Android).
  Future<bool> _tryOpenExo(String url, Map<String, String>? headers) async {
    if (url.startsWith('error://')) {
      logger.severe('URL de error recibida: $url');
      return false;
    }
    final started = await playExo(url: url, headers: headers);
    if (!started) return false;

    final completer = Completer<bool>();
    final subs = <StreamSubscription>[];
    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    // Solo aceptar como éxito real: primer frame renderizado o isPlaying=true
    // NO aceptar STATE_BUFFERING(2) solo, ya que no garantiza reproducción real
    subs.add(exo.onRenderedFirstFrame.listen((_) {
      logger.info('_tryOpenExo: primer frame renderizado -> OK');
      finish(true);
    }));

    subs.add(exo.onIsPlayingChanged.listen((isPlaying) {
      if (isPlaying) {
        logger.info('_tryOpenExo: onIsPlayingChanged(true) -> OK');
        finish(true);
      }
    }));

    subs.add(exo.onStateChanged.listen((args) {
      final state = args['playbackState'] as int? ?? 0;
      final isPl = args['isPlaying'] as bool? ?? false;
      // Media3: STATE_READY = 3 (stream confirmado listo para reproducir)
      // No aceptar STATE_BUFFERING (2) solo, puede ser buffering de stream roto
      if (state == 3 || isPl) {
        logger.info('_tryOpenExo: state=$state isPl=$isPl -> OK');
        finish(true);
      }
    }));

    subs.add(exo.onError.listen((err) {
      // Solo marcar como fallo si no hay reproducción en curso
      if (!isPlaying.value && exoPositionMs.value == 0) {
        logger.severe('_tryOpenExo error: $err');
        finish(false);
      } else {
        // Error en stream que ya se reproduce (p.ej. segmento 4xx de thumbnail) - ignorar
        logger.warning('_tryOpenExo error ignorado (ya hay reproducción): $err');
      }
    }));

    // Timeout extendido a 12s para VidHide/CDNs lentos
    var ok = await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        // Al timeout, verificar si ExoPlayer ya está reproduciendo de facto
        if (isPlaying.value || exoPositionMs.value > 0 || exoIsPlaying.value) {
          logger.info('_tryOpenExo: timeout pero hay reproducción activa -> OK');
          return true;
        }
        // Verificar posición en el timer activo
        logger.warning('_tryOpenExo: timeout de 12s sin confirmación de reproducción');
        return false;
      },
    );

    // Verificación final: si exo ya avanzó en posición, es éxito
    if (!ok && (isPlaying.value || exoPositionMs.value > 0 || exoIsPlaying.value)) {
      logger.info('_tryOpenExo: marcado OK por estado actual post-timeout');
      ok = true;
    }

    for (final sub in subs) {
      await sub.cancel();
    }

    if (ok) {
      error.value = '';
      serverFailedMessage.value = '';
      isGettingWatchData.value = false;
    }

    return ok;
  }

  // Abre el stream en el motor adecuado (ExoPlayer en Android, mpv en otras plataformas).
  Future<bool> _openStream(String url, Map<String, String>? headers) async {
    if (isExoPlayerActive) {
      return await _tryOpenExo(url, headers);
    } else {
      return await _tryOpenPlayer(url, headers);
    }
  }

  /// Servidor HTTP en loopback que entrega el playlist HLS prefetcheado.
  ///
  /// No se puede entregar como archivo local: el demuxer HLS de FFmpeg lee
  /// solo el primer segmento de un playlist en disco y termina la
  /// reproducción al llegar a su final. Servido por HTTP funciona igual que
  /// el playlist remoto, pero sin descargar los ~156 KB sin comprimir.
  HttpServer? _hlsServer;
  String? _hlsPlaylistBody;

  /// Publica [body] en el servidor loopback y devuelve la URL para mpv.
  Future<String?> _serveHlsPlaylist(String body) async {
    try {
      _hlsPlaylistBody = body;
      var server = _hlsServer;
      if (server == null) {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        _hlsServer = server;
        server.listen((request) async {
          final response = request.response;
          final playlist = _hlsPlaylistBody;
          if (playlist == null) {
            response.statusCode = HttpStatus.notFound;
            await response.close();
            return;
          }
          response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          response.headers.set('Access-Control-Allow-Origin', '*');
          response.write(playlist);
          await response.close();
        });
      }
      return 'http://127.0.0.1:${server.port}/playlist.m3u8';
    } catch (e) {
      logger.warning('Servidor HLS local no disponible: $e');
      return null;
    }
  }

  /// Descarga el playlist HLS (maestro + media) con gzip y lo publica en un
  /// servidor loopback con URLs absolutas. FFmpeg descarga el playlist VOD
  /// completo (~156 KB) sin comprimir antes de abrir el primer segmento; con
  /// gzip son ~2.5 KB. Devuelve null si no es seguro/aplicable (live,
  /// cifrado, error).
  Future<String?> _prefetchHlsPlaylist(
    String url,
    Map<String, String>? headers,
  ) async {
    if (!url.contains('.m3u8')) return null;
    final client = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      headers: headers,
      followRedirects: true,
    ));
    try {
      final masterResp = await client.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final masterBody = masterResp.data;
      if (masterBody == null || !masterBody.contains('#EXTM3U')) return null;
      final masterUri = Uri.parse(masterResp.realUri.toString());

      var mediaBody = masterBody;
      var mediaUri = masterUri;

      if (masterBody.contains('#EXT-X-STREAM-INF')) {
        // Con pistas de audio separadas mpv necesita el master original.
        if (masterBody.contains('#EXT-X-MEDIA:')) return null;
        final lines = masterBody.split('\n');
        int? bestBw;
        String? bestUri;
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
          final bw = int.tryParse(
            RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '',
          );
          for (var j = i + 1; j < lines.length; j++) {
            final candidate = lines[j].trim();
            if (candidate.isEmpty || candidate.startsWith('#')) continue;
            if (bw != null && (bestBw == null || bw < bestBw)) {
              bestBw = bw;
              bestUri = candidate;
            }
            break;
          }
        }
        if (bestUri == null) return null;
        final mediaUrl = masterUri.resolve(bestUri).toString();
        final mediaResp = await client.get<String>(
          mediaUrl,
          options: Options(responseType: ResponseType.plain),
        );
        mediaBody = mediaResp.data ?? '';
        mediaUri = Uri.parse(mediaResp.realUri.toString());
      }

      // Solo VOD: un playlist en vivo debe refrescarse y no puede ser local.
      if (!mediaBody.contains('#EXTM3U') ||
          !mediaBody.contains('#EXT-X-ENDLIST')) {
        return null;
      }
      // Cifrado: las claves requieren reescritura; mejor no tocar.
      if (mediaBody.contains('#EXT-X-KEY')) return null;

      final out = <String>[];
      for (final raw in mediaBody.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) {
          if (line.startsWith('#EXT-X-MAP:')) {
            out.add(line.replaceAllMapped(
              RegExp(r'URI="([^"]+)"'),
              (m) => 'URI="${mediaUri.resolve(m.group(1)!)}"',
            ));
          } else {
            out.add(raw);
          }
          continue;
        }
        out.add(mediaUri.resolve(line).toString());
      }

      final dir = Directory(
        path.join(JiruHubDirectory.getCacheDirectory, 'hls_prefetch'),
      );
      // Los playlists de versiones anteriores se escribían en disco.
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
      return await _serveHlsPlaylist(out.join('\n'));
    } catch (e) {
      logger.warning('HLS prefetch falló (se usará URL original): $e');
      return null;
    } finally {
      client.close();
    }
  }

  // Intenta abrir el player con la URL dada.
  // Retorna true solo si el stream REALMENTE empieza a reproducirse.
  Future<bool> _tryOpenPlayer(String url, Map<String, String>? headers) async {
    final _tp0 = DateTime.now();
    logger.info('⏱ [player+0ms] _tryOpenPlayer START');

    if (url.startsWith('error://')) {
      logger.severe('URL de error recibida: $url');
      return false;
    }
    // En Linux se verifica si el host es alcanzable para prevenir el bug de SIGSEGV con EHOSTUNREACH.
    // En Windows se omite para eliminar 1-2 segundos de latencia de red innecesaria.
    if (Platform.isLinux && !await _isHostReachable(url)) {
      return false;
    }

    // Filtrar cabeceras internas (como X-Netu-Alts) para no enviarlas al CDN
    final cleanHeaders = headers == null
        ? null
        : (Map<String, String>.from(headers)
          ..removeWhere((k, _) => k.startsWith('X-Netu-')));

    // Configurar propiedades mpv de baja latencia ANTES de abrir el stream.
    // - 'referrer' asegura que cada petición de fragmento .ts lleve el Referer necesario para VidHide CDN.
    // - 'demuxer-lavf-o reconnect=0' evita el bucle de reconexión al llegar al
    //   EOF del playlist HLS VOD (~20s de espera antes del primer segmento).
    // - 'demuxer-lavf-analyzeduration 1.0' / 'probesize 1MB' permiten detectar
    //   correctamente los parámetros del audio AAC.
    // - 'cache-pause-initial no' arranca en cuanto el primer frame está decodificado.
    try {
      final nativePlayer = player.platform as NativePlayer;
      final referer = cleanHeaders?['Referer'] ?? cleanHeaders?['referer'];
      final ua = cleanHeaders?['User-Agent'] ?? cleanHeaders?['user-agent'];
      if (referer != null && referer.isNotEmpty) {
        await nativePlayer.setProperty('referrer', referer);
        logger.info('mpv referrer configurado: $referer');
      }
      if (ua != null && ua.isNotEmpty) {
        await nativePlayer.setProperty('user-agent', ua);
        logger.info('mpv user-agent configurado');
      }
      await nativePlayer.setProperty('demuxer-lavf-o', 'reconnect=0');
      await nativePlayer.setProperty('demuxer-lavf-analyzeduration', '1.0');
      await nativePlayer.setProperty('demuxer-lavf-probesize', '1048576');
      await nativePlayer.setProperty('demuxer-readahead-secs', '30');
      await nativePlayer.setProperty('cache-pause-initial', 'no');
      await nativePlayer.setProperty('network-timeout', '30');
      // Buffer amplio: con valores bajos (10s) el demuxer se queda sin datos
      // justo en cada cambio de segmento y la reproducción se detiene.
      await nativePlayer.setProperty('cache-secs', '60');
      // Forzar selección de calidad más baja inicialmente para arranque rápido
      await nativePlayer.setProperty('hls-bitrate', 'min');
      logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] mpv props set');
    } catch (e) {
      logger.warning('No se pudieron configurar propiedades mpv: $e');
    }

    // Prefetch del playlist HLS: con gzip baja de ~156 KB a ~2.5 KB. Si no es
    // aplicable o falla, se usa la URL original sin penalizar el arranque.
    var playUrl = url;
    if (url.contains('.m3u8')) {
      final pf0 = DateTime.now();
      final localPlaylist = await _prefetchHlsPlaylist(url, cleanHeaders);
      final pfMs = DateTime.now().difference(pf0).inMilliseconds;
      if (localPlaylist != null) {
        playUrl = localPlaylist;
        logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] HLS prefetch OK en ${pfMs}ms');
      } else {
        logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] HLS prefetch omitido en ${pfMs}ms');
      }
    }

    try {
      logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] player.open() START');
      await player.open(Media(playUrl, httpHeaders: cleanHeaders));
      logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] player.open() RETURNED (stream abierto, esperando playback)');
    } catch (e) {
      logger.severe('player.open error: $e');
      return false;
    }

    final completer = Completer<bool>();
    final subs = <StreamSubscription>[];
    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    // Detección instantánea del primer frame decodificado (equivalente a onRenderedFirstFrame en ExoPlayer)
    subs.add(player.stream.width.listen((w) {
      if (w != null && w > 0) {
        logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] primer frame renderizado ($w px) -> OK');
        finish(true);
      }
    }));
    subs.add(player.stream.playing.listen((playing) {
      if (playing) {
        logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] playing=true -> OK');
        finish(true);
      }
    }));
    subs.add(player.stream.duration.listen((d) {
      if (d > const Duration(seconds: 1)) {
        logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] duration=${d.inSeconds}s -> OK');
        finish(true);
      }
    }));
    subs.add(player.stream.position.listen((p) {
      if (p.inSeconds > 0) {
        logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] position=${p.inSeconds}s -> OK');
        finish(true);
      }
    }));
    // Solo fallar por error si NO hay reproducción o decodificación en curso.
    subs.add(player.stream.error.listen((errMsg) {
      final alreadyPlaying = player.state.playing ||
          player.state.position.inSeconds > 0 ||
          player.state.duration.inSeconds > 1 ||
          (player.state.width ?? 0) > 0;
      if (!alreadyPlaying) {
        logger.severe('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] error sin reproducción activa: $errMsg');
        finish(false);
      } else {
        logger.warning('_tryOpenPlayer error ignorado (reproducción activa): $errMsg');
      }
    }));

      var ok = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          if (player.state.playing ||
              player.state.position.inSeconds > 0 ||
              (player.state.width ?? 0) > 0) {
            logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] timeout pero reproducción activa -> OK');
            return true;
          }
          logger.warning('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] TIMEOUT sin reproducción — FALLO');
          return false;
        },
      );

    if (!ok && (isPlaying.value || position.value.inSeconds > 0 || (player.state.width ?? 0) > 0)) {
      logger.info('_tryOpenPlayer: marcado OK por estado activo post-timeout');
      ok = true;
    }

    for (final sub in subs) {
      await sub.cancel();
    }

    logger.info('⏱ [player+${DateTime.now().difference(_tp0).inMilliseconds}ms] _tryOpenPlayer END — ok=$ok');

    if (ok) {
      error.value = '';
      serverFailedMessage.value = '';
      isGettingWatchData.value = false;
    } else {
      logger.severe('El stream no arrancó: $url');
      try {
        await player.stop();
      } catch (_) {}
    }
    return ok;
  }

  // Inicializa mpv con una fuente local de video negro (sin red).
  Future<void> _safePlayerInit() async {
    try {
      await player.open(
        Media('av://lavfi:color=black:size=2x2:rate=1'),
        play: false,
      );
      await Future.delayed(const Duration(milliseconds: 300));
      await player.stop();
      await Future.delayed(const Duration(milliseconds: 500));
      logger.info('_safePlayerInit completado');
    } catch (e) {
      logger.severe('_safePlayerInit error: $e');
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        await player.stop();
      } catch (_) {}
    }
  }

  // 播放器相关操作
  playOrPause() async {
    if (isExoPlayerActive) {
      final willPlay = !isPlaying.value;
      await setExoPlayWhenReady(willPlay);
      return;
    }
    if (dlnaDevice.value == null) {
      player.playOrPause();
      return;
    }
    if (isPlaying.value) {
      await dlnaDevice.value!.pause();
    } else {
      await dlnaDevice.value!.play();
    }
  }

  seek(Duration duration) async {
    if (isExoPlayerActive) {
      await seekExoMs(duration.inMilliseconds);
      return;
    }
    if (dlnaDevice.value == null) {
      player.seek(duration);
      return;
    }
    final curr = await dlnaDevice.value!.position();
    final diff = duration - position.value;
    await dlnaDevice.value!.seekByCurrent(curr, diff.inSeconds);
  }
}

class Message {
  final Widget child;
  final Duration time;
  Message(this.child, {this.time = const Duration(seconds: 3)});
}
