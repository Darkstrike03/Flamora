import 'package:flutter/material.dart';

import 'neu_button.dart';

/// Expandable bottom-right nav ball for wide (landscape/tablet/desktop)
/// layouts.
///
/// Collapsed: single 64px ball showing the current tab icon.
/// Expanded: vertical popup above the ball with all destinations;
/// tapping a destination navigates + collapses, tapping outside
/// (barrier in [AppShell]) collapses.
class FloatingNavBall extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool expanded;
  final VoidCallback onToggle;

  const FloatingNavBall({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.expanded,
    required this.onToggle,
  });

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.library_music_outlined, Icons.library_music, 'Library'),
    (Icons.search_outlined, Icons.search, 'Search'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _items[selectedIndex];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedScale(
          scale: expanded ? 1 : 0,
          alignment: Alignment.bottomRight,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: expanded ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Visibility(
              visible: expanded,
              maintainState: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                          bottom: i == _items.length - 1 ? 12 : 10),
                      child: NeuButton(
                        icon: selectedIndex == i
                            ? _items[i].$2
                            : _items[i].$1,
                        size: 56,
                        highlighted: selectedIndex == i,
                        tooltip: _items[i].$3,
                        onPressed: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        NeuButton(
          icon: expanded ? Icons.close_rounded : current.$2,
          size: 64,
          highlighted: true,
          tooltip: expanded ? 'Close menu' : 'Open menu',
          onPressed: onToggle,
        ),
      ],
    );
  }
}
