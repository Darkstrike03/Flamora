import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/neu.dart';
import 'neu_button.dart';
import '../../features/library/library_provider.dart';
import '../../features/player/player_service.dart';

/// Floating mini player. Body tap returns home; the trailing button
/// toggles play/pause without leaving the current screen.
///
/// Reads live state from the player providers. Portrait renders a
/// full-width stadium bar (sits above the nav bar); wide renders a
/// compact pill (sits left of the nav ball).
class MiniPlayer extends ConsumerWidget {
  final VoidCallback onBodyTap;
  final bool wide;

  const MiniPlayer({
    super.key,
    required this.onBodyTap,
    this.wide = false,
  });

  Future<void> _toggle(BuildContext context, WidgetRef ref) {
    final songs = ref.read(librarySongsProvider).value ?? const [];
    final current = ref.read(playerCurrentProvider).value;
    final playing =
        ref.read(playerStateProvider).value?.playing ?? false;
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
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.watch(playerCurrentProvider).value;
    final position =
        ref.watch(playerPositionProvider).value ?? Duration.zero;
    final playing =
        ref.watch(playerStateProvider).value?.playing ?? false;
    final totalMs = (current?.duration ?? Duration.zero).inMilliseconds;
    final progress = totalMs <= 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onBodyTap,
      child: Container(
        width: wide ? 250 : null,
        padding: const EdgeInsets.all(8),
        decoration: neuDecoration(context, radius: 24),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/branding/appicon.png',
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.music_note_rounded,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current?.title ?? 'Flamora Preview Mix',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor:
                          scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            NeuButton(
              icon: playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 48,
              highlighted: true,
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: () => _toggle(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
