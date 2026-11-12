import 'dart:async';

import 'package:get/get.dart';
import 'package:jiruhub/models/extension.dart';
import 'package:jiruhub/models/index.dart';
import 'package:jiruhub/data/services/database_service.dart';
import 'package:jiruhub/data/services/extension_service.dart';
import 'package:jiruhub/utils/extension.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';
import 'package:jiruhub/utils/log.dart';

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

  /// Se rellena cuando ninguna fuente devolvió resultados. La vista lo usa
  /// para ofrecer un reintento en vez de dejar el inicio en blanco.
  final RxString catalogError = ''.obs;

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

  List<ExtensionService> _bangumiRuntimes() {
    return ExtensionUtils.runtimes.values
        .where((e) => e.extension.type == ExtensionType.bangumi)
        .where((e) =>
            !e.extension.nsfw ||
            JiruHubStorage.getSetting(SettingKey.enableNSFW))
        .toList();
  }

  Future<List<ExtensionListItem>> _latest(ExtensionService rt) async {
    final package = rt.extension.package;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final list = await rt.latest(1).timeout(const Duration(seconds: 15));
        if (list.isNotEmpty) {
          logger.info('catalog: $package devolvio ${list.length} elementos');
          return list;
        }
        logger.warning(
          'catalog: $package devolvio 0 elementos (intento ${attempt + 1})',
        );
        if (attempt == 1) return list;
      } on TimeoutException {
        // Un reintento no ayuda si la extension se quedo colgada: se omite
        // para que el resto del catalogo no espere el doble.
        logger.warning('catalog: $package excedio 15 s; se omite');
        return <ExtensionListItem>[];
      } catch (e, s) {
        logger.warning(
          'catalog: $package fallo latest(1) (intento ${attempt + 1}): $e',
        );
        if (attempt == 1) {
          // Se registra en jiruhub.log para poder diagnosticar el inicio
          // vacio sin depender de la ventana de logs de la app.
          logger.severe('catalog: $package sin datos', e, s);
          return <ExtensionListItem>[];
        }
      }
      await Future.delayed(const Duration(milliseconds: 900));
    }
    return <ExtensionListItem>[];
  }

  Future<void> _loadCatalogOnce() async {
    var runtimes = _bangumiRuntimes();
    // Las extensiones pueden estar cargandose todavia al abrir la app. Se
    // espera brevemente antes de declarar el inicio vacio.
    for (var i = 0; i < 6 && runtimes.isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      runtimes = _bangumiRuntimes();
    }
    if (runtimes.isEmpty) {
      animes.clear();
      movies.clear();
      series.clear();
      catalogError.value = '';
      catalogLoading.value = false;
      return;
    }
    catalogLoading.value = true;
    catalogError.value = '';

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
        if (u.contains("serieinfo") ||
            u.contains("ver-serie") ||
            u.contains("/serie/")) {
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
    if (an.isEmpty && mv.isEmpty && sr.isEmpty) {
      catalogError.value = 'catalog-empty';
      logger.warning(
        'catalog: ninguna fuente devolvio elementos '
        '(${runtimes.map((e) => e.extension.package).join(', ')})',
      );
    }
    catalogLoading.value = false;
  }
}
