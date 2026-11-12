/// Utilidades de analisis HTML/JS para localizar la fuente de video.
///
/// Se combinan varios patrones (atributo `file:` del reproductor, URLs
/// absolutas y rutas relativas `/stream/...`) para no depender de una unica
/// expresion regular. Las expresiones son solo el ultimo paso; cuando hay
/// JavaScript empaquetado se analiza primero con [JsUnpacker].
library jiruhub.html_source_scanner;

import 'package:jiruhub/services/source_provider.dart' show SourceKind;

class HtmlSourceScanner {
  HtmlSourceScanner._();

  static final RegExp _hlsFile = RegExp(
    r'''file\s*:\s*["']([^"']*(?:\.m3u8|master\.txt|playlist\.txt|/hls/)[^"']*)["']''',
    caseSensitive: false,
  );
  static final RegExp _hlsAbsolute = RegExp(
    r'''["']((?:https?:)?//[^"'<>\s]+(?:\.m3u8|master\.txt|playlist\.txt)[^"'<>\s]*)["']''',
    caseSensitive: false,
  );
  static final RegExp _hlsPath = RegExp(
    r'''["'](/stream/[^"']+\.m3u8[^"']*)["']''',
    caseSensitive: false,
  );
  static final RegExp _mp4File = RegExp(
    r'''file\s*:\s*["']([^"']+\.mp4[^"']*)["']''',
    caseSensitive: false,
  );
  static final RegExp _mp4Absolute = RegExp(
    r'''["']((?:https?:)?//[^"'<>\s]+\.mp4[^"'<>\s]*)["']''',
    caseSensitive: false,
  );

  /// Limpia escapes habituales de los embeds (`\/`, `\u0026`, entidades).
  static String fixUrl(String value) {
    var s = value
        .replaceAll(r'\/', '/')
        .replaceAll(RegExp(r'\\u0026', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&#0?38;'), '&')
        .trim();
    if (s.startsWith('//')) s = 'https:$s';
    return s;
  }

  /// Devuelve `https://host` de una URL.
  static String originOf(String value) {
    final match = RegExp(r'^(https?://[^/]+)', caseSensitive: false)
        .firstMatch(value.trim());
    return match?.group(1) ?? '';
  }

  /// Convierte una URL relativa en absoluta usando [origin].
  static String absolutize(String origin, String url) {
    var s = fixUrl(url);
    if (s.isEmpty) return s;
    if (s.startsWith('//')) return '${_schemeOf(origin)}:$s';
    if (s.startsWith('/')) return '$origin$s';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return s;
  }

  /// Busca una fuente HLS en un fragmento de HTML/JS ya desempaquetado.
  static String? findHls(String text) {
    for (final pattern in [_hlsFile, _hlsAbsolute, _hlsPath]) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Busca una fuente MP4 en un fragmento de HTML/JS ya desempaquetado.
  static String? findMp4(String text) {
    for (final pattern in [_mp4File, _mp4Absolute]) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Clasifica una URL ya resuelta.
  static SourceKind kindOf(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') ||
        lower.contains('master.txt') ||
        lower.contains('playlist.txt') ||
        lower.contains('/hls/')) {
      return SourceKind.hls;
    }
    if (lower.contains('.mp4') ||
        lower.contains('.m4v') ||
        lower.contains('.mov')) {
      return SourceKind.mp4;
    }
    return SourceKind.unknown;
  }

  /// Detecta respuestas de "enlace caducado" de los servidores.
  static bool looksExpired(String html) => RegExp(
        r'no longer available|expired or has been deleted|file (?:was )?not found',
        caseSensitive: false,
      ).hasMatch(html);

  /// Detecta el desafio de Cloudflare.
  static bool looksBlocked(String html) =>
      html.contains('Just a moment') || html.contains('cf-challenge');

  /// Pagina intermedia que pide una segunda carga con cookie/referer.
  static bool needsReload(String html) =>
      html.length < 2000 &&
      (html.contains('Page is loading') || html.contains('Redirecting'));

  static String _schemeOf(String origin) {
    if (origin.startsWith('http://')) return 'http';
    return 'https';
  }
}
