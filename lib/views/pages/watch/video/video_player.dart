import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:jiruhub/models/extension.dart';
import 'package:jiruhub/controllers/watch/video_controller.dart';
import 'package:jiruhub/views/pages/watch/video/video_player_sidebar.dart';
import 'package:jiruhub/views/pages/watch/video/video_player_content.dart';
import 'package:jiruhub/data/services/extension_service.dart';
import 'package:jiruhub/views/widgets/platform_widget.dart';

class VideoPlayer extends StatefulWidget {
  const VideoPlayer({
    super.key,
    required this.playList,
    this.runtime,
    required this.episodeGroupId,
    required this.playerIndex,
    required this.title,
    required this.detailUrl,
    required this.anilistID,
    this.localFilePath,
  });

  final String title;
  final List<ExtensionEpisode> playList;
  final String detailUrl;
  final int playerIndex;
  final int episodeGroupId;
  final ExtensionService? runtime;
  final String anilistID;
  final String? localFilePath;

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  late VideoPlayerController _c;

  @override
  void initState() {
    _c = Get.put(
      VideoPlayerController(
        title: widget.title,
        playList: widget.playList,
        detailUrl: widget.detailUrl,
        playIndex: widget.playerIndex,
        episodeGroupId: widget.episodeGroupId,
        runtime: widget.runtime,
        anilistID: widget.anilistID,
        localFilePath: widget.localFilePath,
      ),
      tag: widget.title,
    );
    super.initState();
  }

  @override
  void dispose() {
    Get.delete<VideoPlayerController>(tag: widget.title);
    super.dispose();
  }

  /// Video + mensajes emergentes. Es la superficie que nunca debe cambiar de
  /// tamaño en Android: redimensionar la `AndroidView` de ExoPlayer obliga al
  /// reproductor nativo a rehacer la superficie y provoca recargas/parpadeos.
  ///
  /// El reproductor queda **fuera** de cualquier `Obx` que dependa de
  /// `showSidebar`: abrir o cerrar el menú no reconstruye esta rama, así que la
  /// PlatformView de ExoPlayer no se recrea y el video sigue reproduciéndose.
  Widget _buildPlayerSurface(double maxWidth) {
    return Stack(
      children: [
        VideoPlayerConten(tag: widget.title),
        // 消息弹出 (solo esta parte reacciona al mensaje actual)
        Obx(() {
          final message = _c.cuurentMessageWidget.value;
          if (message == null) return const SizedBox.shrink();
          return Positioned(
            left: 0,
            bottom: 100,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              constraints: BoxConstraints(
                maxHeight: 200,
                maxWidth: maxWidth,
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                ),
                child: message,
              ),
            ).animate().fade(),
          );
        }),
      ],
    );
  }

  /// En Android el panel se superpone al video en vez de encogerlo.
  ///
  /// El sidebar de escritorio vive en una `Row` y reduce el ancho del video.
  /// En Android eso redimensiona la PlatformView de ExoPlayer, lo que reinicia
  /// el buffering y deja el reproductor pequeño y con parpadeos. Al dibujarlo
  /// como overlay el video conserva su tamaño y su superficie.
  ///
  /// Solo el panel está dentro de un `Obx`; el reproductor no se reconstruye al
  /// abrir/cerrar el menú.
  Widget _buildAndroidContent(double maxWidth) {
    final sidebarWidth = math.min(maxWidth * 0.85, 360.0);
    // `SizedBox.expand` es obligatorio aquí: el `Obx` del panel devuelve un
    // `SizedBox.shrink()` (0x0) cuando está cerrado. Al ser el único hijo NO
    // posicionado del `Stack`, el Stack se encogía a 0x0 y el video (que va en
    // `Positioned.fill`) quedaba invisible: solo se veía el fondo gris del
    // Scaffold. Con el Stack expandido, el área del video siempre ocupa toda
    // la pantalla, con el panel abierto o cerrado.
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(child: _buildPlayerSurface(maxWidth)),
          Obx(() {
            if (!_c.showSidebar.value) return const SizedBox.shrink();
            return Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: sidebarWidth,
              child: Material(
                elevation: 12,
                color: Colors.black,
                child: SafeArea(
                  left: false,
                  child: VideoPlayerSidebar(
                    controller: _c,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDesktopContent(double maxWidth) {
    return Row(
      children: [
        AnimatedContainer(
          onEnd: () {
            _c.isOpenSidebar.value = _c.showSidebar.value;
          },
          width: _c.showSidebar.value ? maxWidth - 300 : maxWidth,
          duration: const Duration(milliseconds: 120),
          child: _buildPlayerSurface(maxWidth),
        ),
        if (_c.isOpenSidebar.value)
          Expanded(
            child: VideoPlayerSidebar(
              controller: _c,
            ),
          )
      ],
    );
  }

  _buildContent() {
    final maxWidth = MediaQuery.of(context).size.width;
    if (Platform.isAndroid) {
      // Android: el reproductor no depende de ningún estado reactivo, así que
      // no hace falta envolver todo en un `Obx` (evita reconstruir la
      // PlatformView de ExoPlayer al abrir el menú).
      return _buildAndroidContent(maxWidth);
    }
    return Obx(() => _buildDesktopContent(maxWidth));
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: (context) => Theme(
        data: ThemeData.dark(useMaterial3: true),
        child: Scaffold(body: _buildContent()),
      ),
      desktopBuilder: ((context) => _buildContent()),
    );
  }
}
