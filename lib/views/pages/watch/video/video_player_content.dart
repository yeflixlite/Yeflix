import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jiruhub/controllers/watch/video_controller.dart';
import 'package:jiruhub/utils/exo_player_view.dart';
import 'package:jiruhub/views/pages/watch/video/video_player_desktop_controls.dart';
import 'package:jiruhub/views/pages/watch/video/video_player_mobile_controls.dart';

/// Contenido del reproductor.
///
/// En Android renderiza [ExoPlayerView] (Media3 ExoPlayer nativo) como motor
/// principal de reproducción. En las demás plataformas se conserva
/// `media_kit_video.Video` (mpv) para no romper escritorio (Windows/Linux).
class VideoPlayerConten extends StatelessWidget {
  const VideoPlayerConten({
    super.key,
    required this.tag,
  });
  final String tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<VideoPlayerController>(tag: tag);
    if (Platform.isAndroid) {
      // Android: ExoPlayer nativo embebido vía AndroidView con controles completos superpuestos.
      return Stack(
        fit: StackFit.expand,
        children: [
          ExoPlayerView(
            tag: tag,
            sourceUrl: c.exoSourceUrl.value,
            headers: c.exoHeaders.value,
            onError: (message) => c.onExoError(message),
            onStateChanged: (playing, state) => c.onExoStateChanged(playing, state),
            onLoadingChanged: (loading) => c.onExoLoadingChanged(loading),
          ),
          Positioned.fill(
            child: VideoPlayerMobileControls(
              controller: c,
            ),
          ),
        ],
      );
    }
    // Otras plataformas: media_kit (mpv) — motor existente.
    return Video(
      controller: c.videoController,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
      controls: (state) {
        if (Platform.isAndroid) {
          return VideoPlayerMobileControls(
            controller: c,
          );
        }
        return VideoPlayerDesktopControls(
          controller: c,
        );
      },
    );
  }
}
