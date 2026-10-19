import 'package:flutter/material.dart';

/// Yeflix design system: brand colours, gradients and small brand widgets.
class YeflixStyle {
  YeflixStyle._();

  static const Color red = Color(0xFFE53935);
  static const Color redDark = Color(0xFFC62828);
  static const Color redDeep = Color(0xFF7E1512);

  static const Color bg = Color(0xFF0E0E11);
  static const Color surface = Color(0xFF17171B);
  static const Color surfaceAlt = Color(0xFF202027);
  static const Color border = Color(0xFF2C2C34);

  static const Color textPrimary = Color(0xFFF2F2F5);
  static const Color textMuted = Color(0xFF9A9AA3);

  static const double radius = 16;
  static const double radiusSm = 12;

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [redDeep, Color(0xFF141418)],
  );

  static const LinearGradient markGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [red, redDark],
  );

  static const LinearGradient cardScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xE6000000)],
  );
}

/// The Yeflix "Y" app mark.
class YeflixMark extends StatelessWidget {
  const YeflixMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: YeflixStyle.markGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: YeflixStyle.red.withOpacity(0.35),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'Y',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.6,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

/// Section title with a red accent bar and an optional "show all" action.
class YeflixSectionHeader extends StatelessWidget {
  const YeflixSectionHeader({
    super.key,
    required this.title,
    this.onMore,
    this.moreLabel,
  });

  final String title;
  final VoidCallback? onMore;
  final String? moreLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: YeflixStyle.red,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(
                foregroundColor: YeflixStyle.red,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                moreLabel ?? 'Ver todo',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
