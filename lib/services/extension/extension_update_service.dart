/// Actualizador automatico de extensiones de Yeflix.
///
/// Es independiente del actualizador de la aplicacion: consulta el indice
/// `index.json` del repositorio de extensiones, compara versiones/hashes y
/// descarga solo las extensiones que cambiaron. No requiere publicar un APK
/// ni una nueva version de Yeflix por cada cambio de extension.
///
/// Garantias:
///  * Comprobacion periodica (cada 3 h) y al iniciar, sin bloquear la UI.
///  * `ETag` / `If-None-Match` para evitar descargas cuando el indice no
///    cambio, y una espera minima entre comprobaciones manuales.
///  * Descarga por archivo, validacion de tamano y SHA-256 cuando el indice
///    los publica, y validacion de que el archivo es una extension Yeflix.
///  * Escritura atomica con respaldo: si algo falla se restaura la version
///    anterior y se puede reintentar en la siguiente comprobacion.
///  * Reintentos con espera progresiva y respeto de `Retry-After` cuando
///    GitHub limita las solicitudes.
library jiruhub.extension_update_service;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:jiruhub/utils/extension.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';
import 'package:jiruhub/utils/log.dart';
import 'package:jiruhub/utils/request.dart';
import 'package:path/path.dart' as p;

enum ExtensionUpdatePhase {
  idle,
  checking,
  upToDate,
  updating,
  updated,
  error,
  rateLimited,
}

class ExtensionUpdateStatus {
  const ExtensionUpdateStatus({
    this.phase = ExtensionUpdatePhase.idle,
    this.message = '',
    this.updated = 0,
    this.lastCheck,
    this.pending = 0,
  });

  final ExtensionUpdatePhase phase;
  final String message;
  final int updated;
  final DateTime? lastCheck;

  /// Extensiones nuevas del repositorio que no estan instaladas. No se
  /// instalan solas para no alterar la seleccion del usuario.
  final int pending;

  bool get isBusy =>
      phase == ExtensionUpdatePhase.checking ||
      phase == ExtensionUpdatePhase.updating;

  ExtensionUpdateStatus copyWith({
    ExtensionUpdatePhase? phase,
    String? message,
    int? updated,
    DateTime? lastCheck,
    int? pending,
  }) =>
      ExtensionUpdateStatus(
        phase: phase ?? this.phase,
        message: message ?? this.message,
        updated: updated ?? this.updated,
        lastCheck: lastCheck ?? this.lastCheck,
        pending: pending ?? this.pending,
      );
}

class ExtensionUpdateService {
  ExtensionUpdateService._();

  static final ExtensionUpdateService instance = ExtensionUpdateService._();

  /// Comprobacion automatica cada 3 horas mientras la app esta abierta.
  static const Duration interval = Duration(hours: 3);

  /// Evita martillear GitHub si el usuario pulsa "comprobar" repetidamente.
  static const Duration manualCooldown = Duration(seconds: 45);

  static const Duration _indexTimeout = Duration(seconds: 15);
  static const Duration _fileTimeout = Duration(seconds: 30);
  static const int _maxAttempts = 3;

  final Rx<ExtensionUpdateStatus> status =
      const ExtensionUpdateStatus().obs;

  Timer? _timer;
  bool _checking = false;
  DateTime? _lastAttempt;
  DateTime? _blockedUntil;

  /// Error real de red/servidor en la ultima consulta. Se distingue de "sin
  /// cambios" para no decir "extensiones al dia" cuando no hubo conexion.
  String? _lastIndexError;

  void start({bool immediate = true}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
    if (immediate) {
      // Deja terminar el arranque y la primera pantalla antes de usar red.
      Future<void>.delayed(const Duration(seconds: 4), () {
        unawaited(check());
      });
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> check({bool manual = false, bool force = false}) async {
    if (_checking) return;
    final now = DateTime.now();
    if (!force && _lastAttempt != null) {
      final elapsed = now.difference(_lastAttempt!);
      final cooldown = manual ? manualCooldown : const Duration(minutes: 5);
      if (elapsed < cooldown) return;
    }
    if (_blockedUntil != null && now.isBefore(_blockedUntil!)) {
      final wait = _blockedUntil!.difference(now).inMinutes + 1;
      status.value = status.value.copyWith(
        phase: ExtensionUpdatePhase.rateLimited,
        message: 'GitHub limito las solicitudes. Reintento en ~$wait min.',
      );
      return;
    }

    final base = '${JiruHubStorage.getSetting(SettingKey.jiruhubRepoUrl)}'
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return;

    _checking = true;
    _lastAttempt = now;
    status.value = status.value.copyWith(
      phase: ExtensionUpdatePhase.checking,
      message: manual ? 'Comprobando extensiones...' : 'Buscando actualizaciones...',
    );
    try {
      final index = await _fetchIndex(base, force: force);
      if (index == null) {
        if (_lastIndexError == 'rate-limited') {
          // El estado de limite ya lo publico _fetchIndex.
          return;
        }
        if (_lastIndexError != null) {
          status.value = status.value.copyWith(
            phase: ExtensionUpdatePhase.error,
            message: 'No se pudieron comprobar las extensiones',
            lastCheck: DateTime.now(),
          );
          return;
        }
        // 304 Not Modified o indice vacio: no hay nada que hacer.
        status.value = status.value.copyWith(
          phase: ExtensionUpdatePhase.upToDate,
          message: 'Extensiones al dia',
          lastCheck: DateTime.now(),
        );
        return;
      }
      final entries = _parseIndex(index.body);
      if (entries.isEmpty) {
        status.value = status.value.copyWith(
          phase: ExtensionUpdatePhase.upToDate,
          message: 'Extensiones al dia',
          lastCheck: DateTime.now(),
        );
        return;
      }
      final installed = _installedPackages();
      final updates = <_ManifestEntry>[];
      var pendingNew = 0;
      for (final entry in entries) {
        final local = installed[entry.package];
        if (local == null) {
          pendingNew++;
          continue;
        }
        if (_needsUpdate(entry, local)) updates.add(entry);
      }

      if (updates.isEmpty) {
        status.value = status.value.copyWith(
          phase: ExtensionUpdatePhase.upToDate,
          message: pendingNew > 0
              ? 'Extensiones al dia ($pendingNew nuevas en el repositorio)'
              : 'Extensiones al dia',
          lastCheck: DateTime.now(),
          pending: pendingNew,
          updated: 0,
        );
        await _saveIndexState(index, base);
        return;
      }

      status.value = status.value.copyWith(
        phase: ExtensionUpdatePhase.updating,
        message: 'Actualizando ${updates.length} extension(es)...',
        pending: pendingNew,
      );

      var applied = 0;
      final failed = <String>[];
      for (final entry in updates) {
        final ok = await _applyUpdate(entry);
        if (ok) {
          applied++;
        } else {
          failed.add(entry.package);
        }
      }

      await _saveIndexState(index, base);
      ExtensionUtils.refreshPages();
      if (failed.isEmpty) {
        status.value = status.value.copyWith(
          phase: ExtensionUpdatePhase.updated,
          message: applied == 1
              ? '1 extension actualizada'
              : '$applied extensiones actualizadas',
          updated: applied,
          lastCheck: DateTime.now(),
          pending: pendingNew,
        );
      } else {
        status.value = status.value.copyWith(
          phase: ExtensionUpdatePhase.error,
          message:
              'Se actualizaron $applied; fallo: ${failed.join(', ')}. Se conserva la version anterior.',
          updated: applied,
          lastCheck: DateTime.now(),
          pending: pendingNew,
        );
      }
    } catch (e) {
      logger.warning('ExtensionUpdate: $e');
      status.value = status.value.copyWith(
        phase: ExtensionUpdatePhase.error,
        message: 'No se pudieron comprobar las extensiones',
        lastCheck: DateTime.now(),
      );
    } finally {
      _checking = false;
    }
  }

  // ------------------------------------------------------------------ index

  Future<_IndexResponse?> _fetchIndex(String base, {required bool force}) async {
    _lastIndexError = null;
    final url = '$base/index.json';
    final etag = JiruHubStorage.getSetting(SettingKey.extensionUpdateEtag);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Cache-Control': 'no-cache',
    };
    if (!force && etag is String && etag.isNotEmpty) {
      headers['If-None-Match'] = etag;
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await dio.get<String>(
          url,
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
            receiveTimeout: _indexTimeout,
            sendTimeout: _indexTimeout,
            validateStatus: (code) => code != null && code < 500,
          ),
        );
        final code = response.statusCode ?? 0;
        if (code == 304) {
          return null;
        }
        if (code == 403 || code == 429) {
          final retryAfter = response.headers.value('retry-after');
          final seconds = int.tryParse(retryAfter ?? '') ?? 900;
          _blockedUntil = DateTime.now().add(Duration(seconds: seconds));
          _lastIndexError = 'rate-limited';
          status.value = status.value.copyWith(
            phase: ExtensionUpdatePhase.rateLimited,
            message:
                'GitHub limito las solicitudes. Reintento en ~${(seconds / 60).ceil()} min.',
          );
          return null;
        }
        if (code >= 400) {
          lastError = 'HTTP $code';
          continue;
        }
        final body = (response.data ?? '').replaceFirst('\uFEFF', '');
        if (body.isEmpty) {
          return null;
        }
        return _IndexResponse(
          body,
          response.headers.value('etag') ?? '',
        );
      } catch (e) {
        lastError = e;
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }
    if (lastError != null) {
      _lastIndexError = lastError.toString();
      logger.warning('ExtensionUpdate index: $lastError');
    } else {
      _lastIndexError = 'sin respuesta';
    }
    return null;
  }

  Future<void> _saveIndexState(_IndexResponse index, String base) async {
    await JiruHubStorage.setSetting(SettingKey.extensionUpdateCheckedAt,
        DateTime.now().millisecondsSinceEpoch);
    if (index.etag.isNotEmpty) {
      await JiruHubStorage.setSetting(
          SettingKey.extensionUpdateEtag, index.etag);
    }
    await JiruHubStorage.setSetting(
      SettingKey.extensionUpdateIndexHash,
      sha256.convert(utf8.encode(index.body)).toString(),
    );
    await JiruHubStorage.setSetting(SettingKey.extensionUpdateRepo, base);
  }

  List<_ManifestEntry> _parseIndex(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    dynamic list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map) {
      list = decoded['extensions'] ?? decoded['packages'] ?? decoded['data'];
    }
    if (list is! List) return const [];
    final entries = <_ManifestEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final package = item['package']?.toString().trim() ?? '';
      final version = item['version']?.toString().trim() ?? '';
      final url = item['url']?.toString().trim() ?? '';
      if (package.isEmpty || url.isEmpty) continue;
      if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(package)) continue;
      final hashRaw = (item['sha256'] ??
              item['hash'] ??
              item['checksum'] ??
              item['integrity'])
          ?.toString()
          .trim()
          .toLowerCase()
          .replaceFirst('sha256:', '');
      entries.add(_ManifestEntry(
        package: package,
        version: version,
        url: url,
        sha256: hashRaw != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(hashRaw)
            ? hashRaw
            : null,
        size: int.tryParse(item['size']?.toString() ?? ''),
      ));
    }
    return entries;
  }

  Map<String, _LocalExtension> _installedPackages() {
    final result = <String, _LocalExtension>{};
    for (final entry in ExtensionUtils.runtimes.entries) {
      final ext = entry.value.extension;
      result[entry.key] = _LocalExtension(
        version: ext.version,
        hash: _fileHash(p.join(ExtensionUtils.extensionsDir, '${entry.key}.js')),
      );
    }
    // Extensiones instaladas que aun no cargaron tambien cuentan.
    final dir = Directory(ExtensionUtils.extensionsDir);
    if (dir.existsSync()) {
      for (final file in dir.listSync()) {
        if (file is! File || p.extension(file.path) != '.js') continue;
        final package = p.basenameWithoutExtension(file.path);
        if (result.containsKey(package)) continue;
        try {
          final content = file.readAsStringSync();
          final ext = ExtensionUtils.parseExtension(content);
          result[package] = _LocalExtension(
            version: ext.version,
            hash: sha256.convert(utf8.encode(content)).toString(),
          );
        } catch (_) {}
      }
    }
    return result;
  }

  String? _fileHash(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return sha256.convert(file.readAsBytesSync()).toString();
    } catch (_) {
      return null;
    }
  }

  bool _needsUpdate(_ManifestEntry remote, _LocalExtension local) {
    if (remote.version.isNotEmpty &&
        _compareVersions(remote.version, local.version) > 0) {
      return true;
    }
    if (remote.sha256 != null &&
        local.hash != null &&
        remote.sha256 != local.hash) {
      return true;
    }
    return false;
  }

  int _compareVersions(String a, String b) {
    List<int> parts(String value) {
      final cleaned = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final main = cleaned.split('-').first.split('+').first;
      return main
          .split('.')
          .map((e) => int.tryParse(RegExp(r'\d+').firstMatch(e)?.group(0) ?? '') ?? 0)
          .toList();
    }

    final left = parts(a);
    final right = parts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  // ---------------------------------------------------------------- install

  Future<bool> _applyUpdate(_ManifestEntry entry) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final bytes = await _download(entry.url);
        if (bytes == null || bytes.isEmpty) {
          throw StateError('descarga vacia');
        }
        if (entry.size != null && entry.size! > 0 && bytes.length != entry.size) {
          throw StateError('tamano no coincide');
        }
        final hash = sha256.convert(bytes).toString();
        if (entry.sha256 != null && entry.sha256 != hash) {
          throw StateError('sha256 no coincide');
        }
        final content = utf8.decode(bytes);
        if (!content.contains('==MiruExtension==')) {
          throw StateError('no es una extension Yeflix');
        }
        final parsed = ExtensionUtils.parseExtension(content);
        if (parsed.package != entry.package) {
          throw StateError('package no coincide');
        }
        await _atomicInstall(entry.package, content);
        logger.info(
          'ExtensionUpdate: ${entry.package} ${entry.version} instalada',
        );
        return true;
      } catch (e) {
        logger.warning(
          'ExtensionUpdate: fallo ${entry.package} intento $attempt: $e',
        );
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    }
    return false;
  }

  Future<List<int>?> _download(String url) async {
    try {
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: _fileTimeout,
          sendTimeout: _indexTimeout,
          headers: const {'Accept': 'text/javascript, application/javascript, */*'},
          validateStatus: (code) => code != null && code < 400,
        ),
      );
      return response.data;
    } catch (e) {
      logger.warning('ExtensionUpdate download: $e');
      return null;
    }
  }

  Future<void> _atomicInstall(String package, String content) async {
    final savePath = p.join(ExtensionUtils.extensionsDir, '$package.js');
    final temp = File('$savePath.download');
    final backup = File('$savePath.bak');
    ExtensionUtils.beginExtensionUpdate(package);
    try {
      await temp.writeAsString(content, flush: true);
      if (backup.existsSync()) {
        try {
          backup.deleteSync();
        } catch (_) {}
      }
      final current = File(savePath);
      final hadPrevious = current.existsSync();
      if (hadPrevious) {
        await current.rename(backup.path);
      }
      try {
        await temp.rename(savePath);
        await ExtensionUtils.reloadPackage(package);
        if (backup.existsSync()) {
          try {
            backup.deleteSync();
          } catch (_) {}
        }
      } catch (e) {
        // Restaura la version anterior: nunca dejar una extension a medias.
        try {
          if (File(savePath).existsSync()) File(savePath).deleteSync();
        } catch (_) {}
        if (hadPrevious && backup.existsSync()) {
          try {
            await backup.rename(savePath);
            await ExtensionUtils.reloadPackage(package);
          } catch (_) {}
        }
        rethrow;
      }
    } finally {
      ExtensionUtils.endExtensionUpdate(package);
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } catch (_) {}
      }
    }
  }
}

class _ManifestEntry {
  _ManifestEntry({
    required this.package,
    required this.version,
    required this.url,
    this.sha256,
    this.size,
  });

  final String package;
  final String version;
  final String url;
  final String? sha256;
  final int? size;
}

class _LocalExtension {
  _LocalExtension({required this.version, required this.hash});
  final String version;
  final String? hash;
}

class _IndexResponse {
  _IndexResponse(this.body, this.etag);
  final String body;
  final String etag;
}
