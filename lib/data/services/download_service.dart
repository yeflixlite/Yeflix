import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:jiruhub/models/download.dart';
import 'package:jiruhub/services/source_provider.dart';
import 'package:jiruhub/utils/download_storage.dart';
import 'package:jiruhub/utils/jiruhub_directory.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';
import 'package:jiruhub/utils/log.dart';

/// Gestor de descargas offline (capa Dart).
///
/// Orquesta la descarga de una fuente de reproduccion a almacenamiento privado
/// de la app, persiste el estado y expone la lista para la UI. La descarga
/// real se hace con dio; para fuentes HLS se descarga el manifiesto y los
/// segmentos de la variante seleccionada.
class DownloadService extends GetxService {
  static DownloadService get instance => Get.find<DownloadService>();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      },
    ),
  );
  final _downloads = <DownloadEntry>[].obs;
  final _active = <String, _DownloadTask>{}.obs;

  List<DownloadEntry> get downloads => _downloads;
  Map<String, DownloadEntry> get byId => {for (final d in _downloads) d.id: d};

  bool _initialized = false;

  @override
  Future<void> onInit() async {
    super.onInit();
    await load();
    _initialized = true;
  }

  /// Carga los registros de descarga desde almacenamiento privado.
  Future<void> load() async {
    final list = DownloadStorage.load();
    // Interrupted downloads check: any download in preparing, queued, resolvingSource, downloading, resuming
    // should be marked as paused because the app closed while downloading.
    final updatedList = list.map((d) {
      if (!d.isTerminal && d.status != DownloadStatus.paused) {
        return d.copyWith(
          status: DownloadStatus.paused,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      return d;
    }).toList();
    _downloads.assignAll(updatedList.reversed.toList());
  }

  /// Guarda los registros en almacenamiento privado.
  Future<void> _persist() async {
    await DownloadStorage.save(_downloads);
  }

  /// Directorio privado de descargas de la app.
  Directory get _downloadsDir {
    final dir = Directory(p.join(JiruHubDirectory.getDirectory, 'downloads'));
    dir.createSync(recursive: true);
    return dir;
  }

  /// Genera un id unico para una descarga.
  String _newId(String package, String detailUrl, int episodeIndex) {
    final data = '$package|$detailUrl|$episodeIndex';
    final bytes = utf8.encode(data);
    final hash = _md5(bytes);
    return 'dl_$hash';
  }

  String _md5(List<int> bytes) {
    var content = '';
    for (final b in bytes) {
      content += b.toRadixString(16).padLeft(2, '0');
    }
    return content;
  }

  /// Registros descargados y listos para reproducir.
  List<DownloadEntry> get completed =>
      _downloads.where((d) => d.isPlayable).toList();

  /// Descargas en curso o pendientes.
  List<DownloadEntry> get active =>
      _downloads.where((d) => !d.isTerminal).toList();

  /// Descargas por tipo de contenido.
  List<DownloadEntry> byType(DownloadContentType type) =>
      _downloads.where((d) => d.contentType == type).toList();

  /// Busca una descarga por id.
  DownloadEntry? getById(String id) => byId[id];

  /// Verifica si el contenido ya esta descargado (playable).
  bool isDownloaded(String package, String detailUrl, {int? episodeIndex}) {
    return _downloads.any(
      (d) =>
          d.package == package &&
          d.detailUrl == detailUrl &&
          (episodeIndex == null || d.episodeIndex == episodeIndex) &&
          d.isPlayable,
    );
  }

  /// Inicia una descarga. Retorna el id de la descarga registrada.
  Future<String> startDownload({
    required String package,
    required String title,
    required DownloadContentType contentType,
    required String serverName,
    required String? serverType,
    required String sourceUrl,
    required String sourceType,
    required bool isHls,
    required Map<String, String>? headers,
    required String detailUrl,
    String? episodeName,
    int? episodeIndex,
    int? episodeGroupId,
    String? quality,
    String? qualityLabel,
    List<SourceQuality>? qualities,
  }) async {
    // Evita duplicados: si ya hay una descarga playable para este contenido, no se duplica.
    if (isDownloaded(package, detailUrl, episodeIndex: episodeIndex)) {
      final existing = _downloads.firstWhere(
        (d) =>
            d.package == package &&
            d.detailUrl == detailUrl &&
            (episodeIndex == null || d.episodeIndex == episodeIndex) &&
            d.isPlayable,
      );
      return existing.id;
    }
    // Si hay una descarga no terminal para el mismo contenido, la reutiliza.
    final pending = _downloads.firstWhereOrNull(
      (d) =>
          d.package == package &&
          d.detailUrl == detailUrl &&
          (episodeIndex == null || d.episodeIndex == episodeIndex) &&
          !d.isTerminal,
    );
    if (pending != null) {
      return pending.id;
    }

    final id = _newId(package, detailUrl, episodeIndex ?? 0);
    final now = DateTime.now().millisecondsSinceEpoch;
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ext = isHls ? '.m3u8' : (sourceType == 'mp4' ? '.mp4' : '.dat');
    final fileName = '${safeTitle}_${episodeIndex ?? 0}$ext';
    final entry = DownloadEntry(
      id: id,
      package: package,
      title: title,
      contentType: contentType,
      detailUrl: detailUrl,
      episodeName: episodeName,
      episodeIndex: episodeIndex,
      episodeGroupId: episodeGroupId,
      serverName: serverName,
      serverType: serverType,
      sourceType: sourceType,
      sourceUrl: sourceUrl,
      headers: headers,
      quality: quality,
      qualityLabel: qualityLabel,
      fileName: fileName,
      status: DownloadStatus.preparing,
      createdAt: now,
      updatedAt: now,
      isHls: isHls,
    );
    _downloads.insert(0, entry);
    await _persist();
    _runDownload(entry);
    return id;
  }

  /// Ejecuta la descarga de un registro.
  Future<void> _runDownload(DownloadEntry entry) async {
    final task = _DownloadTask(entry.id);
    _active[entry.id] = task;
    DownloadEntry? updated;
    try {
      final dir = Directory(p.join(_downloadsDir.path, entry.id));
      if (!await dir.exists()) await dir.create(recursive: true);
      final fileName = entry.fileName ?? (entry.isHls ? 'video.m3u8' : 'video.mp4');
      final filePath = p.join(dir.path, fileName);
      updated = entry.copyWith(
        status: DownloadStatus.resolvingSource,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        filePath: filePath,
        fileName: fileName,
      );
      _replace(updated);
      // Pequena pausa para que la UI refleje "resolviendo fuente" antes de transferir.
      await Future.delayed(const Duration(milliseconds: 300));
      if (task.cancelled) {
        _replace(updated.copyWith(status: DownloadStatus.cancelled));
        return;
      }
      updated = entry.copyWith(
        status: DownloadStatus.queued,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        filePath: filePath,
        fileName: fileName,
      );
      _replace(updated);
      await Future.delayed(const Duration(milliseconds: 200));
      if (task.cancelled) {
        _replace(updated.copyWith(status: DownloadStatus.cancelled));
        return;
      }
      updated = entry.copyWith(
        status: DownloadStatus.downloading,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        filePath: filePath,
        fileName: fileName,
      );
      _replace(updated);

      if (entry.isHls) {
        await _downloadHls(entry, updated, task, dir, filePath);
      } else {
        await _downloadFile(entry, updated, task, filePath);
      }

      if (task.cancelled) {
        _replace(updated.copyWith(status: DownloadStatus.cancelled));
        return;
      }
      if (task.error != null) {
        _replace(
            updated.copyWith(status: DownloadStatus.failed, error: task.error));
        return;
      }

      final size = await _calculateTotalSize(filePath, dir, entry.isHls);
      if (size <= 0) {
        throw Exception('El archivo descargado está vacío o no se guardó');
      }
      _replace(
        updated.copyWith(
          status: DownloadStatus.completed,
          totalSize: size,
          downloadedBytes: size,
          progress: 1.0,
          speedBps: 0,
          etaSeconds: null,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e, stack) {
      logger.severe('DownloadService _runDownload error: $e');
      if (task.cancelled) {
        _replace((updated ?? entry).copyWith(status: DownloadStatus.cancelled));
      } else {
        _replace((updated ?? entry).copyWith(
          status: DownloadStatus.failed,
          error: e.toString(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    } finally {
      _active.remove(entry.id);
    }
  }

  Future<void> _downloadFile(
    DownloadEntry entry,
    DownloadEntry updated,
    _DownloadTask task,
    String filePath,
  ) async {
    final headers = <String, String>{};
    if (entry.headers != null) headers.addAll(entry.headers!);
    var lastBytes = 0;
    var lastTime = DateTime.now().millisecondsSinceEpoch;
    await _dio.download(
      entry.sourceUrl,
      filePath,
      onReceiveProgress: (received, total) {
        if (task.cancelled) {
          throw DioException(
            requestOptions: RequestOptions(path: entry.sourceUrl),
            message: 'cancelled',
          );
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final deltaMs = now - lastTime;
        final deltaBytes = received - lastBytes;
        // Velocidad: bytes por segundo (promedio movil simple sobre el ultimo intervalo).
        final bps = deltaMs > 0 ? (deltaBytes * 1000 ~/ deltaMs) : 0;
        lastTime = now;
        lastBytes = received;
        // ETA solo si conocemos el total y la velocidad es significativa.
        int? etaSeconds;
        if (total > 0 && received > 0 && bps > 0 && received < total) {
          final remaining = total - received;
          etaSeconds = remaining ~/ bps;
        }
        final progress = (total > 0 && received <= total)
            ? received / total
            : (total > 0 ? 1.0 : 0.0);
        task.progress = progress;
        task.downloadedBytes = received;
        task.totalSize = total > 0 ? total : received;
        _replace(updated.copyWith(
          downloadedBytes: received,
          totalSize: total > 0 ? total : received,
          progress: progress,
          speedBps: bps,
          etaSeconds: etaSeconds,
          updatedAt: now,
        ));
      },
      options: Options(headers: headers),
      deleteOnError: true,
    );
  }

  String? _selectVariantUrl(String manifestContent, String qualityPref) {
    final lines = manifestContent.split('\n');
    final variants = <_HlsVariantTrack>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        int bandwidth = 0;
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        if (bwMatch != null) {
          bandwidth = int.tryParse(bwMatch.group(1) ?? '0') ?? 0;
        }

        int? height;
        final resMatch = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
        if (resMatch != null) {
          height = int.tryParse(resMatch.group(1) ?? '0');
        }

        for (var j = i + 1; j < lines.length; j++) {
          final nextLine = lines[j].trim();
          if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
            variants.add(_HlsVariantTrack(
              url: nextLine,
              bandwidth: bandwidth,
              height: height,
            ));
            break;
          }
        }
      }
    }

    if (variants.isEmpty) return null;

    // Ordenar de menor a mayor ancho de banda
    variants.sort((a, b) => a.bandwidth.compareTo(b.bandwidth));

    if (qualityPref == 'low') {
      // 480p económica: menor peso (~300-450 MB)
      final lowVariants =
          variants.where((v) => v.height != null && v.height! <= 480).toList();
      if (lowVariants.isNotEmpty) {
        return lowVariants.last.url;
      }
      return variants.first.url;
    } else if (qualityPref == 'high') {
      // 1080p máxima calidad (~1.0 - 1.5 GB)
      return variants.last.url;
    } else {
      // 'standard' (720p - Recomendada): equilibrio ideal (~500-700 MB)
      final standardVariants =
          variants.where((v) => v.height != null && v.height! <= 720).toList();
      if (standardVariants.isNotEmpty) {
        return standardVariants.last.url;
      }
      final bwStandard = variants
          .where((v) => v.bandwidth > 0 && v.bandwidth <= 1600000)
          .toList();
      if (bwStandard.isNotEmpty) {
        return bwStandard.last.url;
      }
      return variants.first.url;
    }
  }

  Future<void> _downloadHls(
    DownloadEntry entry,
    DownloadEntry updated,
    _DownloadTask task,
    Directory dir,
    String finalPlaylistPath,
  ) async {
    final headers = <String, String>{};
    if (entry.headers != null) headers.addAll(entry.headers!);

    // 1. Descarga el manifiesto inicial (puede ser Master o Media Playlist)
    final initialResp = await _dio.get<String>(
      entry.sourceUrl,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
      ),
    );
    var manifestContent = initialResp.data ?? '';
    var baseUri = Uri.parse(entry.sourceUrl);

    // 2. Si es Master Playlist (#EXT-X-STREAM-INF), extraer la mejor variante según la preferencia de calidad
    if (manifestContent.contains('#EXT-X-STREAM-INF')) {
      final qualityPref =
          (JiruHubStorage.getSetting(SettingKey.downloadQuality) as String?) ??
              'standard';
      final variantUrl = _selectVariantUrl(manifestContent, qualityPref);

      if (variantUrl != null) {
        baseUri = baseUri.resolve(variantUrl);
        final variantResp = await _dio.get<String>(
          baseUri.toString(),
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
          ),
        );
        manifestContent = variantResp.data ?? '';
      }
    }

    // 3. Analizar la lista de medios y construir el manifiesto local válido
    final lines = manifestContent.split('\n');
    final segments = <_HlsSegment>[];
    final localPlaylistLines = <String>[];
    int segIndex = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        localPlaylistLines.add(line);
        // La siguiente línea no vacía y que no sea comentario es la URL del segmento
        for (var j = i + 1; j < lines.length; j++) {
          final nextLine = lines[j].trim();
          if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
            final segUri = baseUri.resolve(nextLine);
            final origPath = Uri.parse(nextLine).path;
            final ext = p.extension(origPath).isNotEmpty ? p.extension(origPath) : '.ts';
            final localSegName = 'seg_${segIndex.toString().padLeft(4, '0')}$ext';
            segments.add(_HlsSegment(segUri.toString(), localSegName));
            localPlaylistLines.add(localSegName);
            segIndex++;
            i = j;
            break;
          }
        }
      } else {
        // Mantener etiquetas estándar (#EXTM3U, #EXT-X-VERSION, #EXT-X-TARGETDURATION, etc.)
        localPlaylistLines.add(line);
      }
    }

    if (!localPlaylistLines.any((l) => l.startsWith('#EXT-X-ENDLIST'))) {
      localPlaylistLines.add('#EXT-X-ENDLIST');
    }

    if (segments.isEmpty) {
      throw Exception('No se encontraron segmentos en la lista HLS');
    }

    final total = segments.length;
    var received = 0;
    var totalDownloadedBytes = 0;
    var lastBytes = 0;
    var lastTime = DateTime.now().millisecondsSinceEpoch;

    void updateProgress({bool force = false}) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final deltaMs = now - lastTime;
      if (force || deltaMs >= 400 || received >= total) {
        final deltaBytes = totalDownloadedBytes - lastBytes;
        final bps = deltaMs > 0 ? (deltaBytes * 1000 ~/ deltaMs) : 0;
        lastTime = now;
        lastBytes = totalDownloadedBytes;

        int? etaSeconds;
        if (received > 0 && bps > 0 && received < total) {
          final avgBytesPerSeg = totalDownloadedBytes ~/ received;
          final remainingBytes = avgBytesPerSeg * (total - received);
          etaSeconds = remainingBytes ~/ bps;
        }

        task.progress = total > 0 ? received / total : 0;
        task.downloadedBytes = totalDownloadedBytes;
        task.totalSize =
            received > 0 ? (totalDownloadedBytes * total ~/ received) : 0;

        _replace(updated.copyWith(
          downloadedBytes: totalDownloadedBytes,
          totalSize: task.totalSize,
          progress: task.progress,
          speedBps: bps,
          etaSeconds: etaSeconds,
          updatedAt: now,
        ));
      }
    }

    // 4. Descargar concurrentemente los segmentos con cola de trabajadores (3 en paralelo)
    int nextIndex = 0;
    const concurrency = 3;

    Future<void> worker() async {
      while (true) {
        if (task.cancelled) break;
        if (nextIndex >= segments.length) break;
        final idx = nextIndex++;
        final seg = segments[idx];
        final segFile = File(p.join(dir.path, seg.localName));

        // Comprobar si ya existe del intento anterior (reanudar)
        if (await segFile.exists()) {
          final existingLen = await segFile.length();
          if (existingLen > 0) {
            received++;
            totalDownloadedBytes += existingLen;
            updateProgress();
            continue;
          }
        }

        bool success = false;
        try {
          await _dio.download(
            seg.remoteUrl,
            segFile.path,
            options: Options(headers: headers),
          );
          success = true;
        } catch (e) {
          if (task.cancelled) break;
          logger.severe('HLS segmento fallido ${seg.remoteUrl}: $e');
          // Reintento único ante micro-cortes
          try {
            await Future.delayed(const Duration(milliseconds: 300));
            if (task.cancelled) break;
            await _dio.download(
              seg.remoteUrl,
              segFile.path,
              options: Options(headers: headers),
            );
            success = true;
          } catch (retryError) {
            logger.severe('Reintento fallido para ${seg.remoteUrl}: $retryError');
          }
        }

        if (success && await segFile.exists()) {
          final segSize = await segFile.length();
          received++;
          totalDownloadedBytes += segSize;
        }

        updateProgress();
      }
    }

    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);

    updateProgress(force: true);

    if (task.cancelled) return;

    // 5. Guardar el manifiesto m3u8 local con referencias locales relativas
    await File(finalPlaylistPath).writeAsString(localPlaylistLines.join('\n'));
  }

  Future<int> _calculateTotalSize(String filePath, Directory dir, bool isHls) async {
    if (!isHls) {
      return await _fileSize(filePath);
    }
    int total = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: false)) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      }
    } catch (_) {}
    return total;
  }

  void _replace(DownloadEntry entry) {
    final idx = _downloads.indexWhere((d) => d.id == entry.id);
    if (idx != -1) {
      _downloads[idx] = entry;
      _persist();
    } else {
      _downloads.add(entry);
      _persist();
    }
  }

  Future<int> _fileSize(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return 0;
      return await f.length();
    } catch (_) {
      return 0;
    }
  }

  /// Pausa una descarga en curso (o en cola / reanudando).
  Future<void> pause(String id) async {
    final task = _active[id];
    if (task != null) task.cancel();
    final entry = byId[id];
    if (entry != null &&
        (entry.status == DownloadStatus.downloading ||
            entry.status == DownloadStatus.queued ||
            entry.status == DownloadStatus.resuming)) {
      _replace(entry.copyWith(
        status: DownloadStatus.paused,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  /// Reanuda una descarga pausada.
  Future<void> resume(String id) async {
    final entry = byId[id];
    if (entry == null || entry.status != DownloadStatus.paused) return;
    _replace(entry.copyWith(
      status: DownloadStatus.resuming,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _runDownload(entry.copyWith(status: DownloadStatus.downloading));
  }

  /// Cancela y elimina una descarga (registro y archivo local).
  Future<void> cancelAndDelete(String id) async {
    final task = _active[id];
    if (task != null) task.cancel();
    final entry = byId[id];
    if (entry != null) {
      await _removeFiles(entry);
      _downloads.removeWhere((d) => d.id == id);
      _active.remove(id);
      await _persist();
    }
  }

  Future<void> _removeFiles(DownloadEntry entry) async {
    if (entry.filePath != null) {
      try {
        final f = File(entry.filePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    // Carpeta del descargado (HLS segmentos)
    if (entry.id.isNotEmpty) {
      try {
        final dir = Directory(p.join(_downloadsDir.path, entry.id));
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Elimina el registro de una descarga fallida o cancelada sin afectar al resto.
  Future<void> remove(String id) async {
    final entry = byId[id];
    if (entry == null) return;
    await _removeFiles(entry);
    _downloads.removeWhere((d) => d.id == id);
    _active.remove(id);
    await _persist();
  }
}

class _DownloadTask {
  _DownloadTask(this.id);
  final String id;
  bool cancelled = false;
  double progress = 0;
  int downloadedBytes = 0;
  int totalSize = 0;
  String? error;

  void cancel() => cancelled = true;
}

class _HlsSegment {
  _HlsSegment(this.remoteUrl, this.localName);
  final String remoteUrl;
  final String localName;
}

class _HlsVariantTrack {
  _HlsVariantTrack({required this.url, required this.bandwidth, this.height});
  final String url;
  final int bandwidth;
  final int? height;
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
