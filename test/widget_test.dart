import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flamora/core/widgets/floating_nav_bar.dart';
import 'package:flamora/main.dart';

Future<void> _setSurface(
    WidgetTester tester, double width, double height) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('Wide layout uses nav ball (expand/select/collapse)',
      (WidgetTester tester) async {
    await _setSurface(tester, 1000, 800);
    await tester.pumpWidget(const ProviderScope(child: FlamoraApp()));
    await tester.pumpAndSettle();

    expect(find.text('Flamora'), findsWidgets);
    expect(find.byType(NavigationBar), findsNothing);

    // Collapsed: single ball showing current tab icon.
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.library_music), findsNothing);

    // Expand.
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);

    // Select Library -> navigates + collapses.
    await tester.tap(find.byTooltip('Library'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(find.byIcon(Icons.library_music), findsOneWidget);
    expect(find.text('Songs · Albums · Artists land here in Phase 3.'),
        findsOneWidget);
  });

  testWidgets('Narrow layout uses floating bar directly',
      (WidgetTester tester) async {
    await _setSurface(tester, 390, 844);
    await tester.pumpWidget(const ProviderScope(child: FlamoraApp()));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(find.byTooltip('Open menu'), findsNothing);

    // Portrait Home fits one frame: header + player + controls, no scroll.
    expect(find.byType(Scrollable), findsNothing);

    // Selected tab shows the filled icon inside the flame circle.
    expect(find.byIcon(Icons.home), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('M3 SearchBar + filters land here in Phase 4.'),
        findsOneWidget);
  });

  testWidgets('Tiny portrait falls back to scroll instead of overflowing',
      (WidgetTester tester) async {
    await _setSurface(tester, 360, 540);
    await tester.pumpWidget(const ProviderScope(child: FlamoraApp()));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
  });

  testWidgets('Portrait queue drawer opens, rail jumps, scrim closes',
      (WidgetTester tester) async {
    await _setSurface(tester, 390, 844);
    await tester.pumpWidget(const ProviderScope(child: FlamoraApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Up Next'), findsOneWidget);
    expect(find.text('Amber Skies'), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-M')), findsOneWidget);

    // Tap M on the rail -> list jumps to the M section.
    await tester.tap(find.byKey(const ValueKey('rail-M')));
    await tester.pumpAndSettle();

    expect(find.text('Midnight Sun'), findsOneWidget);

    // Tap the scrim (left of the drawer) -> closes.
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();

    expect(find.text('Up Next'), findsNothing);
  });

  testWidgets('Wide queue button shows portrait-only notice',
      (WidgetTester tester) async {
    await _setSurface(tester, 1000, 800);
    await tester.pumpWidget(const ProviderScope(child: FlamoraApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Up Next'), findsNothing);
    expect(
      find.text('Queue panel is portrait-only for now.'),
      findsOneWidget,
    );
  });
}
