import 'package:flutter/material.dart';
import '../theme/neu.dart';

/// Soft raised neumorphic surface. Use for art cards, panels, tiles.
class NeuCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double distance;
  final VoidCallback? onTap;

  const NeuCard({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.distance = 9,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: neuDecoration(context, radius: radius, color: color)
          .copyWith(
        boxShadow: neuShadows(context, distance: distance),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: content,
    );
  }
}
