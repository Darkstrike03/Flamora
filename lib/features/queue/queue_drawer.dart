import 'package:flutter/material.dart';

import '../../core/theme/flamora_colors.dart';
import 'queue_panel.dart';

/// Portrait / medium queue panel sliding in from the right.
///
/// Thin presentation wrapper around the shared [QueuePanel] — same width,
/// slide animation, scrim handling (in `AppShell`), and colors as before.
/// Wide layouts embed [QueuePanel] directly instead of using this drawer.
class QueueDrawer extends StatelessWidget {
  final VoidCallback onClose;

  const QueueDrawer({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.85;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, slide, child) {
        return Transform.translate(
          offset: Offset(slide * width, 0),
          child: Opacity(opacity: 1 - slide * 0.4, child: child),
        );
      },
      child: Material(
        type: MaterialType.transparency,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: isDark ? FlamoraColors.maroon : FlamoraColors.creamCard,
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(-12, 0),
              ),
            ],
          ),
          child: SafeArea(
            child: QueuePanel(onClose: onClose, showCloseButton: true),
          ),
        ),
      ),
    );
  }
}
