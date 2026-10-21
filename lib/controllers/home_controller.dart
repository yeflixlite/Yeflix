import 'package:get/get.dart';
import 'package:jiruhub/models/extension.dart';
import 'package:jiruhub/models/index.dart';
import 'package:jiruhub/data/services/database_service.dart';
import 'package:jiruhub/data/services/extension_service.dart';
import 'package:jiruhub/utils/extension.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';

class CatalogItem {
  CatalogItem(this.item, this.package);
  final ExtensionListItem item;
  final String package;
}

class HomePageController extends GetxController {
  final RxList<History> resents = <History>[].obs;
  final RxMap<ExtensionType, List<Favorite>> favorites =
      <ExtensionType, List<Favorite>>{}.obs;

  final RxList<CatalogItem> animes = <CatalogItem>[].obs;
  final RxList<CatalogItem> movies = <CatalogItem>[].obs;
  final RxList<CatalogItem> series = <CatalogItem>[].obs;
  final RxBool catalogLoading = true.obs;

  @override
  void onInit() {
    onRefresh();
    super.onInit();
  }

  refreshHistory() async {
    resents.clear();
    resents.addAll(
      await DatabaseService.getHistorysByType(),
    );
  }

  onRefresh() async {
    favorites.clear();
    await refreshHistory();
    favorites.addAll({
      ExtensionType.bangumi: await DatabaseService.getFavoritesByType(
        type: ExtensionType.bangumi,
        limit: 20,
      ),
      ExtensionType.manga: await DatabaseService.getFavoritesByType(
        type: ExtensionType.manga,
        limit: 20,
      ),
    });
    await loadCatalog();
  }

  bool _catalogRunning = false;
  bool _catalogQueued = false;

  Future<void> loadCatalog() async {
    if (_catalogRunning) {
      _catalogQueued = true;
      return;
    }
    _catalogRunning = true;
    try {
      do {
        _catalogQueued = false;
        await _loadCatalogOnce();
      } while (_catalogQueued);
    } finally {
      _catalogRunning = false;
    }
  }

  Future<List<ExtensionListItem>> _latest(ExtensionService rt) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final list =
            await rt.latest(1).timeout(const Duration(seconds: 25));
        if (list.isNotEmpty || attempt == 1) return list;
      } catch (_) {
        if (attempt == 1) return <ExtensionListItem>[];
      }
      await Future.delayed(const Duration(milliseconds: 900));
    }
    return <ExtensionListItem>[];
  }

  Future<void> _loadCatalogOnce() async {
    final runtimes = ExtensionUtils.runtimes.values
        .where((e) => e.extension.type == ExtensionType.bangumi)
        .where((e) =>
            !e.extension.nsfw ||
            JiruHubStorage.getSetting(SettingKey.enableNSFW))
        .toList();
    if (runtimes.isEmpty) {
      animes.clear();
      movies.clear();
      series.clear();
      catalogLoading.value = false;
      return;
    }
    catalogLoading.value = true;

    final results = await Future.wait(runtimes.map((rt) async {
      return MapEntry(rt, await _latest(rt));
    }));

    final an = <CatalogItem>[];
    final mv = <CatalogItem>[];
    final sr = <CatalogItem>[];
    for (final entry in results) {
      final package = entry.key.extension.package;
      for (final item in entry.value) {
        final u = item.url.toLowerCase();
        if (u.contains("serieinfo") || u.contains("ver-serie")) {
          sr.add(CatalogItem(item, package));
        } else if (u.contains("movieinfo") || u.contains("/pelicula/")) {
          mv.add(CatalogItem(item, package));
        } else {
          an.add(CatalogItem(item, package));
        }
      }
    }

    animes.assignAll(an.take(20));
    movies.assignAll(mv.take(20));
    series.assignAll(sr.take(20));
    catalogLoading.value = false;
  }
}
