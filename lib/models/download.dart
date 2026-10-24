library jiruhub.download;

/// Estado de una descarga offline.
///
/// Estados obligatorios que debe poder mostrar cada tarea de descarga:
/// preparando, resolviendo fuente, en cola, descargando, pausada,
/// reanudando, completada, error, cancelada.
enum DownloadStatus {
  /// Se esta creando la tarea y validando la fuente.
  preparing,
  /// Se esta resolviendo la URL de reproduccion del servidor seleccionado.
  resolvingSource,
  /// La tarea esta en cola esperando recursos de red/almacenamiento.
  queued,
  /// Se esta transferiendo datos.
  downloading,
  /// Pausada por el usuario o por interrupcion de red.
  paused,
  /// Se esta reanudando una descarga previa.
  resuming,
  /// Completa y lista para reproducir offline.
  completed,
  /// Terminó con error (red, almacenamiento, fuente incompatibile).
  failed,
  /// Cancelada por el usuario y archivo eliminado.
  cancelled,
}

/// Tipo de contenido descargable.
enum DownloadContentType { movie, episode }

/// Registro de una descarga offline.
///
/// No se usa Isar para evitar depender de codegen (build_runner) en entornos
/// sin SDK de Flutter. La persistencia se hace en un archivo JSON mediante
/// [DownloadStorage]. Cuando se integre un descargador nativo (Media3) este
/// modelo es el contrato entre la capa Dart y la capa nativa.
class DownloadEntry {
  DownloadEntry({
    required this.id,
    required this.package,
    required this.title,
    required this.contentType,
    required this.serverName,
    required this.sourceType,
    required this.sourceUrl,
    this.detailUrl = '',
    this.episodeName,
    this.episodeIndex,
    this.episodeGroupId,
    this.serverType,
    this.headers,
    this.quality,
    this.qualityLabel,
    this.fileName,
    this.filePath,
    this.totalSize = 0,
    this.downloadedBytes = 0,
    this.progress = 0.0,
    this.speedBps = 0,
    this.etaSeconds,
    this.status = DownloadStatus.preparing,
    this.error,
    this.createdAt,
    this.updatedAt,
    this.isHls = false,
  });

  final String id;
  final String package;
  final String title;
  final DownloadContentType contentType;
  final String detailUrl;
  final String? episodeName;
  final int? episodeIndex;
  final int? episodeGroupId;
  final String serverName;
  final String? serverType;
  final String sourceType;
  final String sourceUrl;
  final Map<String, String>? headers;
  final String? quality;
  final String? qualityLabel;
  final String? fileName;
  final String? filePath;
  final int totalSize;
  final int downloadedBytes;
  final double progress;
  /// Velocidad actual en bytes por segundo (medida durante la descarga).
  final int speedBps;
  /// Tiempo restante estimado en segundos (solo si hay datos suficientes).
  final int? etaSeconds;
  final DownloadStatus status;
  final String? error;
  final int? createdAt;
  final int? updatedAt;
  final bool isHls;

  DownloadEntry copyWith({
    String? id,
    String? package,
    String? title,
    DownloadContentType? contentType,
    String? detailUrl,
    String? episodeName,
    int? episodeIndex,
    int? episodeGroupId,
    String? serverName,
    String? serverType,
    String? sourceType,
    String? sourceUrl,
    Map<String, String>? headers,
    String? quality,
    String? qualityLabel,
    String? fileName,
    String? filePath,
    int? totalSize,
    int? downloadedBytes,
    double? progress,
    int? speedBps,
    int? etaSeconds,
    DownloadStatus? status,
    String? error,
    int? createdAt,
    int? updatedAt,
    bool? isHls,
  }) {
    return DownloadEntry(
      id: id ?? this.id,
      package: package ?? this.package,
      title: title ?? this.title,
      contentType: contentType ?? this.contentType,
      detailUrl: detailUrl ?? this.detailUrl,
      episodeName: episodeName ?? this.episodeName,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      episodeGroupId: episodeGroupId ?? this.episodeGroupId,
      serverName: serverName ?? this.serverName,
      serverType: serverType ?? this.serverType,
      sourceType: sourceType ?? this.sourceType,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      headers: headers ?? this.headers,
      quality: quality ?? this.quality,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      totalSize: totalSize ?? this.totalSize,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      progress: progress ?? this.progress,
      speedBps: speedBps ?? this.speedBps,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      status: status ?? this.status,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isHls: isHls ?? this.isHls,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'package': package,
      'title': title,
      'contentType': contentType.index,
      'detailUrl': detailUrl,
      'episodeName': episodeName,
      'episodeIndex': episodeIndex,
      'episodeGroupId': episodeGroupId,
      'serverName': serverName,
      'serverType': serverType,
      'sourceType': sourceType,
      'sourceUrl': sourceUrl,
      'headers': headers,
      'quality': quality,
      'qualityLabel': qualityLabel,
      'fileName': fileName,
      'filePath': filePath,
      'totalSize': totalSize,
      'downloadedBytes': downloadedBytes,
      'progress': progress,
      'speedBps': speedBps,
      'etaSeconds': etaSeconds,
      'status': status.index,
      'error': error,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isHls': isHls,
    };
  }

  factory DownloadEntry.fromMap(Map<String, dynamic> m) {
    return DownloadEntry(
      id: m['id'] as String,
      package: m['package'] as String,
      title: m['title'] as String,
      contentType: DownloadContentType.values[m['contentType'] as int],
      detailUrl: m['detailUrl'] as String? ?? '',
      episodeName: m['episodeName'] as String?,
      episodeIndex: m['episodeIndex'] as int?,
      episodeGroupId: m['episodeGroupId'] as int?,
      serverName: m['serverName'] as String,
      serverType: m['serverType'] as String?,
      sourceType: m['sourceType'] as String? ?? 'unknown',
      sourceUrl: m['sourceUrl'] as String? ?? '',
      headers: (m['headers'] as Map?)?.cast<String, String>(),
      quality: m['quality'] as String?,
      qualityLabel: m['qualityLabel'] as String?,
      fileName: m['fileName'] as String?,
      filePath: m['filePath'] as String?,
      totalSize: (m['totalSize'] as num?)?.toInt() ?? 0,
      downloadedBytes: (m['downloadedBytes'] as num?)?.toInt() ?? 0,
      progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
      speedBps: (m['speedBps'] as num?)?.toInt() ?? 0,
      etaSeconds: m['etaSeconds'] as int?,
      status: DownloadStatus.values[m['status'] as int],
      error: m['error'] as String?,
      createdAt: m['createdAt'] as int?,
      updatedAt: m['updatedAt'] as int?,
      isHls: m['isHls'] as bool? ?? false,
    );
  }

  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  bool get isPlayable =>
      status == DownloadStatus.completed && filePath != null && filePath!.isNotEmpty;

  @override
  String toString() {
    return 'DownloadEntry(id=$id, title=$title, server=$serverName, status=$status, progress=$progress)';
  }
}
