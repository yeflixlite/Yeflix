import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rojo exacto del wordmark (`assets/icon/yeflix_logo.png`).
const Color _brandRed = Color(0xFFE50914);

/// Pantalla de carga de Yeflix.
///
/// Fondo negro, wordmark rojo, arco parcial rojo girando y el texto gris
/// "Cargando video...". Se adapta a teléfonos, tablets y escritorio usando el
/// lado corto disponible.
class YeflixLoader extends StatefulWidget {
  const YeflixLoader({
    super.key,
    this.message = 'Cargando video...',
    this.opaque = true,
    this.logoHeight,
  });

  final String message;

  /// `true` para la carga inicial (fondo negro completo). `false` para una
  /// pausa de buffering durante la reproducción (fondo semitransparente).
  final bool opaque;
  final double? logoHeight;

  @override
  State<YeflixLoader> createState() => _YeflixLoaderState();
}

class _YeflixLoaderState extends State<YeflixLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.message,
      liveRegion: true,
      child: ColoredBox(
        color: widget.opaque ? Colors.black : Colors.black.withOpacity(0.62),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortest = constraints.biggest.shortestSide;
            final isTablet = shortest >= 600;
            final logoHeight = widget.logoHeight ??
                (isTablet ? 68.0 : (shortest < 420 ? 46.0 : 58.0));
            final spinnerSize = isTablet ? 56.0 : 46.0;

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/yeflix_logo.png',
                    height: logoHeight,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => Text(
                      'YEFLIX',
                      style: TextStyle(
                        color: _brandRed,
                        fontSize: logoHeight * 0.55,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  SizedBox(height: isTablet ? 36 : 28),
                  SizedBox(
                    width: spinnerSize,
                    height: spinnerSize,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => CustomPaint(
                        painter: _ArcSpinnerPainter(
                          progress: _controller.value,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isTablet ? 22 : 18),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF8C8C95),
                      fontSize: isTablet ? 15 : 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ArcSpinnerPainter extends CustomPainter {
  _ArcSpinnerPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.095;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 1);

    final rotation = progress * math.pi * 2 - math.pi / 2;
    const sweep = math.pi * 1.2;
    // El degradado se comprime al arco visible: si se dejara el círculo
    // completo, la cabeza del arco solo alcanzaría un rojo tenue.
    const arcFraction = sweep / (math.pi * 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..shader = SweepGradient(
        colors: [
          _brandRed.withOpacity(0.0),
          _brandRed.withOpacity(0.45),
          _brandRed,
        ],
        stops: const [0.0, arcFraction * 0.55, arcFraction],
        transform: GradientRotation(rotation),
      ).createShader(rect);
    canvas.drawArc(arcRect, rotation, sweep, false, paint);

    // Cabeza redondeada: el degradado termina aquí en rojo pleno.
    final headAngle = rotation + sweep;
    final center = size.center(Offset.zero);
    final radius = arcRect.shortestSide / 2;
    final head = Offset(
      center.dx + radius * math.cos(headAngle),
      center.dy + radius * math.sin(headAngle),
    );
    canvas.drawCircle(
      head,
      stroke / 2,
      Paint()..color = _brandRed,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcSpinnerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
