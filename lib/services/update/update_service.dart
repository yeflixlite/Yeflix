/// Servicio de actualizaciones: GitHub, caché y descargas reanudables.
library jiruhub.update_service;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:jiruhub/services/update/update_asset_selector.dart';
import 'package:jiruhub/services/update/update_models.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';
import 'package:path/path.dart' as p;

/// Se lanza cuando el usuario cancela una descarga.
class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  static const String repository = 'yeflixlite/Yeflix';
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$repository/releases/latest';

  /// La comprobación automática reutiliza el release durante 6 h.
  static const Duration autoCacheTtl = Duration(hours: 6);

  /// Una comprobación manual reciente no vuelve a llamar a GitHub.
  static const Duration manualCacheTtl = Duration(minutes: 2);

  /// `version.json` cambia muy poco; se cachea aparte.
  static const Duration versionJsonTtl = Duration(hours: 6);

  static const Duration _requestTimeout = Duration(seconds: 20);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: _requestTimeout,
      receiveTimeout: _requestTimeout,
      sendTimeout: _requestTimeout,
      followRedirects: true,
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Yeflix-Updater',
      },
    ),
  );

  Future<UpdateCheckResult>? _inFlight;

  /// Evita dos comprobaciones simultáneas (arranque + botón manual).
  Future<UpdateCheckResult> check({
    required UpdateEnvironment environment,
    bool manual = false,
    bool force = false,
  }) {
    final running = _inFlight;
    if (running != null) return running;

    final future = _checkInternal(
      environment: environment,
      manual: manual,
      force: force,
    );
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<UpdateCheckResult> _checkInternal({
    required UpdateEnvironment environment,
    required bool manual,
    required bool force,
  }) async {
    final now = DateTime.now();
    final cachedJson = _readCachedPayload();
    final cachedAt = _readCacheTime();
    final ttl = manual ? manualCacheTtl : autoCacheTtl;

    if (!force &&
        cachedJson != null &&
        cachedAt != null &&
        now.difference(cachedAt) < ttl) {
      final release =
          await _releaseFromJson(cachedJson, environment: environment);
      if (release != null) {
        return _evaluate(release, environment, fromCache: true);
      }
    }

    try {
      final etag = _readEtag();
      final latest = await _withRetry(
        () => _fetchLatest(etag: cachedJson == null ? null : etag),
      );
      final json = latest.json;

      if (json == null) {
        // 304 Not Modified: el release no cambió.
        if (cachedJson == null) {
          return UpdateCheckResult.failure(
            environment: environment,
            error: 'GitHub no devolvió información del release.',
          );
        }
        await _writeCacheTime(DateTime.now());
        final release = await _releaseFromJson(
          cachedJson,
          environment: environment,
        );
        if (release == null) {
          return UpdateCheckResult.failure(
            environment: environment,
            error: 'La respuesta guardada del release no es válida.',
          );
        }
        return _evaluate(release, environment, fromCache: true);
      }

      await _writeCache(json, etag: latest.etag);
      final release = await _releaseFromJson(json, environment: environment);
      if (release == null) {
        return UpdateCheckResult.failure(
          environment: environment,
          error: 'El release publicado no tiene una versión válida.',
        );
      }
      return _evaluate(release, environment);
    } catch (e) {
      debugPrint('[UpdateService] error: $e');
      // GitHub puede limitar o no estar disponible. Si ya hay un release
      // guardado, se evalúa contra el build local: no genera falsos avisos y
      // permite actualizar aunque la comprobación falle.
      if (cachedJson != null &&
          cachedAt != null &&
          now.difference(cachedAt) < const Duration(days: 7)) {
        final release =
            await _releaseFromJson(cachedJson, environment: environment);
        if (release != null) {
          return _evaluate(release, environment, fromCache: true);
        }
      }
      return UpdateCheckResult.failure(
        environment: environment,
        error: _describeError(e),
      );
    }
  }

  UpdateCheckResult _evaluate(
    RemoteRelease release,
    UpdateEnvironment environment, {
    bool fromCache = false,
  }) {
    final evaluated = UpdateAssetSelector.evaluate(
      release: release,
      environment: environment,
    );
    return UpdateCheckResult(
      hasUpdate: evaluated.hasUpdate,
      localVersion: evaluated.localVersion,
      platform: evaluated.platform,
      release: evaluated.release,
      asset: evaluated.asset,
      localBuild: evaluated.localBuild,
      remoteBuild: evaluated.remoteBuild,
      localVersionCode: evaluated.localVersionCode,
      fromCache: fromCache,
    );
  }

  Future<RemoteRelease?> _releaseFromJson(
    Map<String, dynamic> json, {
    required UpdateEnvironment environment,
  }) async {
    final base = RemoteRelease.fromJson(json);
    if (base == null) return null;
    final build = await _resolveRemoteBuild(base);
    return build != null ? base.copyWith(build: build) : base;
  }

  /// Lee el build de `version.json` y lo cachea.
  Future<int?> _resolveRemoteBuild(RemoteRelease release) async {
    UpdateAsset? versionJson;
    for (final asset in release.assets) {
      if (asset.kind == UpdateAssetKind.versionJson) {
        versionJson = asset;
        break;
      }
    }
    if (versionJson == null) return null;

    final cachedUrl =
        JiruHubStorage.getSetting(SettingKey.updateVersionJsonUrl);
    final cachedBuild =
        JiruHubStorage.getSetting(SettingKey.updateVersionJsonBuild);
    final cachedAtRaw =
        JiruHubStorage.getSetting(SettingKey.updateVersionJsonTimestamp);
    if (cachedUrl == versionJson.url &&
        cachedBuild is int &&
        cachedBuild > 0 &&
        cachedAtRaw is int) {
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtRaw);
      if (DateTime.now().difference(cachedAt) < versionJsonTtl) {
        return cachedBuild;
      }
    }

    try {
      final response = await _withRetry(
        () => _dio.get<String>(
          versionJson!.url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {'Accept': 'application/json'},
          ),
        ),
      );
      final raw = response.data;
      final decoded = raw is String ? jsonDecode(raw) : raw;
      final buildRaw = decoded is Map ? decoded['build'] : null;
      final build =
          buildRaw is int ? buildRaw : int.tryParse('${buildRaw ?? ''}');
      if (build != null && build > 0) {
        await JiruHubStorage.setSetting(
          SettingKey.updateVersionJsonUrl,
          versionJson.url,
        );
        await JiruHubStorage.setSetting(
          SettingKey.updateVersionJsonBuild,
          build,
        );
        await JiruHubStorage.setSetting(
          SettingKey.updateVersionJsonTimestamp,
          DateTime.now().millisecondsSinceEpoch,
        );
        return build;
      }
    } catch (e) {
      debugPrint('[UpdateService] version.json no disponible: $e');
    }
    return null;
  }

  /// Devuelve `json == null` en un 304 Not Modified.
  Future<_LatestResponse> _fetchLatest({String? etag}) async {
    final headers = <String, String>{};
    if (etag != null && etag.isNotEmpty) {
      headers['If-None-Match'] = etag;
    }

    final response = await _dio.get<dynamic>(
      latestReleaseUrl,
      options: Options(
        headers: headers,
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && (status < 400 || status == 304),
      ),
    );

    if (response.statusCode == 304) {
      return _LatestResponse(null, response.headers.value('etag') ?? etag);
    }

    final data = response.data;
    Map<String, dynamic>? json;
    if (data is Map) {
      json = Map<String, dynamic>.from(data);
    } else if (data is String && data.trim().isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    }
    if (json == null) {
      throw const FormatException('Respuesta inesperada de GitHub.');
    }
    return _LatestResponse(json, response.headers.value('etag'));
  }

  Future<T> _withRetry<T>(
    Future<T> Function() action, {
    int attempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await action();
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        lastError = e;
        final status = e.response?.statusCode;
        // 403 (rate limit) y 404 no se arreglan reintentando.
        if (status == 403 || status == 404 || attempt == attempts) rethrow;
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      } catch (e) {
        lastError = e;
        if (attempt == attempts) rethrow;
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
    throw lastError ?? Exception('Error de red desconocido.');
  }

  /// Descarga [asset] en [directory] con reanudación, reintentos y SHA-256.
  Future<File> download({
    required UpdateAsset asset,
    required Directory directory,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
    int attempts = 3,
  }) async {
    await directory.create(recursive: true);
    final safeName = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final finalFile = File(p.join(directory.path, safeName));
    final partFile = File('${finalFile.path}.part');

    if (await finalFile.exists()) {
      final length = await finalFile.length();
      final sizeOk = asset.size <= 0 || length == asset.size;
      if (sizeOk && await _digestMatches(finalFile, asset)) {
        onProgress(length, asset.size > 0 ? asset.size : length);
        return finalFile;
      }
      try {
        await finalFile.delete();
      } catch (_) {}
    }

    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _downloadOnce(
          asset: asset,
          partFile: partFile,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );

        final length = await partFile.length();
        if (asset.size > 0 && length != asset.size) {
          throw Exception(
            'Descarga incompleta ($length de ${asset.size} bytes).',
          );
        }
        if (!await _digestMatches(partFile, asset)) {
          try {
            await partFile.delete();
          } catch (_) {}
          throw Exception('El archivo descargado está dañado (SHA-256).');
        }

        if (await finalFile.exists()) await finalFile.delete();
        await partFile.rename(finalFile.path);
        onProgress(length, length);
        return finalFile;
      } on UpdateCancelled {
        rethrow;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) throw const UpdateCancelled();
        lastError = e;
        if (attempt == attempts) rethrow;
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      } catch (e) {
        lastError = e;
        if (attempt == attempts) rethrow;
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
    throw lastError ?? Exception('No se pudo descargar la actualización.');
  }

  Future<void> _downloadOnce({
    required UpdateAsset asset,
    required File partFile,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    var offset = await partFile.exists() ? await partFile.length() : 0;
    if (asset.size > 0 && offset > asset.size) {
      await partFile.delete();
      offset = 0;
    }
    if (asset.size > 0 && offset == asset.size) {
      onProgress(offset, asset.size);
      return;
    }

    final headers = <String, String>{};
    if (offset > 0) headers['Range'] = 'bytes=$offset-';

    final response = await _dio.get<ResponseBody>(
      asset.url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        followRedirects: true,
        validateStatus: (status) => status == 200 || status == 206,
      ),
      cancelToken: cancelToken,
    );

    final body = response.data;
    if (body == null) throw Exception('Respuesta vacía al descargar.');

    final append = response.statusCode == 206 && offset > 0;
    final start = append ? offset : 0;
    final contentLengthHeader =
        response.headers.value(Headers.contentLengthHeader);
    final contentLength =
        contentLengthHeader == null ? null : int.tryParse(contentLengthHeader);
    final total = asset.size > 0
        ? asset.size
        : (contentLength != null && contentLength > 0
            ? start + contentLength
            : 0);

    final raf = await partFile.open(
      mode: append ? FileMode.append : FileMode.write,
    );
    var received = start;
    try {
      await for (final chunk in body.stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw const UpdateCancelled();
        }
        await raf.writeFrom(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
    } finally {
      await raf.close();
    }
  }

  Future<bool> _digestMatches(File file, UpdateAsset asset) async {
    final expected = asset.sha256;
    if (expected == null) return true;
    final actual = await sha256.bind(file.openRead()).first;
    return actual.toString().toLowerCase() == expected;
  }

  String _describeError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Tiempo de espera agotado al conectar con GitHub.';
        case DioExceptionType.connectionError:
          return 'Sin conexión con GitHub. Comprueba tu red o el proxy.';
        case DioExceptionType.badResponse:
          final status = error.response?.statusCode;
          if (status == 403) {
            return 'GitHub limitó temporalmente las comprobaciones. '
                'Inténtalo de nuevo más tarde.';
          }
          if (status == 404) {
            return 'No se encontró el release de Yeflix en GitHub.';
          }
          return 'GitHub respondió con un error HTTP $status.';
        default:
          return 'No se pudo comprobar la actualización (${error.message ?? 'red'}).';
      }
    }
    return 'No se pudo comprobar la actualización: $error';
  }

  Map<String, dynamic>? _readCachedPayload() {
    final raw = JiruHubStorage.getSetting(SettingKey.updateCachePayload);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      debugPrint('[UpdateService] caché inválida: $e');
    }
    return null;
  }

  String? _readEtag() {
    final value = JiruHubStorage.getSetting(SettingKey.updateCacheEtag);
    return value is String && value.isNotEmpty ? value : null;
  }

  DateTime? _readCacheTime() {
    final value = JiruHubStorage.getSetting(SettingKey.updateCacheTimestamp);
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  Future<void> _writeCache(Map<String, dynamic> json, {String? etag}) async {
    await JiruHubStorage.setSetting(
      SettingKey.updateCachePayload,
      jsonEncode(json),
    );
    await JiruHubStorage.setSetting(
      SettingKey.updateCacheTimestamp,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (etag != null && etag.isNotEmpty) {
      await JiruHubStorage.setSetting(SettingKey.updateCacheEtag, etag);
    }
  }

  Future<void> _writeCacheTime(DateTime time) async {
    await JiruHubStorage.setSetting(
      SettingKey.updateCacheTimestamp,
      time.millisecondsSinceEpoch,
    );
  }
}

class _LatestResponse {
  const _LatestResponse(this.json, this.etag);

  final Map<String, dynamic>? json;
  final String? etag;
}
