import 'package:flutter/material.dart';
import 'package:jiruhub/utils/yeflix_style.dart';
import 'package:jiruhub/views/pages/main_page.dart';

/// Pantalla de inicio animada al estilo Netflix.
/// Muestra el logo YEFLIX con animación de aparición y luego navega a la app.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Fase 1: logo aparece (fade + escala)
  late Animation<double> _fadeIn;
  late Animation<double> _scaleIn;

  // Fase 2: pausa y fundido a negro antes de navegar
  late Animation<double> _fadeOut;
  late Animation<double> _bgFade;

  @override
  void initState() {
    super.initState();

    // Duración total de la animación: 2.4 segundos
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    // Fade-in del logo: 0% → 40%
    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
    );

    // Scale del logo: 0% → 50% (crece de 0.85 a 1.0)
    _scaleIn = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.50, curve: Curves.easeOutCubic),
      ),
    );

    // Fade-out del logo: 70% → 95%
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.70, 0.95, curve: Curves.easeIn),
      ),
    );

    // Fondo negro aparece en la misma franja de salida
    _bgFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.70, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward().then((_) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            pageBuilder: (_, __, ___) => const AndroidMainPage(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Fondo base negro
              const ColoredBox(color: Colors.black),

              // Logo animado: fade + scale
              Center(
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: FadeTransition(
                    // Segunda capa de fade-out para salida suave
                    opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.70, 0.95, curve: Curves.easeIn),
                      ),
                    ),
                    child: ScaleTransition(
                      scale: _scaleIn,
                      child: Image.asset(
                        'assets/icon/yeflix_logo.png',
                        width: 220,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text(
                          'YEFLIX',
                          style: TextStyle(
                            color: YeflixStyle.red,
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Overlay negro que aparece al final para transición suave
              Opacity(
                opacity: _bgFade.value,
                child: const ColoredBox(color: Colors.black),
              ),
            ],
          );
        },
      ),
    );
  }
}
