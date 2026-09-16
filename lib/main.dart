import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_media_session/flutter_media_session.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'dart:io' show Platform;

import 'core/theme/flamora_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/widgets/neu_button.dart';
import 'core/widgets/neu_card.dart';
import 'core/widgets/floating_nav_ball.dart';
import 'core/widgets/floating_nav_bar.dart';
import 'core/widgets/screen_header.dart';
import 'core/widgets/mini_player.dart';
import 'core/widgets/online_toggle.dart';
import 'features/library/library_provider.dart';
import 'features/library/add_to_playlist_sheet.dart';
import 'features/library/library_screen.dart';
import 'features/player/player_service.dart';
import 'features/player/media_session_bridge.dart';
import 'features/player/playback_state_repository.dart';
import 'features/library/song.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/player/player_panel.dart';
import 'features/queue/queue_drawer.dart';
import 'features/queue/queue_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // Opened before runApp so repositories (folders, playlists next)
  // can read synchronously in their providers.
  await Hive.openBox('flamora');
  // just_audio has no Windows implementation — plug mpv in underneath it
  // so the existing FlamoraAudioHandler works unchanged on desktop.
  // Android/iOS/macOS are untouched (native just_audio).
  if (Platform.isWindows) {
    JustAudioMediaKit.title = 'Flamora';
    JustAudioMediaKit.ensureInitialized();
    // SMTC identity so the volume flyout shows "Flamora" instead of
    // "Unknown Application" (unpackaged dev builds).
    try {
      await FlutterMediaSession().setWindowsAppUserModelId(
        'com.flamora.flamora',
        displayName: 'Flamora',
      );
    } catch (_) {}
  }
  runApp(const ProviderScope(child: FlamoraApp()));
}

class FlamoraApp extends ConsumerWidget {
  const FlamoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Flamora',
      debugShowCheckedModeBanner: false,
      theme: FlamoraTheme.light(),
      darkTheme: FlamoraTheme.dark(),
      themeMode: mode,
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int index = 0;
  bool navOpen = false;
  bool queueOpen = false;

  void _onQueueTap() {
    // Drawer serves narrow (<600) + medium (600-800).
    // Wide (>=800) shows the queue inline, so there is nothing to open.
    if (MediaQuery.sizeOf(context).width < 800) {
      setState(() => queueOpen = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always mounted: keeps player gain + EQ synced with track + prefs,
    // persists the session, restores it paused on next launch, and feeds
    // the Windows system media controls.
    ref.watch(volumeApplierProvider);
    ref.watch(equalizerApplierProvider);
    ref.watch(playbackSaverProvider);
    ref.watch(playbackRestoreProvider);
    ref.watch(mediaSessionBridgeProvider);
    final pages = [
      Column(
        children: [
          ScreenHeader.home(actions: const [OnlineToggleButton()]),
          Expanded(
            child: _HomePreview(
              onQueueTap: _onQueueTap,
            ),
          ),
        ],
      ),
      const LibraryScreen(),
      const SearchScreen(),
      const SettingsScreen(),
    ];

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 600;
    final isWide = width >= 800;
    final drawerOpen = !isWide && queueOpen;
    // Mini player floats on every screen except home (index 0);
    // body tap returns home.
    final showMini = index != 0;

    // Full-screen stack so the queue drawer merges over content too —
    // nothing sticks out above it when open.
    return Stack(
      children: [
        Scaffold(
          extendBody: true,
          // No global AppBar: each screen owns its header (Home branding,
          // Library / Search / Settings titles).
          // Adaptive overlay: narrow (<600dp) shows the floating bar,
          // wide shows the bottom-right ball. Content stays full-bleed behind.
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Never leave popups stuck open when crossing breakpoints.
              // nav ball lives on medium+wide, drawer lives on narrow+medium.
              if ((isNarrow && navOpen) || (isWide && queueOpen)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    navOpen = false;
                    queueOpen = false;
                  });
                });
              }
              return Stack(
                children: [
                  Positioned.fill(
                    child: SafeArea(
                      top: true,
                      bottom: false,
                      // Reserve room for the mini player above the
                      // portrait nav bar so list ends stay reachable.
                      child: Padding(
                        padding: EdgeInsets.only(
                            bottom: showMini && isNarrow ? 80 : 0),
                        child: pages[index],
                      ),
                    ),
                  ),
                  if (!isNarrow && navOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => navOpen = false),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  if (isNarrow)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20 + safeBottom,
                      child: FloatingNavBar(
                        selectedIndex: index,
                        onSelected: (i) => setState(() => index = i),
                      ),
                    )
                  else
                    Positioned(
                      right: 20,
                      bottom: 20 + safeBottom,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (showMini)
                            MiniPlayer(
                              onBodyTap: () =>
                                  setState(() => index = 0),
                              wide: true,
                            ),
                          if (showMini) const SizedBox(width: 12),
                          FloatingNavBall(
                            selectedIndex: index,
                            expanded: navOpen,
                            onToggle: () =>
                                setState(() => navOpen = !navOpen),
                            onSelected: (i) => setState(() {
                              index = i;
                              navOpen = false;
                            }),
                          ),
                        ],
                      ),
                    ),
                  if (showMini && isNarrow)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 104 + safeBottom,
                      child: MiniPlayer(
                        onBodyTap: () => setState(() => index = 0),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        // Drawer for narrow + medium. Wide embeds the queue inline.
        if (drawerOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => queueOpen = false),
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
              ),
            ),
          ),
        if (drawerOpen)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: QueueDrawer(
              onClose: () => setState(() => queueOpen = false),
            ),
          ),
      ],
    );
  }
}

class _HomePreview extends ConsumerStatefulWidget {
  final VoidCallback onQueueTap;

  const _HomePreview({
    required this.onQueueTap,
  });

  @override
  ConsumerState<_HomePreview> createState() => _HomePreviewState();
}

class _HomePreviewState extends ConsumerState<_HomePreview> {
  /// Shared play/pause behavior: toggles when something is loaded,
  /// starts the library from the top when idle, prompts for folders
  /// when the library is empty.
  Future<void> _toggle() {
    final songs = ref.read(librarySongsProvider).value ?? const [];
    final current = ref.read(playerCurrentProvider).value;
    final playing = ref.read(playerStateProvider).value?.playing ?? false;
    final service = ref.read(playerServiceProvider);
    if (playing) return service.pause();
    if (current != null) return service.play();
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Add a music folder in Settings first.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return Future.value();
    }
    return service.playSongs(songs);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Wide: two-pane player + inline queue. Medium: centered single column.
    // Narrow (<600) portrait path below is intentionally untouched.
    if (width >= 800) return _wideTwoPane();
    if (width >= 600) return _mediumCentered();
    // Portrait phones: fit header + player + controls + bar in one frame.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Very short screens: fall back to scroll rather than overflow.
        if (constraints.maxHeight < 560) {
          return _scrollList(artHeight: 150, compact: true);
        }
        final artHeight =
            (constraints.maxHeight - 460).clamp(120.0, 170.0).toDouble();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(
            children: [
              _playerCard(artHeight, tight: true),
              const SizedBox(height: 12),
              _controlsCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _mediumCentered() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          // Bottom inset lets the last card scroll out from under the nav.
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          children: [
            PlayerPanel(
              onQueueTap: widget.onQueueTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _wideTwoPane() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Bounded pane height so both the player column and the inline
        // queue (with its A–Z rail) scroll independently. The 110px bottom
        // reserve keeps content clear of the floating nav ball.
        final paneHeight = (constraints.maxHeight - 130).clamp(320.0, 900.0);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 432,
                    height: paneHeight.toDouble(),
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: PlayerPanel(
                        onQueueTap: widget.onQueueTap,
                        compact: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: SizedBox(
                      height: paneHeight.toDouble(),
                      child: NeuCard(
                        padding: EdgeInsets.zero,
                        child: const QueuePanel(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _scrollList({required double artHeight, bool compact = false}) {
    return ListView(
      // Bottom inset lets the last cards scroll out from under the nav.
      padding: EdgeInsets.fromLTRB(
          compact ? 16 : 20, compact ? 12 : 20, compact ? 16 : 20, 110),
      children: [
        _playerCard(artHeight, tight: compact),
        SizedBox(height: compact ? 12 : 16),
        _controlsCard(),
      ],
    );
  }

  Widget _playerCard(double artHeight, {bool tight = false}) {
    final current = ref.watch(playerCurrentProvider).value;
    final position =
        ref.watch(playerPositionProvider).value ?? Duration.zero;
    final playing =
        ref.watch(playerStateProvider).value?.playing ?? false;
    final duration = current?.duration ?? Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final valueMs = maxMs <= 0
        ? 0.0
        : position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return NeuCard(
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/branding/appicon.png',
              height: artHeight,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => SizedBox(
                height: artHeight,
                child: const Icon(Icons.music_note, size: 64),
              ),
            ),
          ),
          SizedBox(height: tight ? 12 : 16),
          Text(
            current?.title ?? 'Flamora Preview Mix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Slider(
            value: valueMs,
            max: maxMs <= 0 ? 1 : maxMs,
            onChanged: maxMs <= 0
                ? null
                : (v) => ref
                    .read(playerServiceProvider)
                    .seekTo(Duration(milliseconds: v.round())),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatTrackDuration(position)),
                Text(formatTrackDuration(
                    duration == Duration.zero ? null : duration)),
              ],
            ),
          ),
          SizedBox(height: tight ? 6 : 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              NeuButton(
                icon: Icons.skip_previous_rounded,
                onPressed: () =>
                    ref.read(playerServiceProvider).skipToPrevious(),
                tooltip: 'Previous',
              ),
              NeuButton(
                icon: playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                highlighted: true,
                size: 76,
                onPressed: _toggle,
                tooltip: 'Play / pause',
              ),
              NeuButton(
                icon: Icons.skip_next_rounded,
                onPressed: () =>
                    ref.read(playerServiceProvider).skipToNext(),
                tooltip: 'Next',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlsCard() {
    final repeatMode =
        ref.watch(playerStateProvider).value?.repeatMode ??
            AudioServiceRepeatMode.none;
    final shuffleOn =
        (ref.watch(playerStateProvider).value?.shuffleMode ??
                AudioServiceShuffleMode.none) ==
            AudioServiceShuffleMode.all;

    IconData repeatIcon;
    switch (repeatMode) {
      case AudioServiceRepeatMode.one:
        repeatIcon = Icons.repeat_one_rounded;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        repeatIcon = Icons.repeat_on_outlined;
      case AudioServiceRepeatMode.none:
        repeatIcon = Icons.repeat_rounded;
    }

    AudioServiceRepeatMode nextRepeat() {
      return switch (repeatMode) {
        AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group =>
          AudioServiceRepeatMode.one,
        AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
      };
    }

    return NeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          NeuButton(
            icon: shuffleOn
                ? Icons.shuffle_on_outlined
                : Icons.shuffle_rounded,
            size: 52,
            highlighted: shuffleOn,
            tooltip: 'Shuffle',
            onPressed: () => ref
                .read(playerServiceProvider)
                .setShuffle(!shuffleOn),
          ),
          NeuButton(
            icon: repeatIcon,
            size: 52,
            highlighted: repeatMode != AudioServiceRepeatMode.none,
            tooltip: 'Repeat',
            onPressed: () => ref
                .read(playerServiceProvider)
                .setRepeatMode(nextRepeat()),
          ),
          NeuButton(
            icon: Icons.queue_music_rounded,
            size: 52,
            tooltip: 'Queue',
            onPressed: widget.onQueueTap,
          ),
          NeuButton(
            icon: Icons.playlist_add_rounded,
            size: 52,
            tooltip: 'Add to playlist',
            onPressed: () => showAddCurrentToPlaylist(context, ref),
          ),
        ],
      ),
    );
  }
}
