import 'dart:convert';
import 'dart:io';

import 'package:jiruhub/models/download.dart';
import 'package:jiruhub/utils/jiruhub_directory.dart';
import 'package:jiruhub/utils/log.dart';
import 'package:path/path.dart' as p;

/// Persistencia de descargas offline en un archivo JSON dentro del directorio
/// de documentos de la app (almacenamiento privado, sin permisos extra).
class DownloadStorage {
  static const _fileName = 'downloads.json';

  static String get _filePath => p.join(JiruHubDirectory.getDirectory, _fileName);

  static List<DownloadEntry> load() {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return [];
      final json = jsonDecode(file.readAsStringSync());
      if (json == null || json is! List) return [];
      return json
          .map<DownloadEntry>((e) => DownloadEntry.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      logger.severe('DownloadStorage.load error: $e');
      return [];
    }
  }

  static Future<void> save(List<DownloadEntry> downloads) async {
    try {
      final file = File(_filePath);
      final dir = Directory(p.dirname(_filePath));
      if (!await dir.exists()) await dir.create(recursive: true);
      final json = downloads.map((e) => e.toMap()).toList();
      await file.writeAsString(jsonEncode(json), flush: true);
    } catch (e) {
      logger.severe('DownloadStorage.save error: $e');
      rethrow;
    }
  }
}
