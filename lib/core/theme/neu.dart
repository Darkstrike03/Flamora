import 'package:flutter/material.dart';
import 'flamora_colors.dart';

/// Dual soft shadows that create the neumorphic look.
/// [isDark] switches the shadow palette, [distance] controls depth,
/// [radius] matches the card shape.
List<BoxShadow> neuShadows(BuildContext context,
    {double distance = 9, double blur = 22}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return [
      BoxShadow(
        color: const Color(0xFF241010).withValues(alpha: 0.9),
        offset: Offset(distance, distance),
        blurRadius: blur,
      ),
      BoxShadow(
        color: const Color(0xFF8A4A4A).withValues(alpha: 0.35),
        offset: Offset(-distance, -distance),
        blurRadius: blur,
      ),
    ];
  }
  return [
    BoxShadow(
      color: FlamoraColors.creamShadowDark.withValues(alpha: 0.85),
      offset: Offset(distance, distance),
      blurRadius: blur,
    ),
    const BoxShadow(
      color: Colors.white,
      offset: Offset(-9, -9),
      blurRadius: 22,
    ),
  ];
}

BoxDecoration neuDecoration(BuildContext context,
    {double radius = 28, Color? color}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: color ??
        (isDark ? FlamoraColors.maroon : FlamoraColors.creamCard),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: neuShadows(context),
  );
}

/// Inset (pressed) look used for sliders / toggles / active controls.
BoxDecoration neuInsetDecoration(BuildContext context, {double radius = 28}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: isDark ? FlamoraColors.maroonDeep : const Color(0xFFE2D5C4),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: isDark
        ? [
            const BoxShadow(
              color: Color(0xFF241010),
              offset: Offset(4, 4),
              blurRadius: 10,
            ),
            BoxShadow(
              color: const Color(0xFF8A4A4A).withValues(alpha: 0.3),
              offset: const Offset(-4, -4),
              blurRadius: 10,
            ),
          ]
        : [
            BoxShadow(
              color: FlamoraColors.creamShadowDark.withValues(alpha: 0.9),
              offset: const Offset(4, 4),
              blurRadius: 10,
            ),
            const BoxShadow(
              color: Colors.white,
              offset: Offset(-4, -4),
              blurRadius: 10,
            ),
          ],
  );
}
