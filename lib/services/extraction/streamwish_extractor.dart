/// Extractor directo de StreamWish y sus mirrors.
///
/// StreamWish no publica la fuente en el HTML: la esconde en un bloque
/// JavaScript empaquetado (`links = {hls2: ..., hls3: ...}`). El extractor
/// desempaqueta ese bloque y elige la pista HLS disponible sin ejecutar codigo.
library jiruhub.streamwish_extractor;

import 'package:jiruhub/services/extraction/extraction_models.dart';
import 'package:jiruhub/services/extraction/html_source_scanner.dart';
import 'package:jiruhub/services/extraction/js_unpacker.dart';
import 'package:jiruhub/services/source_provider.dart' show SourceKind;

class StreamWishExtractor {
  StreamWishExtractor(this._fetch);

  final PageFetcher _fetch;

  /// Mirrors conocidos, en el mismo orden que usa la extension.
  static const List<String> _mirrors = [
    'playnixes.com',
    'hglamioz.com',
    'medixiru.com',
    'hglink.to',
    'streamhg.com',
    'streamwish.to',
  ];

  /// Referer que el CDN de StreamWish espera para hls2/hls3.
  static const String _streamWishReferer = 'https://streamwish.to/';

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
    final attempts = <_PageAttempt>[];
    for (final host in hosts) {
      attempts.add(_PageAttempt(host, '/e/'));
      attempts.add(_PageAttempt(host, '/v/'));
    }

    String? lastFailure;
    for (final attempt in attempts) {
      final origin = '$scheme://${attempt.host}';
      final pageUrl = '$origin${attempt.path}$id$search';
      final fetch =
          await _fetch(pageUrl, _pageHeaders('https://www.google.com/'));
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
          host: attempt.host,
        );
      }
      lastFailure = 'sin fuente en HTML';
    }

    timings.totalMs = DateTime.now().difference(startedAt).inMilliseconds;
    return _fail(
      timings,
      lastFailure ?? 'sin fuente',
      attempts.isNotEmpty ? attempts.first.host : null,
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
      final region = JsUnpacker.locatePackedScript(html, 'links');
      final unpackWatch = Stopwatch()..start();
      unpacked = JsUnpacker.unpack(region);
      timings.unpackMs += unpackWatch.elapsedMilliseconds;
    }

    if (unpacked != null && unpacked.isNotEmpty) {
      final fromLinks = _parseLinks(unpacked, origin);
      if (fromLinks != null) {
        timings.parseMs += parseWatch.elapsedMilliseconds;
        return fromLinks;
      }
    }

    final hasUnpacked = unpacked != null && unpacked.isNotEmpty;
    final primary = hasUnpacked ? unpacked : html;
    var url = HtmlSourceScanner.findHls(primary) ?? '';
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
      server: ExtractionServer.streamwish,
      headers: {
        'Referer': _streamWishReferer,
        'User-Agent': kExtractionUserAgent,
      },
      referer: _streamWishReferer,
    );
  }

  /// Extrae `links = { hls2: "...", hls3: "..." }` del JS desempaquetado.
  ExtractedSource? _parseLinks(String text, String origin) {
    final block = RegExp(r'links\s*=\s*\{([\s\S]*?)\}').firstMatch(text);
    if (block == null) return null;

    final links = <String, String>{};
    final pair = RegExp(
      r'''["']([a-zA-Z0-9_]+)["']\s*:\s*["']([^"']+)["']''',
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
      final kind = HtmlSourceScanner.kindOf(absolute);
      if (kind == SourceKind.unknown) continue;

      final referer = key == 'hls4' ? '$origin/' : _streamWishReferer;
      return ExtractedSource(
        url: absolute,
        kind: kind,
        server: ExtractionServer.streamwish,
        headers: {
          'Referer': referer,
          'User-Agent': kExtractionUserAgent,
        },
        referer: referer,
      );
    }
    return null;
  }

  String _idOf(Uri uri) {
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

class _PageAttempt {
  const _PageAttempt(this.host, this.path);
  final String host;
  final String path;
}
