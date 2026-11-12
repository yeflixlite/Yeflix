/// Resolucion directa de fuentes para Android.
///
/// Orquesta los extractores de VidHide y StreamWish, evita repetir solicitudes
/// (cache + deduplicacion en vuelo) y registra tiempos por etapa. En cualquier
/// plataforma distinta de Android devuelve `null` para no alterar el escritorio:
/// alli la extraccion sigue siendo la de las extensiones.
library jiruhub.direct_source_resolver;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:jiruhub/services/extraction/extraction_models.dart';
import 'package:jiruhub/services/extraction/html_source_scanner.dart';
import 'package:jiruhub/services/extraction/streamwish_extractor.dart';
import 'package:jiruhub/services/extraction/vidhide_extractor.dart';
import 'package:jiruhub/services/source_provider.dart' show SourceKind;
import 'package:jiruhub/utils/log.dart';
import 'package:jiruhub/utils/request.dart';

class DirectSourceResolver {
  DirectSourceResolver({
    this.ttl = const Duration(minutes: 5),
    this.failureTtl = const Duration(seconds: 20),
  });

  /// Vigencia de una fuente resuelta.
  final Duration ttl;

  /// Vigencia de un fallo para no martillar al servidor.
  final Duration failureTtl;

  static final RegExp _streamWish = RegExp(
    r'streamwish|hglink|streamhg|playnixes|hglamioz|medixiru|awish|hgcloud|'
    r'sfastwish|wishfast|streamhide|desiupload|embedwish|hlswish|vibuxer',
    caseSensitive: false,
  );
  static final RegExp _vidHide = RegExp(
    r'vidhide|earnvids|morencius|callistanise|minochinos|vsharea|vhide|'
    r'vid-hide|vidhideplus',
    caseSensitive: false,
  );

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<ExtractionOutcome>> _inFlight = {};

  /// Detecta el servidor usando solo el host de la URL.
  ///
  /// Evita falsos positivos cuando el nombre del servidor aparece en la ruta
  /// o en la query de una pagina que no es un embed.
  static ExtractionServer? detectServerHost(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    if (_streamWish.hasMatch(host)) return ExtractionServer.streamwish;
    if (_vidHide.hasMatch(host)) return ExtractionServer.vidhide;
    return null;
  }

  /// Detecta el servidor a partir de la URL del embed.
  ///
  /// Si la URL tiene host, la deteccion se limita a el; solo las URLs
  /// relativas (sin host) se evaluan completas.
  static ExtractionServer? detectServer(String url) {
    final value = url.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty) {
      return detectServerHost(value);
    }
    if (_streamWish.hasMatch(value)) return ExtractionServer.streamwish;
    if (_vidHide.hasMatch(value)) return ExtractionServer.vidhide;
    return null;
  }

  /// Devuelve el tipo si [url] ya es una fuente de video directa.
  static SourceKind? directMediaKind(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.m3u8') ||
        lower.contains('.m3u8?') ||
        lower.contains('master.txt') ||
        lower.contains('playlist.txt')) {
      return SourceKind.hls;
    }
    if (lower.endsWith('.mp4') || lower.contains('.mp4?')) {
      return SourceKind.mp4;
    }
    return null;
  }

  bool get isAndroid => Platform.isAndroid;

  /// Resuelve un embed y devuelve solo la fuente, si se obtuvo.
  Future<ExtractedSource?> resolveSource(
    String embedUrl, {
    String? referer,
  }) async {
    final outcome = await resolve(embedUrl, referer: referer);
    return outcome?.source;
  }

  /// Resuelve un embed. Devuelve `null` si no es un servidor soportado o si
  /// la plataforma no es Android.
  Future<ExtractionOutcome?> resolve(
    String embedUrl, {
    String? referer,
    bool force = false,
  }) async {
    if (!Platform.isAndroid) return null;
    final server = detectServer(embedUrl);
    if (server == null) return null;

    final key = _key(embedUrl);
    if (!force) {
      final cached = _cache[key];
      if (cached != null && !cached.isExpired) {
        logger.info(
            '⏱ [direct] cache hit ${server.label} (${cached.outcome.ok ? 'ok' : 'fallo'})');
        return cached.outcome;
      }
    }

    final running = _inFlight[key];
    if (running != null) {
      logger.info('⏱ [direct] solicitud en curso reutilizada ${server.label}');
      return running;
    }

    final future = _run(server, embedUrl, referer);
    _inFlight[key] = future;
    try {
      final outcome = await future;
      _cache[key] = _CacheEntry(
        outcome,
        DateTime.now(),
        outcome.ok ? ttl : failureTtl,
      );
      return outcome;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Invalida una entrada (por ejemplo, tras un fallo de reproduccion).
  void invalidate(String embedUrl) {
    _cache.remove(_key(embedUrl));
  }

  Future<ExtractionOutcome> _run(
    ExtractionServer server,
    String embedUrl,
    String? referer,
  ) async {
    try {
      final outcome = server == ExtractionServer.vidhide
          ? await VidHideExtractor(_fetch).extract(embedUrl, referer: referer)
          : await StreamWishExtractor(_fetch)
              .extract(embedUrl, referer: referer);
      _log(server, embedUrl, outcome);
      return outcome;
    } catch (e) {
      final timings = ExtractionTimings();
      final outcome = ExtractionOutcome(
        timings: timings,
        failure: e.runtimeType.toString(),
      );
      _log(server, embedUrl, outcome);
      return outcome;
    }
  }

  Future<PageFetch> _fetch(
    String url,
    Map<String, String> headers,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final requestHeaders = <String, String>{...headers};
      final cookie = await MiruRequest.getCookie(url);
      if (cookie.isNotEmpty) requestHeaders['Cookie'] = cookie;

      final response = await dio
          .get<String>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              headers: requestHeaders,
              followRedirects: true,
              maxRedirects: 5,
              validateStatus: (status) => status != null && status < 500,
              receiveTimeout: const Duration(seconds: 9),
              sendTimeout: const Duration(seconds: 6),
            ),
          )
          .timeout(const Duration(seconds: 11));

      watch.stop();
      final status = response.statusCode ?? 0;
      if (status >= 400) {
        return PageFetch(
          statusCode: status,
          ms: watch.elapsedMilliseconds,
          error: 'HTTP $status',
        );
      }
      return PageFetch(
        body: response.data,
        statusCode: status,
        ms: watch.elapsedMilliseconds,
      );
    } on TimeoutException {
      return PageFetch(ms: watch.elapsedMilliseconds, error: 'timeout');
    } on DioException catch (e) {
      return PageFetch(
        statusCode: e.response?.statusCode,
        ms: watch.elapsedMilliseconds,
        error: e.type.name,
      );
    } catch (e) {
      return PageFetch(
        ms: watch.elapsedMilliseconds,
        error: e.runtimeType.toString(),
      );
    }
  }

  String _key(String embedUrl) =>
      HtmlSourceScanner.fixUrl(embedUrl).split('#').first;

  /// Log sin cookies, tokens ni URLs completas: solo host y metricas.
  void _log(
    ExtractionServer server,
    String embedUrl,
    ExtractionOutcome outcome,
  ) {
    final embedHost = Uri.tryParse(embedUrl)?.host ?? '?';
    final source = outcome.source;
    final sourceHost =
        source == null ? '-' : (Uri.tryParse(source.url)?.host ?? '?');
    final result = source == null
        ? 'fallback(${outcome.failure ?? 'sin fuente'})'
        : '${source.kind.name}@$sourceHost';
    logger.info(
      '⏱ [direct] ${server.label} host=$embedHost '
      'req=${outcome.timings.requests} '
      'page=${outcome.timings.pageMs}ms '
      'parse=${outcome.timings.parseMs}ms '
      'unpack=${outcome.timings.unpackMs}ms '
      'extract=${outcome.timings.extractMs}ms '
      'total=${outcome.timings.totalMs}ms result=$result',
    );
  }
}

class _CacheEntry {
  _CacheEntry(this.outcome, this.createdAt, this.ttl);

  final ExtractionOutcome outcome;
  final DateTime createdAt;
  final Duration ttl;

  bool get isExpired => DateTime.now().difference(createdAt) >= ttl;
}
