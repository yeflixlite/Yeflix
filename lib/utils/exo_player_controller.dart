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

import 'package:flutter/foundation.dart';
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
  final _viewAttachedController = StreamController<void>.broadcast();

  Stream<String> get onError => _errorController.stream;
  Stream<Map<String, dynamic>> get onStateChanged => _stateController.stream;
  Stream<bool> get onLoadingChanged => _loadingController.stream;
  Stream<void> get onRenderedFirstFrame => _renderedFirstFrameController.stream;
  Stream<bool> get onIsPlayingChanged => _isPlayingController.stream;

  /// Se emite cada vez que se crea una instancia nativa nueva del reproductor.
  ///
  /// Ocurre al montar la PlatformView por primera vez y también si Android o
  /// Flutter la recrean (rotación, vuelta desde segundo plano, cambio de
  /// layout). Sirve para reabrir la fuente en la última posición en lugar de
  /// dejar la pantalla en negro o empezar de cero.
  Stream<void> get onViewAttached => _viewAttachedController.stream;

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
      case 'onViewAttached':
        _viewAttachedController.add(null);
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
    int? maxVideoHeight,
    int? maxVideoBitrate,
  }) async {
    if (_channel == null) return;
    final arguments = {
      'url': url,
      'headers': headers ?? <String, String>{},
      if (positionMs != null && positionMs > 0) 'positionMs': positionMs,
      if (mimeType != null && mimeType.isNotEmpty) 'mimeType': mimeType,
      if (maxVideoHeight != null && maxVideoHeight > 0)
        'maxVideoHeight': maxVideoHeight,
      if (maxVideoBitrate != null && maxVideoBitrate > 0)
        'maxVideoBitrate': maxVideoBitrate,
    };
    // La PlatformView puede tardar unos frames en registrar su handler
    // nativo (p. ej. al abrir un archivo local desde onInit). Se reintenta
    // durante ~1.5 s en vez de fallar y mostrar un error de reproducción.
    for (var attempt = 0; attempt < 15; attempt++) {
      try {
        await _channel!.invokeMethod('setSource', arguments);
        return;
      } on MissingPluginException {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_channel == null) return;
      }
    }
    // No se pudo entregar la fuente. La vista nativa puede crearse mas tarde:
    // su evento `onViewAttached` reabre la fuente guardada en el controlador.
    debugPrint(
      '⏱ [exo] setSource no entregado (vista nativa aun no disponible): $tag',
    );
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

  /// Fuerza un reintento de la carga actual sin perder la posición.
  ///
  /// Se usa cuando el reproductor lleva demasiado tiempo sin avanzar por un
  /// corte temporal del CDN. Si ExoPlayer está en error, `prepare()` vuelve a
  /// intentarlo; si está atascado en buffering, el seek cancela la petición
  /// colgada y pide de nuevo el segmento actual.
  Future<void> recover({int positionMs = 0}) async {
    if (_channel == null) return;
    await _channel!.invokeMethod('recover', {
      if (positionMs > 0) 'positionMs': positionMs,
    });
  }

  /// Establece el volumen (0.0-1.0).
  Future<void> setVolume(double volume) async {
    if (_channel == null) return;
    await _channel!.invokeMethod('setVolume', {'volume': volume});
  }

  /// Activa o desactiva las pistas de texto nativas de ExoPlayer.
  ///
  /// Se desactivan cuando Yeflix dibuja un subtítulo externo en Flutter para
  /// evitar que aparezcan dos subtítulos a la vez. No re-prepara la fuente.
  Future<void> setSubtitlesEnabled(bool enabled) async {
    if (_channel == null) return;
    try {
      await _channel!
          .invokeMethod('setSubtitlesEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // La PlatformView todavía no está montada.
    }
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
    await _viewAttachedController.close();
    if (_channel != null) {
      await _channel!.invokeMethod('dispose');
      _channel?.setMethodCallHandler(null);
      _channel = null;
    }
  }
}
