/// Vista del reproductor nativo ExoPlayer para Android, embebida vía [AndroidView].
///
/// En Android se renderiza [PlayerView] de Media3 ExoPlayer. El canal de
/// métodos `com.yeflix.app/exoplayer_<tag>` permite controlar el reproductor
/// (setSource, play, pause, seek, ...) desde Flutter.
///
/// En plataformas no-Android (Windows/Linux/macOS) este widget devuelve un
/// contenedor vacío para que el reproductor existente (media_kit) siga siendo
/// el motor principal fuera de Android.
library jiruhub.exo_player_view;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Superficie del reproductor nativo ExoPlayer (solo Android).
///
/// Este widget es **únicamente la vista**: no envía `setSource` ni registra
/// handlers de canal. La fuente y el estado los controla
/// `ExoPlayerNativeController`, que es el único dueño del canal
/// `com.yeflix.app/exoplayer_<tag>`.
///
/// Antes el widget reenviaba la fuente en cada rebuild y lo hacía **sin** los
/// límites de pista (720p) con los que se abrió el video. El guard nativo de
/// idempotencia comparaba esos límites, no reconocía la petición como repetida
/// y volvía a preparar el video desde 0: pantalla negra al abrir el menú de
/// pistas y reinicio al cerrarlo.
class ExoPlayerView extends StatelessWidget {
  const ExoPlayerView({super.key, required this.tag});

  /// Identificador de la instancia (se usa en el nombre del canal).
  final String tag;

  static const String _channelPrefix = 'com.yeflix.app/exoplayer_';

  /// Nombre del canal de métodos para esta instancia.
  String get channelName => '$_channelPrefix$tag';

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }
    return AndroidView(
      viewType: 'com.yeflix.app/exoplayer',
      creationParams: <String, dynamic>{
        'channelName': channelName,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
