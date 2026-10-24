import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jiruhub/controllers/download_controller.dart';
import 'package:jiruhub/controllers/main_controller.dart';
import 'package:jiruhub/models/download.dart';
import 'package:jiruhub/models/extension.dart';
import 'package:jiruhub/utils/extension.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/utils/yeflix_style.dart';
import 'package:jiruhub/views/pages/watch/video/video_player.dart';
import 'package:jiruhub/views/widgets/platform_widget.dart';

class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key});

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  late final DownloadController c;

  @override
  void initState() {
    c = Get.put(DownloadController());
    super.initState();
  }

  @override
  void dispose() {
    Get.delete<DownloadController>();
    super.dispose();
  }

  String _statusLabel(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.preparing:
        return 'offline.status-preparing'.i18n;
      case DownloadStatus.resolvingSource:
        return 'offline.status-resolving'.i18n;
      case DownloadStatus.queued:
        return 'offline.status-queued'.i18n;
      case DownloadStatus.downloading:
        return 'offline.status-downloading'.i18n;
      case DownloadStatus.paused:
        return 'offline.status-paused'.i18n;
      case DownloadStatus.resuming:
        return 'offline.status-resuming'.i18n;
      case DownloadStatus.completed:
        return 'offline.status-completed'.i18n;
      case DownloadStatus.failed:
        return 'offline.status-failed'.i18n;
      case DownloadStatus.cancelled:
        return 'offline.status-cancelled'.i18n;
    }
  }

  Color _statusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
      case DownloadStatus.downloading:
      case DownloadStatus.resuming:
        return YeflixStyle.red;
      case DownloadStatus.paused:
      case DownloadStatus.queued:
      case DownloadStatus.preparing:
      case DownloadStatus.resolvingSource:
        return YeflixStyle.textMuted;
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return YeflixStyle.redDeep;
    }
  }

  String _formatSpeed(int bps) {
    if (bps <= 0) return '';
    const units = ['B/s', 'KB/s', 'MB/s'];
    var index = 0;
    var size = bps.toDouble();
    while (size >= 1024 && index < units.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
  }

  String _formatEta(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    if (minutes > 0) return '~${minutes}m ${remaining}s';
    return '~${remaining}s';
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: (context) => Scaffold(
        backgroundColor: YeflixStyle.bg,
        appBar: AppBar(
          backgroundColor: YeflixStyle.bg,
          elevation: 0,
          title: Text(
            'offline.title'.i18n,
            style: const TextStyle(
              color: YeflixStyle.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          centerTitle: false,
          iconTheme: const IconThemeData(color: YeflixStyle.textPrimary),
        ),
        body: _body(14),
      ),
      desktopBuilder: (context) => Scaffold(
        backgroundColor: YeflixStyle.bg,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _body(24),
          ),
        ),
      ),
    );
  }

  Widget _body(double padding) {
    return Obx(() {
      final active = _sorted(c.active);
      final completed = c.completed;
      final failed = c.downloads
          .where(
            (entry) =>
                entry.status == DownloadStatus.failed ||
                entry.status == DownloadStatus.cancelled,
          )
          .toList();

      if (c.downloads.isEmpty) return _emptyState();

      return RefreshIndicator(
        color: YeflixStyle.red,
        onRefresh: () async => c.refresh(),
        child: ListView(
          padding: EdgeInsets.all(padding),
          children: [
            if (active.isNotEmpty) ...[
              _section('offline.active'.i18n, '${active.length}'),
              ...active.map(_entryCard),
              const SizedBox(height: 16),
            ],
            if (completed.isNotEmpty) ...[
              _section('offline.completed'.i18n, '${completed.length}'),
              ...completed.map(_entryCard),
              const SizedBox(height: 16),
            ],
            if (failed.isNotEmpty) ...[
              _section('offline.errors'.i18n, '${failed.length}'),
              ...failed.map(_entryCard),
            ],
          ],
        ),
      );
    });
  }

  List<DownloadEntry> _sorted(List<DownloadEntry> list) {
    const order = {
      DownloadStatus.downloading: 0,
      DownloadStatus.resuming: 1,
      DownloadStatus.resolvingSource: 2,
      DownloadStatus.preparing: 3,
      DownloadStatus.queued: 4,
      DownloadStatus.paused: 5,
      DownloadStatus.failed: 6,
      DownloadStatus.completed: 7,
      DownloadStatus.cancelled: 8,
    };
    final sorted = List<DownloadEntry>.from(list);
    sorted.sort((a, b) {
      final first = order[a.status] ?? 99;
      final second = order[b.status] ?? 99;
      if (first != second) return first.compareTo(second);
      return (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0);
    });
    return sorted;
  }

  Widget _section(String title, String count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: YeflixStyle.red,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: YeflixStyle.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            count,
            style: const TextStyle(
              color: YeflixStyle.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(DownloadEntry entry) {
    final failed = entry.status == DownloadStatus.failed ||
        entry.status == DownloadStatus.cancelled;
    final statusColor = _statusColor(entry.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: YeflixStyle.surface,
        borderRadius: BorderRadius.circular(YeflixStyle.radius),
        border: Border.all(color: YeflixStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: entry.isPlayable ? () => _play(entry) : null,
            contentPadding: const EdgeInsets.all(12),
            leading: Container(
              width: 56,
              height: 80,
              decoration: BoxDecoration(
                color: YeflixStyle.surfaceAlt,
                borderRadius: BorderRadius.circular(YeflixStyle.radiusSm),
              ),
              child: const Icon(Icons.movie, color: YeflixStyle.textMuted),
            ),
            title: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: YeflixStyle.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: statusColor.withOpacity(0.45),
                        ),
                      ),
                      child: Text(
                        _statusLabel(entry.status),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (entry.serverName.isNotEmpty)
                      Flexible(
                        child: Text(
                          entry.serverName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: YeflixStyle.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                if (entry.error != null && failed)
                  Text(
                    entry.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: YeflixStyle.redDeep,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            trailing: _actions(entry),
          ),
          const Divider(
            color: YeflixStyle.border,
            height: 1,
            indent: 12,
            endIndent: 12,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: entry.totalSize > 0
                              ? entry.downloadedBytes / entry.totalSize
                              : null,
                          minHeight: 6,
                          backgroundColor: YeflixStyle.surfaceAlt,
                          valueColor:
                              const AlwaysStoppedAnimation(YeflixStyle.red),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 72,
                      child: Text(
                        entry.totalSize > 0
                            ? '${(entry.progress * 100).toStringAsFixed(0)}%'
                            : '?%',
                        style: const TextStyle(
                          color: YeflixStyle.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${c.formatBytes(entry.downloadedBytes)} / '
                        '${entry.totalSize > 0 ? c.formatBytes(entry.totalSize) : '?'}',
                        style: const TextStyle(
                          color: YeflixStyle.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (entry.speedBps > 0)
                      Text(
                        _formatSpeed(entry.speedBps),
                        style: const TextStyle(
                          color: YeflixStyle.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    if (entry.speedBps > 0) const SizedBox(width: 10),
                    if (entry.etaSeconds != null && entry.speedBps > 0)
                      Text(
                        _formatEta(entry.etaSeconds),
                        style: const TextStyle(
                          color: YeflixStyle.textMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(DownloadEntry entry) {
    if (entry.isPlayable) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Reproducir',
            icon: const Icon(
              Icons.play_circle_fill,
              color: YeflixStyle.red,
              size: 30,
            ),
            onPressed: () => _play(entry),
          ),
          IconButton(
            tooltip: 'Eliminar película',
            icon: const Icon(
              Icons.delete_outline,
              color: YeflixStyle.textMuted,
              size: 24,
            ),
            onPressed: () => _confirmDelete(entry),
          ),
        ],
      );
    }

    if (entry.status == DownloadStatus.downloading ||
        entry.status == DownloadStatus.queued ||
        entry.status == DownloadStatus.resuming) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Pausar',
            icon: const Icon(
              Icons.pause_circle_outline,
              color: YeflixStyle.textPrimary,
              size: 26,
            ),
            onPressed: () => c.pause(entry.id),
          ),
          IconButton(
            tooltip: 'Cancelar y eliminar',
            icon: const Icon(
              Icons.close,
              color: YeflixStyle.textMuted,
              size: 24,
            ),
            onPressed: () => _confirmDelete(entry),
          ),
        ],
      );
    }

    if (entry.status == DownloadStatus.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Reanudar',
            icon: const Icon(
              Icons.play_circle_outline,
              color: YeflixStyle.textPrimary,
              size: 26,
            ),
            onPressed: () => c.resume(entry.id),
          ),
          IconButton(
            tooltip: 'Cancelar y eliminar',
            icon: const Icon(
              Icons.close,
              color: YeflixStyle.textMuted,
              size: 24,
            ),
            onPressed: () => _confirmDelete(entry),
          ),
        ],
      );
    }

    return IconButton(
      tooltip: 'Eliminar',
      icon: const Icon(
        Icons.delete_outline,
        color: YeflixStyle.redDeep,
        size: 24,
      ),
      onPressed: () => _confirmDelete(entry),
    );
  }

  Future<void> _confirmDelete(DownloadEntry entry) async {
    final sizeStr = entry.totalSize > 0
        ? c.formatBytes(entry.totalSize)
        : (entry.downloadedBytes > 0 ? c.formatBytes(entry.downloadedBytes) : '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: YeflixStyle.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YeflixStyle.radius),
          side: const BorderSide(color: YeflixStyle.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: YeflixStyle.red, size: 26),
            SizedBox(width: 8),
            Text(
              '¿Eliminar descarga?',
              style: TextStyle(
                color: YeflixStyle.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          entry.isPlayable
              ? 'Se eliminarán completamente los archivos descargados de "${entry.title}"${sizeStr.isNotEmpty ? ' ($sizeStr)' : ''} del dispositivo para liberar espacio.'
              : '¿Deseas cancelar y eliminar la descarga de "${entry.title}"?',
          style: const TextStyle(color: YeflixStyle.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: YeflixStyle.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: YeflixStyle.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YeflixStyle.radiusSm),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Eliminar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await c.cancelAndDelete(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${entry.title}" ha sido eliminada'),
            backgroundColor: YeflixStyle.surfaceAlt,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: YeflixStyle.surfaceAlt,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: YeflixStyle.border),
              ),
              child: const Icon(
                Icons.file_download_outlined,
                size: 34,
                color: YeflixStyle.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'offline.empty-title'.i18n,
              style: const TextStyle(
                color: YeflixStyle.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'offline.empty-message'.i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: YeflixStyle.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _play(DownloadEntry entry) async {
    if (entry.filePath == null || entry.filePath!.isEmpty) {
      Get.snackbar(
        'Error',
        'Ruta de archivo no válida',
        backgroundColor: YeflixStyle.surfaceAlt,
        colorText: YeflixStyle.textPrimary,
      );
      return;
    }

    final file = File(entry.filePath!);
    if (!file.existsSync() || file.lengthSync() == 0) {
      Get.snackbar(
        'Archivo no encontrado',
        'El archivo descargado no existe o está incompleto en el almacenamiento.',
        backgroundColor: YeflixStyle.surfaceAlt,
        colorText: YeflixStyle.textPrimary,
      );
      return;
    }

    final runtime = ExtensionUtils.runtimes[entry.package];
    Get.find<MainController>().setAcitons([]);

    await Get.to(
      () => VideoPlayer(
        title: entry.title,
        playList: [
          ExtensionEpisode(
            name: entry.episodeName ?? entry.title,
            url: entry.filePath!,
          ),
        ],
        runtime: runtime,
        playerIndex: 0,
        episodeGroupId: entry.episodeGroupId ?? 0,
        detailUrl: entry.detailUrl,
        anilistID: '',
        localFilePath: entry.filePath,
      ),
    );
  }
}
