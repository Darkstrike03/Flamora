import 'package:flutter/material.dart';

import '../theme/flamora_colors.dart';
import '../theme/neu.dart';

/// Icon-only floating stadium bar for narrow (portrait phone) layouts.
///
/// Custom row (not M3 [NavigationBar]) so the selected indicator is a
/// true circle: solid flame gradient with a white icon. Unselected icons
/// stay plain.
class FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const FloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.library_music_outlined, Icons.library_music, 'Library'),
    (Icons.search_outlined, Icons.search, 'Search'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: neuDecoration(context, radius: 40),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: Center(
                child: Tooltip(
                  message: _items[i].$3,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onSelected(i),
                    child: AnimatedScale(
                      scale: selectedIndex == i ? 1 : 0.92,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        width: 52,
                        height: 52,
                        decoration: selectedIndex == i
                            ? BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    FlamoraColors.flame,
                                    FlamoraColors.flameDeep,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: neuShadows(
                                  context,
                                  distance: 5,
                                  blur: 14,
                                ),
                              )
                            : const BoxDecoration(shape: BoxShape.circle),
                        child: Icon(
                          selectedIndex == i ? _items[i].$2 : _items[i].$1,
                          color: selectedIndex == i
                              ? Colors.white
                              : scheme.onSurfaceVariant,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
