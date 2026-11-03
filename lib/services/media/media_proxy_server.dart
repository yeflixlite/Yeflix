/// Proxy multimedia local para Windows.
///
/// Escucha solo en `127.0.0.1` y se inicia bajo demanda cuando el reproductor
/// va a abrir un HLS. Sus responsabilidades:
///
///  * Reescribir playlists HLS (maestro y media) para que mpv pida los
///    segmentos al proxy y no directamente al CDN.
///  * Mantener una cache en disco con limite estricto (300 MB por defecto),
///    con desalojo LRU de los elementos menos usados.
///  * Reenviar cabeceras (Referer, User-Agent, Cookie) en cada peticion.
///  * Soportar `Range` / `206 Partial Content` / `Content-Range`.
///  * Detectar VOD frente a live sin inventar duraciones: si el playlist no
///    trae `#EXT-X-ENDLIST` pero es claramente estatico (tipo VOD explicito o
///    ventana larga y cacheable) se declara su final; si es live se deja tal
///    cual para que mpv lo siga refrescando.
///  * Cancelar descargas y liberar el servidor cuando termina la reproduccion.
///
/// No se usa para fuentes que no son HLS (MP4 directo, DoodStream, etc.):
/// en esos casos `open()` devuelve `null` y el reproductor usa la URL original.
library jiruhub.media_proxy_server;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:jiruhub/utils/jiruhub_directory.dart';
import 'package:jiruhub/utils/log.dart';
import 'package:path/path.dart' as p;

class MediaProxyServer {
  MediaProxyServer._();

  static final MediaProxyServer instance = MediaProxyServer._();

  /// Limite de cache en disco. No es una reserva de RAM.
  static const int maxCacheBytes = 300 * 1024 * 1024;

  /// Un archivo mayor que esto no se guarda (evita llenar la cache con un MP4
  /// progresivo que ademas no necesita proxy).
  static const int maxCacheEntryBytes = 48 * 1024 * 1024;

  /// Descargas simultaneas maximas hacia el CDN.
  static const int maxConcurrentFetches = 4;

  static const Duration _playlistTimeout = Duration(seconds: 6);
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _receiveTimeout = Duration(seconds: 30);

  HttpServer? _server;
  final Map<String, _ProxySession> _sessions = {};
  final Map<String, _CacheEntry> _cache = {};
  final Set<String> _inUse = {};
  final Map<String, Completer<void>> _downloading = {};
  final List<Completer<void>> _fetchWaiters = <Completer<void>>[];
  int _activeFetches = 0;
  int _cacheBytes = 0;
  bool _pruning = false;
  bool _cacheScanned = false;
  Timer? _cleanupTimer;
  Directory? _cacheDir;
  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: _connectTimeout,
    receiveTimeout: _receiveTimeout,
    followRedirects: true,
    validateStatus: (status) => status != null && status < 500,
  ));

  int get port => _server?.port ?? 0;

  bool get isRunning => _server != null;

  /// Abre una sesion de reproduccion para [url].
  ///
  /// Devuelve la URL local que debe entregarse a mpv, o `null` cuando la
  /// fuente no es HLS o el proxy no puede manejarla (el llamador debe usar la
  /// URL original como fallback directo).
  Future<String?> open(
    String url,
    Map<String, String>? headers,
  ) async {
    if (!Platform.isWindows) return null;
    if (url.isEmpty || _isProxyUrl(url) || !url.startsWith('http')) return null;
    try {
      await _ensureStarted();
      final fetched = await _fetchText(url, _cleanHeaders(headers),
          timeout: _playlistTimeout);
      if (fetched == null) return null;
      final body = fetched.body;
      if (!body.contains('#EXTM3U')) return null;

      final token = _newToken();
      final session = _ProxySession(token, _cleanHeaders(headers), url);
      _sessions[token] = session;

      // Prefetch del playlist de entrada: se sirve desde memoria en la
      // primera peticion de mpv y evita un viaje extra al CDN.
      final rewritten = _rewritePlaylist(
        body,
        fetched.finalUri,
        session,
        responseHeaders: fetched.headers,
        sourceUrl: url,
      );
      session.seed[url] = _Seed(rewritten, DateTime.now());
      logger.info(
        'MediaProxy: sesion ${token.substring(0, 6)} abierta para ${_safeUrl(url)}',
      );
      return _entryUrl(token, url);
    } catch (e) {
      logger.warning('MediaProxy no disponible (fallback directo): $e');
      return null;
    }
  }

  /// Cierra la sesion y cancela todo lo que siga en vuelo. La cache en disco
  /// se conserva (se reutiliza en la siguiente reproduccion) y se libera el
  /// puerto si no quedan sesiones.
  Future<void> releaseSession(String? token) async {
    if (token == null) return;
    final session = _sessions.remove(token);
    if (session != null) {
      for (final cancel in session.cancels) {
        try {
          cancel.cancel('session released');
        } catch (_) {}
      }
      session.cancels.clear();
      session.seed.clear();
    }
    if (_sessions.isEmpty) {
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
      final server = _server;
      _server = null;
      if (server != null) {
        try {
          await server.close(force: true);
        } catch (_) {}
      }
    }
  }

  /// Cierra el proxy completo (se usa al salir de la app).
  Future<void> shutdown() async {
    for (final token in _sessions.keys.toList()) {
      await releaseSession(token);
    }
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  /// Estadisticas para pruebas y diagnostico (sin datos sensibles).
  Map<String, Object> stats() => {
        'running': isRunning,
        'port': port,
        'sessions': _sessions.length,
        'cacheBytes': _cacheBytes,
        'cacheEntries': _cache.length,
        'maxCacheBytes': maxCacheBytes,
        'activeFetches': _activeFetches,
      };

  // ------------------------------------------------------------------ setup

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    _server = server;
    server.listen(_handleRequest, onError: (e) {
      logger.warning('MediaProxy: error de servidor: $e');
    });
    await _ensureCacheDir();
    _cleanupTimer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupTempFiles();
    });
  }

  Future<Directory> _ensureCacheDir() async {
    final dir = _cacheDir ??
        Directory(p.join(JiruHubDirectory.getCacheDirectory, 'media_proxy'));
    _cacheDir = dir;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    if (!_cacheScanned) {
      _cacheScanned = true;
      await _scanCache();
    }
    return dir;
  }

  Future<void> _scanCache() async {
    try {
      final dir = await _ensureCacheDir();
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.contains('.part-')) {
          try {
            entity.deleteSync();
          } catch (_) {}
          continue;
        }
        try {
          final stat = entity.statSync();
          _cache[name] = _CacheEntry(stat.size, stat.modified);
          _cacheBytes += stat.size;
        } catch (_) {}
      }
      await _pruneCache();
    } catch (e) {
      logger.warning('MediaProxy: no se pudo leer la cache: $e');
    }
  }

  // --------------------------------------------------------------- requests

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final uri = request.uri;
      final segments = uri.pathSegments;
      if (segments.length < 3 || segments[0] != 's') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final session = _sessions[segments[1]];
      if (session == null) {
        response.statusCode = HttpStatus.gone;
        await response.close();
        return;
      }
      final target = _decodeTarget(uri.queryParameters['u']);
      if (target == null) {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return;
      }
      switch (segments[2]) {
        case 'entry':
          await _handlePlaylist(request, response, session, target);
          break;
        case 'p':
          await _handleAsset(request, response, session, target, cache: true);
          break;
        case 'k':
          await _handleAsset(request, response, session, target, cache: false);
          break;
        default:
          response.statusCode = HttpStatus.notFound;
          await response.close();
      }
    } catch (e) {
      // El cliente puede cerrar la conexion en mitad de un segmento: no es un
      // error fatal y no debe registrar URLs completas.
      logger.warning('MediaProxy: peticion abortada: $e');
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePlaylist(
    HttpRequest request,
    HttpResponse response,
    _ProxySession session,
    String target,
  ) async {
    final now = DateTime.now();
    final seeded = session.seed[target];
    String? body;
    Uri? finalUri;
    Map<String, String> headers = const {};
    if (seeded != null &&
        now.difference(seeded.at) < const Duration(seconds: 5)) {
      body = seeded.body;
      finalUri = Uri.parse(target);
      session.seed.remove(target);
    } else {
      final fetched = await _fetchText(
        target,
        session.headers,
        timeout: _playlistTimeout,
      );
      if (fetched == null) {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
        return;
      }
      body = fetched.body;
      finalUri = fetched.finalUri;
      headers = fetched.headers;
    }
    final rewritten = _rewritePlaylist(
      body,
      finalUri,
      session,
      responseHeaders: headers,
      sourceUrl: target,
    );
    response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl');
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Cache-Control', 'no-store');
    response.write(rewritten);
    await response.close();
  }

  Future<void> _handleAsset(
    HttpRequest request,
    HttpResponse response,
    _ProxySession session,
    String target, {
    required bool cache,
  }) async {
    final cacheKey = _cacheKey(target);
    final cacheFile = cache ? await _cacheFileFor(cacheKey) : null;

    if (cache && cacheFile != null && cacheFile.existsSync()) {
      _inUse.add(cacheKey);
      try {
        await _serveFile(request, response, cacheFile, cacheKey);
      } finally {
        _inUse.remove(cacheKey);
      }
      return;
    }

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final normalizedRange = rangeHeader?.replaceAll(' ', '');
    // `bytes=0-` equivale a pedir el objeto completo: se ignora para poder
    // cachearlo y se responde 200. Otros rangos si se reenvian (206).
    final wantsRange = normalizedRange != null &&
        normalizedRange.isNotEmpty &&
        normalizedRange != 'bytes=0-';
    final range = wantsRange ? rangeHeader : null;

    // Si otro cliente ya esta descargando el mismo objeto, esperamos a que la
    // cache este lista para no duplicar trafico.
    if (cache && !wantsRange && _downloading.containsKey(target)) {
      final pending = _downloading[target];
      if (pending != null) {
        try {
          await pending.future.timeout(const Duration(seconds: 20));
        } catch (_) {}
        if (cacheFile != null && cacheFile.existsSync()) {
          _inUse.add(cacheKey);
          try {
            await _serveFile(request, response, cacheFile, cacheKey);
          } finally {
            _inUse.remove(cacheKey);
          }
          return;
        }
      }
    }

    await _withFetchSlot(() async {
      final cancel = CancelToken();
      session.cancels.add(cancel);
      final requestHeaders = Map<String, String>.from(session.headers);
      if (range != null) requestHeaders[HttpHeaders.rangeHeader] = range;
      if (cache && !wantsRange) {
        _downloading[target] = Completer<void>();
      }
      File? temp;
      IOSink? sink;
      var cachedBytes = 0;
      var cacheable = cache && !wantsRange && cacheFile != null;
      try {
        final upstream = await _dio.get<ResponseBody>(
          target,
          options: Options(
            responseType: ResponseType.stream,
            headers: requestHeaders,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 500,
          ),
          cancelToken: cancel,
        );
        final status = upstream.statusCode ?? HttpStatus.ok;
        response.statusCode = status;
        _copyHeader(upstream, response, HttpHeaders.contentTypeHeader);
        _copyHeader(upstream, response, HttpHeaders.contentRangeHeader);
        _copyHeader(upstream, response, HttpHeaders.acceptRangesHeader);
        _copyHeader(upstream, response, HttpHeaders.etagHeader);
        _copyHeader(upstream, response, HttpHeaders.lastModifiedHeader);
        _copyHeader(upstream, response, HttpHeaders.cacheControlHeader);
        final contentType = response.headers.contentType;
        if (contentType != null && contentType.mimeType.contains('mpegurl')) {
          // Un playlist no debe pasar por la ruta de cache de segmentos.
          cacheable = false;
        }
        if (status != HttpStatus.ok) cacheable = false;

        final stream = upstream.data?.stream;
        if (stream == null) {
          await response.close();
          return;
        }

        final lengthValues =
            upstream.headers[HttpHeaders.contentLengthHeader];
        final length = int.tryParse(
          lengthValues != null && lengthValues.isNotEmpty
              ? lengthValues.first
              : '',
        );
        if (length != null && length > maxCacheEntryBytes) cacheable = false;

        if (cacheable) {
          temp = File(
            '${cacheFile!.path}.part-${DateTime.now().microsecondsSinceEpoch}',
          );
          sink = temp.openWrite();
        }

        var writeFailed = false;
        await for (final chunk in stream) {
          if (!writeFailed) {
            try {
              sink?.add(chunk);
              cachedBytes += chunk.length;
              if (cachedBytes > maxCacheEntryBytes) {
                writeFailed = true;
                try {
                  await sink?.close();
                } catch (_) {}
                sink = null;
                try {
                  temp?.deleteSync();
                } catch (_) {}
                temp = null;
              }
            } catch (_) {
              writeFailed = true;
              sink = null;
            }
          }
          response.add(chunk);
        }

        final targetFile = cacheFile;
        if (cacheable && temp != null && sink != null && targetFile != null) {
          try {
            await sink.flush();
            await sink.close();
            sink = null;
            if (targetFile.existsSync()) {
              try {
                targetFile.deleteSync();
              } catch (_) {}
            }
            await temp.rename(targetFile.path);
            temp = null;
            _registerCache(cacheKey, cachedBytes);
          } catch (e) {
            try {
              await sink?.close();
            } catch (_) {}
            sink = null;
            try {
              temp?.deleteSync();
            } catch (_) {}
            temp = null;
            logger.warning('MediaProxy: no se pudo guardar en cache: $e');
          }
        }
        await response.close();
      } catch (e) {
        try {
          await sink?.close();
        } catch (_) {}
        try {
          temp?.deleteSync();
        } catch (_) {}
        try {
          response.statusCode = HttpStatus.badGateway;
        } catch (_) {}
        try {
          await response.close();
        } catch (_) {}
        rethrow;      } finally {
        session.cancels.remove(cancel);
        final pending = _downloading.remove(target);
        pending?.complete();
      }
    });
  }

  Future<void> _serveFile(
    HttpRequest request,
    HttpResponse response,
    File file,
    String cacheKey,
  ) async {
    final total = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final range = _parseRange(rangeHeader, total);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType('application', 'octet-stream');
    if (range == null) {
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = total;
      await response.addStream(file.openRead());
      await response.close();
    } else {
      final start = range.$1;
      final end = range.$2;
      response.statusCode = HttpStatus.partialContent;
      response.headers.contentLength = end - start + 1;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
      await response.addStream(file.openRead(start, end + 1));
      await response.close();
    }
    final entry = _cache[cacheKey];
    if (entry != null) entry.accessed = DateTime.now();
    try {
      file.setLastModifiedSync(DateTime.now());
    } catch (_) {}
  }

  // --------------------------------------------------------------- playlists

  String _rewritePlaylist(
    String body,
    Uri baseUri,
    _ProxySession session, {
    required Map<String, String> responseHeaders,
    required String sourceUrl,
  }) {
    final isMaster = body.contains('#EXT-X-STREAM-INF') ||
        body.contains('#EXT-X-MEDIA:') ||
        body.contains('#EXT-X-I-FRAME-STREAM-INF');
    final out = <String>[];
    final lines = body.split('\n');
    var expectVariantUri = false;
    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        out.add(raw);
        continue;
      }
      if (trimmed.startsWith('#')) {
        final route = _tagRoute(trimmed);
        if (route != null) {
          out.add(line.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (m) =>
                'URI="${_proxyUri(baseUri, m.group(1)!, session, route)}"',
          ));
        } else {
          out.add(raw);
        }
        if (trimmed.startsWith('#EXT-X-STREAM-INF')) {
          expectVariantUri = true;
        }
        continue;
      }
      out.add(_proxyUri(
        baseUri,
        trimmed,
        session,
        expectVariantUri ? 'entry' : 'p',
      ));
      expectVariantUri = false;
    }

    if (!isMaster) {
      final hasEnd = body.contains('#EXT-X-ENDLIST');
      if (!hasEnd && _isVodPlaylist(body, responseHeaders, session, sourceUrl)) {
        out.add('#EXT-X-ENDLIST');
        logger.info(
          'MediaProxy: VOD sin ENDLIST detectado en ${_safeUrl(sourceUrl)}',
        );
      }
    }
    return out.join('\n');
  }

  /// Decide si un playlist sin `#EXT-X-ENDLIST` es en realidad VOD.
  ///
  /// Solo se declara VOD cuando hay una senal fuerte:
  ///  * `#EXT-X-PLAYLIST-TYPE:VOD` explicito, o
  ///  * ventana larga (>= 30 segmentos) y respuesta cacheable.
  ///
  /// Un live real (ventana corta y/o `no-cache`) nunca recibe ENDLIST.
  bool _isVodPlaylist(
    String body,
    Map<String, String> headers,
    _ProxySession session,
    String sourceUrl,
  ) {
    if (session.vodUrls.contains(sourceUrl)) return true;
    if (session.liveUrls.contains(sourceUrl)) return false;
    if (body.contains('#EXT-X-PLAYLIST-TYPE:VOD')) {
      session.vodUrls.add(sourceUrl);
      return true;
    }
    if (body.contains('#EXT-X-PLAYLIST-TYPE:EVENT')) {
      session.liveUrls.add(sourceUrl);
      return false;
    }
    final segments = RegExp(r'#EXTINF:').allMatches(body).length;
    final cacheControl =
        (headers['cache-control'] ?? headers['Cache-Control'] ?? '')
            .toLowerCase();
    final expires = headers['expires'] ?? headers['Expires'];
    final noStore = cacheControl.contains('no-store') ||
        cacheControl.contains('no-cache') ||
        cacheControl.contains('private');
    var cacheable = false;
    if (!noStore) {
      final maxAge =
          RegExp(r'max-age=(\d+)').firstMatch(cacheControl)?.group(1);
      final maxAgeSeconds = maxAge == null ? null : int.tryParse(maxAge);
      if (maxAgeSeconds != null && maxAgeSeconds >= 60) cacheable = true;
      if (expires != null) {
        try {
          if (HttpDate.parse(expires).isAfter(DateTime.now())) {
            cacheable = true;
          }
        } catch (_) {}
      }
    }
    if (segments >= 30 && cacheable) {
      session.vodUrls.add(sourceUrl);
      return true;
    }
    if (segments > 0) session.liveUrls.add(sourceUrl);
    return false;
  }

  static String? _tagRoute(String tag) {
    if (tag.startsWith('#EXT-X-KEY') ||
        tag.startsWith('#EXT-X-SESSION-KEY')) {
      return 'k';
    }
    if (tag.startsWith('#EXT-X-MEDIA:') ||
        tag.startsWith('#EXT-X-I-FRAME-STREAM-INF') ||
        tag.startsWith('#EXT-X-RENDITION-REPORT')) {
      return 'entry';
    }
    if (tag.startsWith('#EXT-X-MAP') ||
        tag.startsWith('#EXT-X-PART') ||
        tag.startsWith('#EXT-X-PRELOAD-HINT')) {
      return 'p';
    }
    return null;
  }

  String _proxyUri(
    Uri baseUri,
    String raw,
    _ProxySession session,
    String route,
  ) {
    Uri resolved;
    try {
      resolved = baseUri.resolve(raw);
    } catch (_) {
      return raw;
    }
    if (_isProxyUrl(resolved.toString())) return resolved.toString();
    return _assetUrl(session.token, resolved.toString(), route);
  }

  // ----------------------------------------------------------------- helpers

  Future<_FetchedText?> _fetchText(
    String url,
    Map<String, String> headers, {
    required Duration timeout,
  }) async {
    final cancel = CancelToken();
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          followRedirects: true,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          validateStatus: (status) => status != null && status < 400,
        ),
        cancelToken: cancel,
      );
      final body = response.data;
      if (body == null || body.isEmpty) return null;
      final map = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) map[name.toLowerCase()] = values.join(',');
      });
      return _FetchedText(
        body.replaceFirst('\uFEFF', ''),
        Uri.parse(response.realUri.toString()),
        map,
      );
    } catch (_) {
      return null;
    } finally {
      try {
        cancel.cancel();
      } catch (_) {}
    }
  }

  Future<T> _withFetchSlot<T>(Future<T> Function() action) async {
    while (_activeFetches >= maxConcurrentFetches) {
      final waiter = Completer<void>();
      _fetchWaiters.add(waiter);
      await waiter.future;
    }
    _activeFetches++;
    try {
      return await action();
    } finally {
      _activeFetches--;
      if (_fetchWaiters.isNotEmpty) {
        _fetchWaiters.removeAt(0).complete();
      }
    }
  }

  Future<File> _cacheFileFor(String key) async {
    final dir = await _ensureCacheDir();
    return File(p.join(dir.path, key));
  }

  String _cacheKey(String url) =>
      sha256.convert(utf8.encode(url)).toString();

  void _registerCache(String key, int bytes) {
    final previous = _cache[key];
    if (previous != null) {
      _cacheBytes -= previous.size;
    }
    _cache[key] = _CacheEntry(bytes, DateTime.now());
    _cacheBytes += bytes;
    unawaited(_pruneCache());
  }

  Future<void> _pruneCache() async {
    if (_pruning) return;
    _pruning = true;
    try {
      if (_cacheBytes <= maxCacheBytes) return;
      final entries = _cache.entries.toList()
        ..sort((a, b) => a.value.accessed.compareTo(b.value.accessed));
      final dir = _cacheDir;
      if (dir == null) return;
      for (final entry in entries) {
        if (_cacheBytes <= maxCacheBytes) break;
        if (_inUse.contains(entry.key)) continue;
        final file = File(p.join(dir.path, entry.key));
        try {
          if (file.existsSync()) file.deleteSync();
          _cache.remove(entry.key);
          _cacheBytes -= entry.value.size;
        } catch (_) {
          // En Windows un archivo abierto no se puede borrar; se reintenta en
          // la siguiente pasada.
        }
      }
      if (_cacheBytes < 0) _cacheBytes = 0;
    } finally {
      _pruning = false;
    }
  }

  void _cleanupTempFiles() {
    final dir = _cacheDir;
    if (dir == null) return;
    try {
      final limit = DateTime.now().subtract(const Duration(hours: 1));
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (!p.basename(entity.path).contains('.part-')) continue;
        try {
          if (entity.statSync().modified.isBefore(limit)) entity.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Map<String, String> _cleanHeaders(Map<String, String>? headers) {
    if (headers == null) return const {};
    final clean = <String, String>{};
    headers.forEach((key, value) {
      if (key.startsWith('X-Netu-')) return;
      if (key.toLowerCase() == 'host') return;
      clean[key] = value;
    });
    return clean;
  }

  bool _isProxyUrl(String url) =>
      url.startsWith('http://127.0.0.1') || url.startsWith('http://localhost');

  String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _entryUrl(String token, String target) =>
      'http://127.0.0.1:$port/s/$token/entry?u=${_encodeTarget(target)}';

  String _assetUrl(String token, String target, String route) =>
      'http://127.0.0.1:$port/s/$token/$route?u=${_encodeTarget(target)}';

  String _encodeTarget(String url) =>
      base64Url.encode(utf8.encode(url)).replaceAll('=', '');

  String? _decodeTarget(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final padded = value.padRight((value.length + 3) & ~3, '=');
      return utf8.decode(base64Url.decode(padded));
    } catch (_) {
      return null;
    }
  }

  void _copyHeader(
      Response<ResponseBody> source, HttpResponse target, String name) {
    final values = source.headers[name];
    if (values != null && values.isNotEmpty) {
      target.headers.set(name, values.join(', '));
    }
  }

  (int, int)? _parseRange(String? header, int total) {
    if (header == null || !header.startsWith('bytes=')) return null;
    final spec = header.substring('bytes='.length).split(',').first.trim();
    final parts = spec.split('-');
    if (parts.length != 2) return null;
    final startText = parts[0].trim();
    final endText = parts[1].trim();
    int start;
    int end;
    if (startText.isEmpty) {
      final suffix = int.tryParse(endText);
      if (suffix == null || suffix <= 0) return null;
      start = max(0, total - suffix);
      end = total - 1;
    } else {
      start = int.tryParse(startText) ?? -1;
      end = endText.isEmpty ? total - 1 : (int.tryParse(endText) ?? -1);
    }
    if (start < 0 || end < start || start >= total) return null;
    return (start, min(end, total - 1));
  }

  String _safeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}${uri.path}';
    } catch (_) {
      return 'url-invalida';
    }
  }
}

class _ProxySession {
  _ProxySession(this.token, this.headers, this.origin);
  final String token;
  final Map<String, String> headers;
  final String origin;
  final Set<CancelToken> cancels = {};
  final Set<String> vodUrls = {};
  final Set<String> liveUrls = {};
  final Map<String, _Seed> seed = {};
}

class _Seed {
  _Seed(this.body, this.at);
  final String body;
  final DateTime at;
}

class _CacheEntry {
  _CacheEntry(this.size, this.accessed);
  final int size;
  DateTime accessed;
}

class _FetchedText {
  _FetchedText(this.body, this.finalUri, this.headers);
  final String body;
  final Uri finalUri;
  final Map<String, String> headers;
}
