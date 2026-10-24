/// Vista de reproductor nativo ExoPlayer para Android, embebida vía [AndroidView].
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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget que muestra el reproductor nativo ExoPlayer en Android.
///
/// [tag] identifica la instancia (se usa en el nombre del canal de métodos).
/// Cuando [sourceUrl] cambia, se invoca automáticamente `setSource` en el
/// reproductor nativo.
class ExoPlayerView extends StatefulWidget {
  const ExoPlayerView({
    super.key,
    required this.tag,
    this.sourceUrl = '',
    this.headers = const {},
    this.onError,
    this.onStateChanged,
    this.onLoadingChanged,
  });

  final String tag;
  final String sourceUrl;
  final Map<String, String> headers;
  final void Function(String message)? onError;
  final void Function(bool playing, int state)? onStateChanged;
  final void Function(bool loading)? onLoadingChanged;

  static const String _channelPrefix = 'com.yeflix.app/exoplayer_';

  /// Nombre del canal de métodos para esta instancia.
  String get channelName => '$_channelPrefix$tag';

  @override
  State<ExoPlayerView> createState() => _ExoPlayerViewState();
}

class _ExoPlayerViewState extends State<ExoPlayerView> {
  MethodChannel? _channel;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _channel = MethodChannel(widget.channelName)
        ..setMethodCallHandler(_handleMethod);
    }
  }

  @override
  void didUpdateWidget(ExoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Platform.isAndroid &&
        widget.sourceUrl.isNotEmpty &&
        widget.sourceUrl != oldWidget.sourceUrl) {
      _applySource();
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onPlayerError':
        widget.onError?.call(call.arguments as String? ?? 'unknown_error');
        break;
      case 'onStateChanged':
        final args = call.arguments as Map<dynamic, dynamic>?;
        final playing = args?['playWhenReady'] == true;
        final state = args?['playbackState'] as int? ?? 0;
        widget.onStateChanged?.call(playing, state);
        break;
      case 'onLoadingChanged':
        widget.onLoadingChanged?.call(call.arguments as bool? ?? false);
        break;
    }
    return null;
  }

  Future<void> _applySource() async {
    if (_channel == null) return;
    await _channel!.invokeMethod('setSource', {
      'url': widget.sourceUrl,
      'headers': widget.headers,
    });
  }

  /// Reproduce o pausa.
  Future<void> setPlayWhenReady(bool value) async {
    if (_channel == null) return;
    await _channel!.invokeMethod(value ? 'play' : 'pause');
  }

  /// Busca a una posición (ms).
  Future<void> seekToMs(int positionMs) async {
    if (_channel == null) return;
    await _channel!.invokeMethod('seek', {'positionMs': positionMs});
  }

  /// Establece el volumen (0.0-1.0).
  Future<void> setVolume(double volume) async {
    if (_channel == null) return;
    await _channel!.invokeMethod('setVolume', {'volume': volume});
  }

  /// Libera el reproductor nativo.
  Future<void> disposePlayer() async {
    if (_channel == null) return;
    await _channel!.invokeMethod('dispose');
    _channel?.setMethodCallHandler(null);
    _channel = null;
  }

  /// Consulta posición actual (ms). Retorna -1 si no está disponible.
  Future<int> positionMs() async {
    if (_channel == null) return -1;
    final result = await _channel!.invokeMethod('positionMs');
    return (result as int?) ?? -1;
  }

  /// Consulta duración (ms). Retorna -1 si no está disponible.
  Future<int> durationMs() async {
    if (_channel == null) return -1;
    final result = await _channel!.invokeMethod('durationMs');
    return (result as int?) ?? -1;
  }

  /// Consulta si está reproduciendo.
  Future<bool> isPlaying() async {
    if (_channel == null) return false;
    final result = await _channel!.invokeMethod('isPlaying');
    return (result as bool?) ?? false;
  }

  @override
  void dispose() {
    disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }
    return AndroidView(
      viewType: 'com.yeflix.app/exoplayer',
      creationParams: <String, dynamic>{
        'channelName': widget.channelName,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
