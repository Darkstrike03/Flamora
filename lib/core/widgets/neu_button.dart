import 'package:flutter/material.dart';
import '../theme/neu.dart';
import '../theme/flamora_colors.dart';

/// Circular neumorphic play / icon button with flame gradient option.
class NeuButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final bool highlighted;
  final String? tooltip;

  const NeuButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 64,
    this.highlighted = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? FlamoraColors.maroon : FlamoraColors.creamCard;
    final inner = Container(
      width: size,
      height: size,
      decoration: highlighted
          ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [FlamoraColors.flame, FlamoraColors.flameDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: neuShadows(context, distance: 7, blur: 18),
            )
          : BoxDecoration(
              color: baseColor,
              shape: BoxShape.circle,
              boxShadow: neuShadows(context, distance: 7, blur: 18),
            ),
      child: Icon(
        icon,
        color: highlighted
            ? Colors.white
            : Theme.of(context).colorScheme.primary,
        size: size * 0.42,
      ),
    );

    final btn = InkWell(
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: inner,
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
