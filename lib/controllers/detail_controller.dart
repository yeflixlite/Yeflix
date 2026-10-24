// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_windows_webview/flutter_windows_webview.dart';
import 'package:get/get.dart';
import 'package:jiruhub/data/providers/tmdb_provider.dart';
import 'package:jiruhub/models/index.dart';
import 'package:jiruhub/models/download.dart';
import 'package:jiruhub/data/services/download_service.dart';
import 'package:jiruhub/services/source_provider.dart';
import 'package:jiruhub/views/dialogs/tmdb_binding.dart';
import 'package:jiruhub/controllers/home_controller.dart';
import 'package:jiruhub/controllers/main_controller.dart';
import 'package:jiruhub/views/pages/watch/watch_page.dart';
import 'package:jiruhub/router/router.dart';
import 'package:jiruhub/data/services/database_service.dart';
import 'package:jiruhub/utils/extension.dart';
import 'package:jiruhub/data/services/extension_service.dart';
import 'package:jiruhub/utils/external_player.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';
import 'package:jiruhub/views/widgets/messenger.dart';

class DetailPageController extends GetxController {
  DetailPageController({
    required this.package,
    required this.url,
    this.heroTag,
  });

  final String package;
  final String url;
  final String? heroTag;

  ScrollController scrollController = ScrollController();

  final RxBool isFavorite = false.obs;
  final Rx<ExtensionDetail?> data = Rx(null);
  final Rx<History?> history = Rx(null);
  final RxString error = ''.obs;
  final RxBool isLoading = true.obs;
  final RxInt selectEpGroup = 0.obs;
  final RxString aniListID = ''.obs;
  final Rx<TMDBDetail?> tmdb = Rx(null);
  final Rx<ExtensionService?> runtime = Rx(null);
  ExtensionType get type =>
      runtime.value?.extension.type ?? ExtensionType.bangumi;
  Extension? get extension => runtime.value?.extension;

  ExtensionDetail? get detail => data.value;
  set detail(ExtensionDetail? value) => data.value = value;

  TMDBDetail? get tmdbDetail => tmdb.value;
  set tmdbDetail(TMDBDetail? value) => tmdb.value = value;

  String? get backgorund {
    String? bg;
    if (tmdbDetail != null && tmdbDetail!.backdrop != null) {
      bg = TmdbApi.getImageUrl(tmdbDetail!.backdrop!) ?? '';
    } else {
      bg = detail?.cover;
    }
    return bg;
  }

  JiruHubDetail? _miruDetail;

  int _tmdbID = -1;

  final _flyoutController = fluent.FlyoutController();

  @override
  void onInit() {
    onRefresh();
    Get.find<MainController>().setAcitons([
      fluent.IconButton(
        icon: const Icon(fluent.FluentIcons.pop_expand),
        onPressed: () async {
          final webview = FlutterWindowsWebview();
          await webview.setUA(JiruHubStorage.getUASetting());
          webview.launchWebview(
            extension!.webSite + url,
            WebviewOptions(
              onNavigation: (url) {
                if (Uri.parse(url).host != Uri.parse(extension!.webSite).host) {
                  return false;
                }
                webview.getCookies(url).then((value) async {
                  if (value.containsKey("cf_clearance")) {
                    debugPrint("验证通过");
                  }
                  runtime.value!.setCookie(
                    value.entries
                        .map((e) => '${e.key}=${e.value}')
                        .toList()
                        .join(';'),
                  );
                });

                return false;
              },
            ),
          );
        },
      ),
      fluent.FlyoutTarget(
        controller: _flyoutController,
        child: fluent.IconButton(
          icon: const Icon(fluent.FluentIcons.more),
          onPressed: () {
            _flyoutController.showFlyout(builder: (context) {
              return SizedBox(
                width: 300,
                child: Card(
                    child: fluent.Column(
                  mainAxisSize: fluent.MainAxisSize.min,
                  children: [
                    if (detail != null)
                      fluent.ListTile(
                        title: Text(
                          'detail.modify-tmdb-binding'.i18n,
                        ),
                        onPressed: () {
                          router.pop();
                          modifyTMDBBinding();
                        },
                      )
                  ],
                )),
              );
            });
          },
        ),
      )
    ]);
    super.onInit();
  }

  onRefresh() async {
    runtime.value = ExtensionUtils.runtimes[package];
    await refreshFavorite();
    try {
      _miruDetail = await DatabaseService.getJiruHubDetail(package, url);
      _tmdbID = _miruDetail?.tmdbID ?? -1;
      aniListID.value = _miruDetail?.aniListID ?? "";
      await getDetail();
      await getTMDBDetail();
      await getHistory();
      isLoading.value = false;
    } catch (e) {
      error.value = e.toString();
      rethrow;
    }
  }

  // 修改 tmdb 绑定
  modifyTMDBBinding() async {
    // 判断是否有 key
    if (JiruHubStorage.getSetting(SettingKey.tmdbKey) == "") {
      showPlatformSnackbar(
        context: currentContext,
        content: 'detail.tmdb-key-missing'.i18n,
        severity: fluent.InfoBarSeverity.error,
      );
      return;
    }

    dynamic data;
    if (Platform.isAndroid) {
      data = await Get.to(TMDBBinding(
        title: detail!.title,
      ));
    } else {
      data = await fluent.showDialog(
        context: currentContext,
        builder: (context) => TMDBBinding(title: detail!.title),
      );
    }
    if (data != null) {
      await getRemoteTMDBDetail(
        id: data['id'],
        mediaType: data['media_type'],
      );
    }
  }

  getDetail() async {
    if (_miruDetail != null) {
      detail = ExtensionDetail.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(_miruDetail!.data),
        ),
      );
      getRemoteDeatil();
    } else {
      await getRemoteDeatil();
    }
  }

  getRemoteDeatil() async {
    try {
      detail = await runtime.value!.detail(url);
      await DatabaseService.putJiruHubDetail(
        package,
        url,
        detail!,
        tmdbID: _tmdbID,
        anilistID: aniListID.value,
      );
    } catch (e) {
      // 弹出错误信息
      if (runtime.value == null) {
        final content = FlutterI18n.translate(
          currentContext,
          'common.extension-missing',
          translationParams: {
            'package': package,
          },
        );
        showPlatformSnackbar(
          context: currentContext,
          content: content,
          severity: fluent.InfoBarSeverity.error,
        );
        throw content;
      } else {
        showPlatformSnackbar(
          context: currentContext,
          title: 'detail.get-lastest-data-error'.i18n,
          content: e.toString().split('\n')[0],
          severity: fluent.InfoBarSeverity.error,
        );
      }
      rethrow;
    }
  }

  getTMDBDetail() async {
    tmdbDetail = await DatabaseService.getTMDBDetail(_tmdbID);
    if (detail == null) {
      return;
    }
    if (tmdbDetail == null) {
      getRemoteTMDBDetail();
      return;
    }
    getRemoteTMDBDetail(id: tmdbDetail!.id, mediaType: tmdbDetail!.mediaType);
  }

  getRemoteTMDBDetail({int? id, String? mediaType}) async {
    if (id != null && mediaType != null) {
      tmdbDetail = await TmdbApi.getDetail(id, mediaType);
      if (tmdbDetail == null) {
        return;
      }
    } else {
      tmdbDetail = await TmdbApi.getDetailBySearch(detail!.title);
      if (tmdbDetail == null) {
        return;
      }
    }
    _tmdbID = await DatabaseService.putTMDBDetail(
      tmdbDetail!.id,
      tmdbDetail!,
      tmdbDetail!.mediaType,
    );
    // 更新 id
    await DatabaseService.putJiruHubDetail(
      package,
      url,
      detail!,
      tmdbID: _tmdbID,
      anilistID: aniListID.value,
    );
  }

  saveAniListIds() async {
    await DatabaseService.putJiruHubDetail(
      package,
      url,
      detail!,
      anilistID: aniListID.value,
    );
  }

  getHistory() async {
    // 获取历史记录
    final history_ = await DatabaseService.getHistoryByPackageAndUrl(
      package,
      url,
    );
    if (history_ != null) {
      // 并且剧集的数量大于历史记录的剧集列表数量 防止历史记录超出剧集列表数量
      if (history_.episodeGroupId < detail!.episodes!.length) {
        history.value = history_;
        selectEpGroup.value = history_.episodeGroupId;
      }
    }
  }

  refreshFavorite() async {
    isFavorite.value = await DatabaseService.isFavorite(
      package: package,
      url: url,
    );
  }

  toggleFavorite() async {
    if (detail == null) {
      return;
    }
    try {
      await DatabaseService.toggleFavorite(
        package: package,
        url: url,
        cover: detail!.cover,
        name: detail!.title,
      );
    } catch (e) {
      showPlatformSnackbar(
        context: currentContext,
        content: e.toString().split('\n')[0],
        severity: fluent.InfoBarSeverity.error,
      );
      rethrow;
    }
    await refreshFavorite();
    Get.find<HomePageController>().onRefresh();
  }

  Future<void> watchWithPicker(BuildContext context) async {
    final groups = detail?.episodes;
    if (groups == null || groups.isEmpty) return;
    if (groups.length == 1) {
      goWatch(context, groups[0].urls, 0, 0);
      return;
    }

    int? picked;
    if (Platform.isAndroid) {
      picked = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: const Color(0xFF17171B),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Elige temporada o idioma",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: groups.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.play_circle_outline),
                    title: Text(groups[i].title),
                    subtitle: Text(
                      groups[i].urls.length == 1
                          ? "1 opción"
                          : "${groups[i].urls.length} opciones",
                    ),
                    onTap: () => Navigator.of(ctx).pop(i),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      picked = await fluent.showDialog<int>(
        context: context,
        builder: (ctx) => fluent.ContentDialog(
          title: const Text("Elige temporada o idioma"),
          content: SizedBox(
            width: 340,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: groups.length,
              itemBuilder: (_, i) => fluent.ListTile(
                title: Text(groups[i].title),
                subtitle: Text("${groups[i].urls.length} opciones"),
                onPressed: () => Navigator.of(ctx).pop(i),
              ),
            ),
          ),
          actions: [
            fluent.Button(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancelar"),
            ),
          ],
        ),
      );
    }

    if (picked == null) return;
    goWatch(context, groups[picked].urls, 0, picked);
  }

  goWatch(
    BuildContext context,
    List<ExtensionEpisode> urls,
    int index,
    int selectEpGroup,
  ) async {
    if (runtime.value == null) {
      showPlatformSnackbar(
        context: currentContext,
        content: FlutterI18n.translate(
          currentContext,
          'common.extension-missing',
          translationParams: {
            'package': package,
          },
        ),
        severity: fluent.InfoBarSeverity.error,
      );
      return;
    }

    if (type == ExtensionType.bangumi) {
      final player = JiruHubStorage.getSetting(SettingKey.videoPlayer);

      if (player != 'built-in') {
        showPlatformSnackbar(
          context: currentContext,
          content: FlutterI18n.translate(
            currentContext,
            'external-player-launching',
            translationParams: {
              'player': player,
            },
          ),
        );
        late ExtensionBangumiWatch watchData;
        try {
          watchData = await runtime.value!.watch(urls[index].url)
              as ExtensionBangumiWatch;
        } catch (e) {
          showPlatformSnackbar(
            context: currentContext,
            content: e.toString().split('\n')[0],
            severity: fluent.InfoBarSeverity.error,
          );
          return;
        }
        try {
          if (GetPlatform.isMobile) {
            await launchMobileExternalPlayer(watchData.url, player);
            return;
          }
          await launchDesktopExternalPlayer(watchData.url, player,
              watchData.headers ?? {}, watchData.subtitles ?? []);
          return;
        } catch (e) {
          showPlatformSnackbar(
            context: currentContext,
            content: e.toString().split('\n')[0],
            severity: fluent.InfoBarSeverity.error,
          );
        }
      }
    }

    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: ((context, animation, secondaryAnimation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.ease,
              ),
            ),
            child: WatchPage(
              cover: detail!.cover,
              playList: urls,
              package: package,
              playerIndex: index,
              title: detail!.title,
              episodeGroupId: selectEpGroup,
              detailUrl: url,
              anilistID: aniListID.value,
            ),
          );
        }),
      ),
    );
  }

  // ------------------------------------------------------------------ descargas offline

  /// Obtiene los servidores disponibles para un episodio (nombre -> embed URL)
  /// a partir de la cabecera X-Servers de la extension.
  Future<Map<String, String>> getEpisodeServers(String episodeUrl) async {
    if (runtime.value == null) return {};
    try {
      final watchData = await runtime.value!.watch(episodeUrl) as ExtensionBangumiWatch;
      final headers = watchData.headers ?? {};
      final servers = <String, String>{};
      if (headers.containsKey('X-Servers')) {
        try {
          final parsed = jsonDecode(headers['X-Servers']!);
          if (parsed is Map) {
            parsed.forEach((k, v) => servers[k.toString()] = v.toString());
          }
        } catch (_) {}
      }
      return servers;
    } catch (e) {
      error.value = e.toString();
      return {};
    }
  }

  /// Resuelve una fuente de descarga para un servidor dado.
  Future<SourceResult> resolveDownloadSource(
    String embedUrl,
    String serverName,
  ) async {
    final lower = serverName.toLowerCase();
    final offlineCompatible =
        lower.contains('streamwish') ||
        lower.contains('vidhide') ||
        lower.contains('voe') ||
        lower.contains('byse') ||
        lower.contains('filemoon');
    final provider = ExtensionSourceProvider(
      serverName: serverName,
      serverType: lower,
      offlineCompatible: offlineCompatible,
      resolveWatch: (u) async =>
          (await runtime.value!.watch(u) as ExtensionBangumiWatch).toJson(),
    );
    return provider.resolve(embedUrl);
  }

  /// Inicia la descarga de un episodio o pelicula.
  Future<void> startDownload({
    required String episodeUrl,
    required String serverName,
    required String sourceUrl,
    required String sourceType,
    required bool isHls,
    required Map<String, String>? headers,
    required String quality,
    String? qualityLabel,
    String? episodeName,
    int? episodeIndex,
  }) async {
    if (detail == null) return;
    final isMovie = detail!.episodes == null || detail!.episodes!.isEmpty;
    await Get.find<DownloadService>().startDownload(
      package: package,
      title: detail!.title,
      contentType: isMovie ? DownloadContentType.movie : DownloadContentType.episode,
      detailUrl: url,
      episodeName: episodeName ?? (isMovie ? null : episodeUrl),
      episodeIndex: episodeIndex,
      serverName: serverName,
      serverType: serverName.toLowerCase(),
      sourceUrl: sourceUrl,
      sourceType: sourceType,
      isHls: isHls,
      headers: headers,
      quality: quality,
      qualityLabel: qualityLabel,
    );
  }

  // ------------------------------------------------------------------ flujo de descarga por episodio

  /// Abre el selector de servidor e inicia la descarga de un episodio.
  Future<void> downloadEpisode(
    BuildContext context,
    ExtensionEpisode episode, {
    int? episodeIndex,
  }) async {
    if (runtime.value == null || detail == null) return;
    final servers = await getEpisodeServers(episode.url);
    if (servers.isEmpty) {
      showPlatformSnackbar(
        context: context,
        content: 'offline.no-servers'.i18n,
        severity: fluent.InfoBarSeverity.error,
      );
      return;
    }

    String? pickedName;
    await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('offline.choose-server'.i18n),
            ),
            ...servers.keys.map((name) => ListTile(
                  title: Text(name),
                  onTap: () => Navigator.pop(ctx, name),
                )),
          ],
        ),
      ),
    ).then((value) => pickedName = value);

    final picked = pickedName;
    if (picked == null) return;
    final embedUrl = servers[picked]!;

    final result = await resolveDownloadSource(embedUrl, picked);
    if (!result.isPlayable) {
      showPlatformSnackbar(
        context: context,
        content: result.errorReason ?? 'offline.source-unavailable'.i18n,
        severity: fluent.InfoBarSeverity.error,
      );
      return;
    }

    final qualityLabel = result.qualities.isNotEmpty
        ? result.qualities.first.label
        : 'offline.quality-auto'.i18n;
    final qualityUrl = result.qualities.isNotEmpty
        ? result.qualities.first.url
        : result.playbackUrl!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('offline.confirm-download'.i18n),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(offlineServerLabel(picked)),
            Text(
              '${'offline.quality'.i18n}: $qualityLabel',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.i18n),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('offline.download'.i18n),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await startDownload(
      episodeUrl: episode.url,
      serverName: picked,
      sourceUrl: qualityUrl,
      sourceType: result.sourceKind == SourceKind.hls ? 'hls' : 'mp4',
      isHls: result.sourceKind == SourceKind.hls,
      headers: result.headers,
      quality: qualityLabel ?? 'offline.quality-auto'.i18n,
      qualityLabel: qualityLabel,
      episodeName: episode.name,
      episodeIndex: episodeIndex,
    );
  }

  String offlineServerLabel(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('streamwish')) return 'offline.server-streamwish'.i18n;
    if (lower.contains('vidhide')) return 'offline.server-vidhide'.i18n;
    if (lower.contains('voe')) return 'offline.server-voe'.i18n;
    return name;
  }

  @override
  void onClose() {
    scrollController.dispose();
    Get.find<MainController>().setAcitons([]);
    super.onClose();
  }
}
