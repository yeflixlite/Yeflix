import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jiruhub/models/extension.dart';
import 'package:jiruhub/controllers/home_controller.dart';
import 'package:jiruhub/controllers/main_controller.dart';
import 'package:jiruhub/controllers/search_controller.dart';
import 'package:jiruhub/views/widgets/home/home_favorites.dart';
import 'package:jiruhub/views/widgets/home/home_recent.dart';
import 'package:jiruhub/views/widgets/home/home_catalog.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/utils/yeflix_style.dart';
import 'package:jiruhub/views/widgets/platform_widget.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late HomePageController c;

  @override
  void initState() {
    c = Get.put(HomePageController());
    super.initState();
  }

  Widget _searchBar() {
    return InkWell(
      onTap: () {
        Get.put(SearchPageController());
        Get.find<MainController>().changeTab(1);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 20, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "home.search-hint".i18n,
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 18),
      decoration: const BoxDecoration(
        gradient: YeflixStyle.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YeflixMark(size: 42),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Yeflix",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      height: 1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "home.tagline".i18n,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _searchBar(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: YeflixStyle.surface,
              shape: BoxShape.circle,
              border: Border.all(color: YeflixStyle.border),
            ),
            child: const Icon(
              Icons.movie_filter_rounded,
              size: 42,
              color: YeflixStyle.red,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "home.empty-title".i18n,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            "home.empty-subtitle".i18n,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: YeflixStyle.textMuted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Get.find<MainController>().changeTab(2),
            icon: const Icon(Icons.extension_rounded, size: 18),
            label: Text("home.explore".i18n),
            style: FilledButton.styleFrom(
              backgroundColor: YeflixStyle.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Obx(
      () {
        final favBangumi = c.favorites[ExtensionType.bangumi] ?? const [];
        final favManga = c.favorites[ExtensionType.manga] ?? const [];
        final hasRecent = c.resents.isNotEmpty;
        final hasFav = favBangumi.isNotEmpty || favManga.isNotEmpty;

        return RefreshIndicator(
          onRefresh: () async {
            await c.onRefresh();
          },
          edgeOffset: 8,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              _header(context),
              const SizedBox(height: 18),
              if (hasRecent) ...[
                HomeRecent(data: c.resents),
                const SizedBox(height: 18),
              ],
              const HomeCatalog(),
              if (favBangumi.isNotEmpty) ...[
                HomeFavorites(type: ExtensionType.bangumi, data: favBangumi),
                const SizedBox(height: 8),
              ],
              if (favManga.isNotEmpty) ...[
                HomeFavorites(type: ExtensionType.manga, data: favManga),
                const SizedBox(height: 8),
              ],
              if (!hasRecent &&
                  !hasFav &&
                  c.animes.isEmpty &&
                  c.movies.isEmpty &&
                  c.series.isEmpty)
                _emptyState(),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          body: _buildContent(),
        ),
      ),
      desktopBuilder: (context) => _buildContent(),
    );
  }
}
