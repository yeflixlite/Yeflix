import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jiruhub/controllers/home_controller.dart';
import 'package:jiruhub/utils/yeflix_style.dart';
import 'package:jiruhub/views/pages/detail_page.dart';
import 'package:jiruhub/views/widgets/cache_network_image.dart';

class HomeHeroBanner extends StatefulWidget {
  const HomeHeroBanner({super.key});

  @override
  State<HomeHeroBanner> createState() => _HomeHeroBannerState();
}

class _HomeHeroBannerState extends State<HomeHeroBanner> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      final c = Get.find<HomePageController>();
      final items = _getFeaturedItems(c);
      if (items.isEmpty || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % items.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  List<CatalogItem> _getFeaturedItems(HomePageController c) {
    final list = <CatalogItem>[];
    const maxEach = 3;
    for (var i = 0; i < maxEach; i++) {
      if (c.movies.length > i) list.add(c.movies[i]);
      if (c.series.length > i) list.add(c.series[i]);
      if (c.animes.length > i) list.add(c.animes[i]);
    }
    return list.take(7).toList();
  }

  String _getItemCategory(CatalogItem item) {
    final u = item.item.url.toLowerCase();
    if (u.contains('serie') || u.contains('serieinfo')) return 'Serie';
    if (u.contains('pelicula') || u.contains('movieinfo') || u.contains('movie')) {
      return 'Película';
    }
    return 'Anime';
  }

  void _openDetail(CatalogItem entry) {
    Get.to(
      DetailPage(
        url: entry.item.url,
        package: entry.package,
        tag: 'hero_${entry.item.url}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<HomePageController>();

    return Obx(() {
      final items = _getFeaturedItems(c);
      if (items.isEmpty) {
        if (c.catalogLoading.value) {
          return _loadingPlaceholder(context);
        }
        return const SizedBox.shrink();
      }

      final height = MediaQuery.of(context).size.height * 0.54;
      final topPadding = MediaQuery.of(context).padding.top;

      return SizedBox(
        height: height,
        child: Stack(
          children: [
            // 1. Carrusel de imágenes destacadas
            PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (idx) {
                setState(() => _currentPage = idx);
              },
              itemBuilder: (context, index) {
                final entry = items[index];
                return _slideItem(entry);
              },
            ),

            // 2. Gradientes cinematográficos (fade superior y fade inferior al fondo negro)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.85),
                        Colors.black.withOpacity(0.15),
                        Colors.transparent,
                        Colors.black.withOpacity(0.55),
                        YeflixStyle.bg,
                      ],
                      stops: const [0.0, 0.18, 0.40, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Barra Superior: Logo YEFLIX completo
            Positioned(
              top: topPadding + 10,
              left: 20,
              child: Image.asset(
                'assets/icon/yeflix_logo.png',
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Text(
                    'YEFLIX',
                    style: TextStyle(
                      color: YeflixStyle.red,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  );
                },
              ),
            ),

            // 4. Botón flecha derecha para avanzar de recomendación
            if (items.length > 1)
              Positioned(
                right: 12,
                top: height * 0.45,
                child: InkWell(
                  onTap: () {
                    final next = (_currentPage + 1) % items.length;
                    _pageController.animateToPage(
                      next,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                      size: 26,
                    ),
                  ),
                ),
              ),

            // 5. Contenido del elemento destacado (Pill, Título, Acciones y Puntos)
            Positioned(
              left: 20,
              right: 20,
              bottom: 12,
              child: _heroContent(items[_currentPage.clamp(0, items.length - 1)], items.length),
            ),
          ],
        ),
      );
    });
  }

  Widget _slideItem(CatalogItem entry) {
    return GestureDetector(
      onTap: () => _openDetail(entry),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Imagen de portada
          if (entry.item.cover != null && entry.item.cover!.isNotEmpty)
            CacheNetWorkImagePic(
              entry.item.cover!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              headers: entry.item.headers,
            )
          else
            Container(color: YeflixStyle.surface),

          // Ícono central de play sutil
          Center(
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.48),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: YeflixStyle.red.withOpacity(0.25),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroContent(CatalogItem entry, int totalSlides) {
    final cat = _getItemCategory(entry);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pill de Categoría
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: YeflixStyle.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                cat.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Título Principal
        Text(
          entry.item.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
            height: 1.15,
            shadows: [
              Shadow(
                color: Color(0xCC000000),
                offset: Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),

        // Subtítulo / Tags
        Text(
          '$cat • Estreno HD',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),

        // Botones de acción: [ ▶ Reproducir ] y [ ℹ Más Info ]
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Botón Reproducir (Rojo Yeflix)
            ElevatedButton.icon(
              onPressed: () => _openDetail(entry),
              icon: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
              label: const Text(
                'Reproducir',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: YeflixStyle.red,
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: YeflixStyle.red.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Botón Más Info (Translucido oscuro)
            ElevatedButton.icon(
              onPressed: () => _openDetail(entry),
              icon: const Icon(Icons.info_outline_rounded, size: 19, color: Colors.white),
              label: const Text(
                'Más Info',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.16),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Indicador de Puntos (Dots)
        if (totalSlides > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalSlides, (index) {
              final isCurrent = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isCurrent ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isCurrent ? YeflixStyle.red : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _loadingPlaceholder(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final height = MediaQuery.of(context).size.height * 0.52;

    return Container(
      height: height,
      color: YeflixStyle.surface,
      child: Stack(
        children: [
          Positioned(
            top: topPadding + 10,
            left: 20,
            child: Image.asset(
              'assets/icon/yeflix_logo.png',
              height: 32,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text(
                'YEFLIX',
                style: TextStyle(color: YeflixStyle.red, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            ),
          ),
          const Center(
            child: CircularProgressIndicator(
              color: YeflixStyle.red,
              strokeWidth: 2.5,
            ),
          ),
        ],
      ),
    );
  }
}
