import 'package:flutter/material.dart';

/// Per-screen header. Home uses branding (app icon + Flamora),
/// other screens use their own title like Library / Search / Settings.
class ScreenHeader extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const ScreenHeader({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.actions,
  });

  /// Home branding: app icon + Flamora name.
  factory ScreenHeader.home({List<Widget>? actions}) {
    return ScreenHeader(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/branding/appicon.png',
          width: 32,
          height: 32,
          errorBuilder: (_, _, _) => const Icon(Icons.music_note_outlined),
        ),
      ),
      title: 'Flamora',
      actions: actions,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
