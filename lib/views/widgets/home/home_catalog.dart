import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jiruhub/controllers/home_controller.dart';
import 'package:jiruhub/views/widgets/extension_item_card.dart';
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
