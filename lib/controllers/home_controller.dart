import 'package:get/get.dart';
import 'package:jiruhub/models/extension.dart';
import 'package:jiruhub/models/index.dart';
import 'package:jiruhub/data/services/database_service.dart';
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

  Future<void> loadCatalog() async {
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
      try {
        final list =
            await rt.latest(1).timeout(const Duration(seconds: 20));
        return MapEntry(rt, list);
      } catch (_) {
        return MapEntry(rt, <ExtensionListItem>[]);
      }
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
