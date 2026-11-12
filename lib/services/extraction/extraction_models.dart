/// Modelos compartidos por el extractor directo de fuentes (solo Android).
///
/// Este modulo no depende de la extension JavaScript: recibe HTML/JS ya
/// descargado y devuelve una fuente reproducible para ExoPlayer junto con los
/// tiempos de cada etapa.
library jiruhub.extraction_models;

import 'package:jiruhub/services/source_provider.dart' show SourceKind;

/// User-Agent usado para las paginas de los reproductores.
const String kExtractionUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Servidores que tienen extractor directo propio.
enum ExtractionServer { vidhide, streamwish }

extension ExtractionServerLabel on ExtractionServer {
  String get label {
    switch (this) {
      case ExtractionServer.vidhide:
        return 'VidHide';
      case ExtractionServer.streamwish:
        return 'StreamWish';
    }
  }
}

/// Fuente de video obtenida sin ejecutar la extension.
class ExtractedSource {
  const ExtractedSource({
    required this.url,
    required this.kind,
    required this.server,
    required this.headers,
    this.referer,
  });

  /// URL de reproduccion (MP4 o playlist HLS).
  final String url;

  /// Tipo detectado de la fuente.
  final SourceKind kind;

  /// Servidor que la produjo.
  final ExtractionServer server;

  /// Cabeceras legitimas necesarias para el CDN (Referer/User-Agent).
  final Map<String, String> headers;

  /// Referer de la pagina del reproductor, si se conoce.
  final String? referer;

  bool get isHls => kind == SourceKind.hls;

  bool get isPlayable {
    final u = url.trim();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  /// MIME explicito solo cuando ExoPlayer no puede inferirlo de la URL.
  ///
  /// El reproductor nativo ya reconoce `.m3u8` y `/hls/`; para playlists con
  /// nombres como `master.txt` o `playlist.txt` se envia el MIME de HLS.
  String? get exoMimeType {
    if (!isHls) return null;
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('/hls/')) return null;
    return 'application/x-mpegURL';
  }
}

/// Resultado de una descarga HTTP intermedia.
class PageFetch {
  const PageFetch({
    this.body,
    this.statusCode,
    this.ms = 0,
    this.error,
  });

  final String? body;
  final int? statusCode;
  final int ms;
  final String? error;

  bool get ok =>
      body != null &&
      body!.isNotEmpty &&
      (statusCode == null || statusCode! < 400);
}

/// Firma de la funcion que descarga una pagina con cabeceras controladas.
typedef PageFetcher = Future<PageFetch> Function(
  String url,
  Map<String, String> headers,
);

/// Tiempos medidos por etapa. Se registran por separado en el log.
class ExtractionTimings {
  /// Tiempo total de red de la(s) pagina(s) del reproductor.
  int pageMs = 0;

  /// Analisis del HTML (scripts, atributos, candidatos).
  int parseMs = 0;

  /// Desempaquetado del JavaScript ofuscado.
  int unpackMs = 0;

  /// Extraccion de la URL final (MP4/HLS).
  int extractMs = 0;

  /// Tiempo total de la resolucion directa.
  int totalMs = 0;

  /// Numero de solicitudes HTTP realizadas.
  int requests = 0;
}

/// Resultado completo de intentar una extraccion directa.
class ExtractionOutcome {
  const ExtractionOutcome({
    required this.timings,
    this.source,
    this.failure,
    this.host,
  });

  final ExtractionTimings timings;
  final ExtractedSource? source;
  final String? failure;
  final String? host;

  bool get ok => source != null;
}
