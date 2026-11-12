/// Extractor directo de VidHide / Earnvids.
///
/// Flujo:
/// 1. Construye la URL del reproductor con el identificador del embed.
/// 2. Descarga el HTML (host de origen primero; mirrors solo si falla).
/// 3. Si hay JavaScript empaquetado lo desempaqueta sin ejecutarlo.
/// 4. Localiza `file: "...m3u8"` (o MP4) y devuelve la fuente con sus
///    cabeceras legitimas.
library jiruhub.vidhide_extractor;

import 'package:jiruhub/services/extraction/extraction_models.dart';
import 'package:jiruhub/services/extraction/html_source_scanner.dart';
import 'package:jiruhub/services/extraction/js_unpacker.dart';
import 'package:jiruhub/services/source_provider.dart' show SourceKind;

class VidHideExtractor {
  VidHideExtractor(this._fetch);

  final PageFetcher _fetch;

  /// Mirrors conocidos, en el mismo orden que usa la extension.
  static const List<String> _mirrors = [
    'morencius.com',
    'minochinos.com',
    'callistanise.com',
    'vsharea.com',
    'vidhide.com',
  ];

  Future<ExtractionOutcome> extract(
    String embedUrl, {
    String? referer,
  }) async {
    final startedAt = DateTime.now();
    final timings = ExtractionTimings();
    final clean = HtmlSourceScanner.fixUrl(embedUrl).split('#').first;
    final uri = Uri.tryParse(clean);
    if (uri == null || uri.host.isEmpty) {
      return _fail(timings, 'URL invalida');
    }

    final id = _idOf(uri);
    if (id.isEmpty) {
      return _fail(timings, 'Sin identificador');
    }

    final search = uri.hasQuery ? '?${uri.query}' : '';
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    final originHost = uri.host.toLowerCase();

    final hosts = <String>[];
    if (originHost.isNotEmpty) hosts.add(originHost);
    for (final mirror in _mirrors) {
      if (hosts.length >= 4) break;
      if (!hosts.contains(mirror)) hosts.add(mirror);
    }

    String? lastFailure;
    for (final host in hosts) {
      final origin = '$scheme://$host';
      final pageUrl = '$origin/v/$id$search';
      final fetch = await _fetch(pageUrl, _pageHeaders('https://google.com/'));
      timings.requests++;
      timings.pageMs += fetch.ms;

      if (!fetch.ok) {
        lastFailure = fetch.error ?? 'HTTP ${fetch.statusCode}';
        continue;
      }

      var body = fetch.body!;
      if (HtmlSourceScanner.looksExpired(body)) {
        lastFailure = 'enlace caducado';
        continue;
      }
      if (HtmlSourceScanner.needsReload(body)) {
        final retry = await _fetch(pageUrl, _pageHeaders(pageUrl));
        timings.requests++;
        timings.pageMs += retry.ms;
        if (retry.ok) body = retry.body!;
      }
      if (HtmlSourceScanner.looksBlocked(body)) {
        lastFailure = 'Cloudflare';
        continue;
      }

      final source = _extractFromHtml(body, origin, timings);
      if (source != null) {
        timings.totalMs = DateTime.now().difference(startedAt).inMilliseconds;
        return ExtractionOutcome(
          source: source,
          timings: timings,
          host: host,
        );
      }
      lastFailure = 'sin fuente en HTML';
    }

    timings.totalMs = DateTime.now().difference(startedAt).inMilliseconds;
    return _fail(
      timings,
      lastFailure ?? 'sin fuente',
      hosts.isNotEmpty ? hosts.first : null,
    );
  }

  ExtractedSource? _extractFromHtml(
    String html,
    String origin,
    ExtractionTimings timings,
  ) {
    final parseWatch = Stopwatch()..start();

    String? unpacked;
    if (JsUnpacker.isPacked(html)) {
      final packed = JsUnpacker.locatePackedScript(html, 'links');
      final unpackWatch = Stopwatch()..start();
      unpacked = JsUnpacker.unpack(packed);
      timings.unpackMs += unpackWatch.elapsedMilliseconds;
    }

    final hasUnpacked = unpacked != null && unpacked.isNotEmpty;
    final primary = hasUnpacked ? unpacked : html;

    // VidHide publica `links = { hls4, hls3, hls2 }`. El orden del objeto NO
    // es el de preferencia: hls4 suele ser un playlist senuelo y hls3 puede
    // apuntar a un host muerto. La extension usa hls2 primero; el extractor
    // directo debe hacer lo mismo para no elegir una fuente inservible.
    var url = _parseLinks(primary, origin) ?? '';
    if (url.isEmpty && hasUnpacked) {
      url = _parseLinks(html, origin) ?? '';
    }
    if (url.isEmpty) {
      url = HtmlSourceScanner.findHls(primary) ?? '';
    }
    if (url.isEmpty && hasUnpacked) {
      url = HtmlSourceScanner.findHls(html) ?? '';
    }

    var kind = SourceKind.hls;
    if (url.isEmpty) {
      var mp4 = HtmlSourceScanner.findMp4(primary) ?? '';
      if (mp4.isEmpty && hasUnpacked) {
        mp4 = HtmlSourceScanner.findMp4(html) ?? '';
      }
      if (mp4.isNotEmpty) {
        url = mp4;
        kind = SourceKind.mp4;
      }
    }

    timings.parseMs += parseWatch.elapsedMilliseconds;
    if (url.isEmpty) return null;

    final absolute = HtmlSourceScanner.absolutize(origin, url);
    if (!absolute.startsWith('http')) return null;
    final detected = HtmlSourceScanner.kindOf(absolute);
    if (detected != SourceKind.unknown) kind = detected;

    return ExtractedSource(
      url: absolute,
      kind: kind,
      server: ExtractionServer.vidhide,
      headers: {
        'Referer': '$origin/',
        'User-Agent': kExtractionUserAgent,
      },
      referer: '$origin/',
    );
  }

  /// Extrae `links = { hls2: "...", hls3: "...", hls4: "..." }` del JS ya
  /// desempaquetado y devuelve la primera variante reproducible.
  ///
  /// Prioridad identica a la extension de PelisPedia:
  /// `hls2` (CDN real) -> `hls3` -> `hls4`.
  String? _parseLinks(String text, String origin) {
    final block = RegExp(r'links\s*=\s*\{([\s\S]*?)\}').firstMatch(text);
    if (block == null) return null;

    final links = <String, String>{};
    // VidHide usa claves sin comillas (`hls2:"..."`); algunos mirrors las
    // entrecomillan. Se aceptan ambas formas.
    final pair = RegExp(
      r'''["']?([a-zA-Z0-9_]+)["']?\s*:\s*["']([^"']+)["']''',
    );
    for (final match in pair.allMatches(block.group(1)!)) {
      links[match.group(1)!] = match.group(2)!;
    }
    if (links.isEmpty) return null;

    for (final key in const ['hls2', 'hls3', 'hls4', 'hls', 'file']) {
      final raw = HtmlSourceScanner.fixUrl(links[key] ?? '');
      if (raw.isEmpty) continue;
      final absolute = HtmlSourceScanner.absolutize(origin, raw);
      if (!absolute.startsWith('http')) continue;
      if (HtmlSourceScanner.kindOf(absolute) == SourceKind.unknown) continue;
      return absolute;
    }
    return null;
  }

  String _idOf(Uri uri) {
    final match = RegExp(r'/(?:v|e|embed)/([A-Za-z0-9]+)', caseSensitive: false)
        .firstMatch(uri.path);
    if (match != null) return match.group(1)!;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    return segments.last
        .replaceFirst(RegExp(r'\.html?$', caseSensitive: false), '');
  }

  Map<String, String> _pageHeaders(String referer) => {
        'Referer': referer,
        'User-Agent': kExtractionUserAgent,
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
      };

  ExtractionOutcome _fail(
    ExtractionTimings timings,
    String failure, [
    String? host,
  ]) =>
      ExtractionOutcome(timings: timings, failure: failure, host: host);
}
