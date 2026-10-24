import 'package:get/get.dart';
import 'package:jiruhub/data/services/download_service.dart';
import 'package:jiruhub/models/download.dart';

/// Controlador de la UI de descargas offline. Delegan toda la logica en
/// [DownloadService] y solo expone el estado para las vistas.
class DownloadController extends GetxController {
  DownloadService get _s {
    if (!Get.isRegistered<DownloadService>()) {
      return Get.put(DownloadService(), permanent: true);
    }
    return DownloadService.instance;
  }

  List<DownloadEntry> get downloads => _s.downloads;
  List<DownloadEntry> get completed => _s.completed;
  List<DownloadEntry> get active => _s.active;
  List<DownloadEntry> byType(DownloadContentType type) => _s.byType(type);

  bool isDownloaded(String package, String detailUrl, {int? episodeIndex}) =>
      _s.isDownloaded(package, detailUrl, episodeIndex: episodeIndex);

  DownloadEntry? getById(String id) => _s.getById(id);

  Future<void> pause(String id) => _s.pause(id);

  Future<void> resume(String id) => _s.resume(id);

  Future<void> cancelAndDelete(String id) => _s.cancelAndDelete(id);

  Future<void> remove(String id) => _s.remove(id);

  String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  String progressPercent(double p) => '${(p * 100).toStringAsFixed(0)}%';

  @override
  void refresh() => _s.load();
}
