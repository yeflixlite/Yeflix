import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jiruhub/controllers/main_controller.dart';
import 'package:jiruhub/controllers/search_controller.dart';
import 'package:jiruhub/data/providers/anilist_provider.dart';
import 'package:jiruhub/data/services/extension_service.dart';
import 'package:jiruhub/models/extension.dart';
import 'package:jiruhub/utils/extension.dart';
import 'package:jiruhub/utils/i18n.dart';
import 'package:jiruhub/utils/jiruhub_storage.dart';
import 'package:jiruhub/utils/yeflix_style.dart';
import 'package:jiruhub/views/pages/detail_page.dart';
import 'package:jiruhub/views/widgets/cache_network_image.dart';

/// "Tendencias" carousel fed by the public AniList trending list.
class HomeTrending extends StatefulWidget {
  const HomeTrending({super.key});

  @override
  State<HomeTrending> createState() => _HomeTrendingState();
}

class _HomeTrendingState extends State<HomeTrending> {
  List<dynamic> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await AniListProvider.getTrending(type: AnilistType.anime);
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _open(dynamic media) async {
    final title = (media["title"]?["userPreferred"] ??
            media["title"]?["romaji"] ??
            "")
        .toString();
    if (title.isEmpty) return;

    final runtimes = ExtensionUtils.runtimes.values
        .where((e) => e.extension.type == ExtensionType.bangumi)
        .where((e) =>
            !e.extension.nsfw ||
            JiruHubStorage.getSetting(SettingKey.enableNSFW))
        .toList();

    if (runtimes.isEmpty) {
      _search(title);
      return;
    }

    Get.dialog(
      const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      barrierDismissible: false,
    );

    ExtensionService? bestRuntime;
    ExtensionListItem? bestItem;
    var bestScore = 0;

    final batches = await Future.wait(runtimes.map((rt) async {
      try {
        final list = await rt
            .search(title, 1)
            .timeout(const Duration(seconds: 15));
        return MapEntry(rt, list);
      } catch (_) {
        return MapEntry(rt, <ExtensionListItem>[]);
      }
    }));

    for (final batch in batches) {
      for (final item in batch.value) {
        final score = _matchScore(title, item.title);
        if (score > bestScore) {
          bestScore = score;
          bestRuntime = batch.key;
          bestItem = item;
        }
      }
    }

    if (Get.isDialogOpen == true) Get.back();

    if (bestRuntime != null && bestItem != null && bestScore > 0) {
      final item = bestItem;
      Get.to(() => DetailPage(
            url: item.url,
            package: bestRuntime!.extension.package,
            tag: item.url,
          ));
      return;
    }

    _search(title);
  }

  void _search(String title) {
    Get.put(SearchPageController()).search.value = title;
    Get.find<MainController>().changeTab(1);
  }

  int _matchScore(String query, String candidate) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    final q = norm(query);
    final c = norm(candidate);
    if (q.isEmpty || c.isEmpty) return 0;
    if (q == c) return 100;
    if (c.startsWith(q)) return 80;
    if (c.contains(q)) return 60;
    if (q.contains(c)) return 40;

    final qs = q.split(' ').where((e) => e.length > 2).toSet();
    final cs = c.split(' ').where((e) => e.length > 2).toSet();
    final hit = qs.intersection(cs).length;
    return hit > 0 ? 20 + hit : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 232,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        YeflixSectionHeader(title: "home.trending".i18n),
        SizedBox(
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final media = _items[index];
              return _TrendingCard(
                title: (media["title"]?["userPreferred"] ??
                        media["title"]?["romaji"] ??
                        "")
                    .toString(),
                cover: media["coverImage"]?["large"]?.toString(),
                score: media["averageScore"],
                onTap: () => _open(media),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrendingCard extends StatelessWidget {
  const _TrendingCard({
    required this.title,
    required this.onTap,
    this.cover,
    this.score,
  });

  final String title;
  final String? cover;
  final dynamic score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(YeflixStyle.radiusSm),
      child: SizedBox(
        width: 134,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(YeflixStyle.radiusSm),
              child: Stack(
                children: [
                  SizedBox(
                    width: 134,
                    height: 178,
                    child: cover != null
                        ? CacheNetWorkImagePic(
                            cover!,
                            width: 134,
                            height: 178,
                          )
                        : Container(color: YeflixStyle.surfaceAlt),
                  ),
                  if (score != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: YeflixStyle.red,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              "$score",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
