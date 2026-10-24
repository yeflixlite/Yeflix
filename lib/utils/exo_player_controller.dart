/// Controlador nativo de ExoPlayer para Android.
///
/// Envuelve el [MethodChannel] `com.yeflix.app/exoplayer_<tag>` y expone las
/// operaciones de reproducción (setSource, play, pause, seek, volumen) así como
/// streams de eventos (error, cambio de estado, carga). Permite que
/// [VideoPlayerController] maneje ExoPlayer en Android sin depender del estado
/// interno del widget [ExoPlayerView].
library jiruhub.exo_player_controller;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Eventos emitidos por el reproductor nativo ExoPlayer.
enum ExoPlayerEvent {
  error,
  stateChanged,
  loadingChanged,
}

/// Wrapper ligero sobre el canal de métodos de ExoPlayer (solo Android).
class ExoPlayerNativeController {
  ExoPlayerNativeController({required this.tag});

  final String tag;
  static const String _channelPrefix = 'com.yeflix.app/exoplayer_';
  String get channelName => '$_channelPrefix$tag';

  MethodChannel? _channel;

  /// Streams de eventos para la UI.
  final _errorController = StreamController<String>.broadcast();
  final _stateController = StreamController<Map<String, dynamic>>.broadcast();
  final _loadingController = StreamController<bool>.broadcast();
  final _renderedFirstFrameController = StreamController<void>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();

  Stream<String> get onError => _errorController.stream;
  Stream<Map<String, dynamic>> get onStateChanged => _stateController.stream;
  Stream<bool> get onLoadingChanged => _loadingController.stream;
  Stream<void> get onRenderedFirstFrame => _renderedFirstFrameController.stream;
  Stream<bool> get onIsPlayingChanged => _isPlayingController.stream;

  bool get isAndroid => Platform.isAndroid;

  void init() {
    if (!Platform.isAndroid) return;
    _channel = MethodChannel(channelName)
      ..setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onPlayerError':
        _errorController.add(call.arguments as String? ?? 'unknown_error');
        break;
      case 'onRenderedFirstFrame':
        _renderedFirstFrameController.add(null);
        break;
      case 'onIsPlayingChanged':
        _isPlayingController.add(call.arguments as bool? ?? false);
        break;
      case 'onStateChanged':
        final args = call.arguments as Map<dynamic, dynamic>?;
        _stateController.add({
          'playWhenReady': args?['playWhenReady'] == true,
          'playbackState': args?['playbackState'] as int? ?? 0,
          'isPlaying': args?['isPlaying'] == true,
        });
        break;
      case 'onLoadingChanged':
        _loadingController.add(call.arguments as bool? ?? false);
        break;
    }
    return null;
  }

  /// Setea la fuente de reproducción (URL + cabeceras autorizadas + posición opcional).
  Future<void> setSource({
    required String url,
    Map<String, String>? headers,
    int? positionMs,
    String? mimeType,
  }) async {
    if (_channel == null) return;
    await _channel!.invokeMethod('setSource', {
      'url': url,
      'headers': headers ?? <String, String>{},
      if (positionMs != null && positionMs > 0) 'positionMs': positionMs,
      if (mimeType != null && mimeType.isNotEmpty) 'mimeType': mimeType,
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

  /// Consulta posición actual (ms). -1 si no disponible.
  Future<int> positionMs() async {
    if (_channel == null) return -1;
    final result = await _channel!.invokeMethod('positionMs');
    return (result as int?) ?? -1;
  }

  /// Consulta duración (ms). -1 si no disponible.
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

  /// Libera el reproductor y sus canales.
  Future<void> dispose() async {
    await _errorController.close();
    await _stateController.close();
    await _loadingController.close();
    if (_channel != null) {
      await _channel!.invokeMethod('dispose');
      _channel?.setMethodCallHandler(null);
      _channel = null;
    }
  }
}
