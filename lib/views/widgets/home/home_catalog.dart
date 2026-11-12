import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jiruhub/controllers/home_controller.dart';
import 'package:jiruhub/views/widgets/extension_item_card.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/utils/yeflix_style.dart';

class HomeCatalog extends StatelessWidget {
  const HomeCatalog({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final c = Get.find<HomePageController>();
      if (c.catalogLoading.value &&
          c.animes.isEmpty &&
          c.movies.isEmpty &&
          c.series.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        );
      }
      if (c.catalogError.value.isNotEmpty &&
          c.animes.isEmpty &&
          c.movies.isEmpty &&
          c.series.isEmpty) {
        return _errorState(c);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row("Animes", c.animes),
          _row("Películas", c.movies),
          _row("Series", c.series),
        ],
      );
    });
  }

  Widget _errorState(HomePageController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        children: [
          Text(
            "home.error-title".i18n,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            "home.error-subtitle".i18n,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: YeflixStyle.textMuted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: c.loadCatalog,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text("common.retry".i18n),
            style: FilledButton.styleFrom(
              backgroundColor: YeflixStyle.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, List<CatalogItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        YeflixSectionHeader(title: title),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final entry = items[index];
              final item = entry.item;
              return Container(
                width: 110,
                margin: const EdgeInsets.only(right: 14),
                child: ExtensionItemCard(
                  key: ValueKey(item.url),
                  title: item.title,
                  url: item.url,
                  package: entry.package,
                  cover: item.cover,
                  update: item.update,
                  headers: item.headers,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
