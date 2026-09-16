import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/neu_button.dart';
import '../../core/widgets/neu_card.dart';
import '../library/add_to_playlist_sheet.dart';
import '../library/library_provider.dart';
import '../library/song.dart';
import 'player_service.dart';

/// Player + controls column for medium / wide layouts.
///
/// Reads live state from [playerStateProvider]/[playerCurrentProvider]/
/// [playerPositionProvider]. Square 1:1 art capped at 340px (220px in
/// compact desktop mode). Portrait (`<600dp`) keeps its legacy banner
/// path in `AppShell` — this widget is only used for `>=600dp`.
class PlayerPanel extends ConsumerStatefulWidget {
  final VoidCallback onQueueTap;
  final bool compact;

  const PlayerPanel({
    super.key,
    required this.onQueueTap,
    this.compact = false,
  });

  @override
  ConsumerState<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends ConsumerState<PlayerPanel> {
  Future<void> _toggle(List<Song> songs, MediaItem? current, bool playing) {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _playerCard(),
        SizedBox(height: widget.compact ? 12 : 20),
        _controlsCard(),
      ],
    );
  }

  Widget _playerCard() {
    final compact = widget.compact;
    final songs = ref.watch(librarySongsProvider).value ?? const [];
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
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: compact ? 220 : 340),
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(compact ? 16 : 20),
                  child: Image.asset(
                    'assets/branding/appicon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.music_note, size: 64),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            current?.title ?? 'Flamora Preview Mix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: compact ? 16 : 18, fontWeight: FontWeight.w700),
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
          SizedBox(height: compact ? 6 : 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              NeuButton(
                icon: Icons.skip_previous_rounded,
                size: compact ? 56 : 64,
                onPressed: () =>
                    ref.read(playerServiceProvider).skipToPrevious(),
                tooltip: 'Previous',
              ),
              NeuButton(
                icon:
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                highlighted: true,
                size: compact ? 64 : 76,
                onPressed: () => _toggle(songs, current, playing),
                tooltip: 'Play / pause',
              ),
              NeuButton(
                icon: Icons.skip_next_rounded,
                size: compact ? 56 : 64,
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
    final compact = widget.compact;
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
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16, vertical: compact ? 10 : 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          NeuButton(
            icon: shuffleOn
                ? Icons.shuffle_on_outlined
                : Icons.shuffle_rounded,
            size: compact ? 44 : 52,
            highlighted: shuffleOn,
            tooltip: 'Shuffle',
            onPressed: () => ref
                .read(playerServiceProvider)
                .setShuffle(!shuffleOn),
          ),
          NeuButton(
            icon: repeatIcon,
            size: compact ? 44 : 52,
            highlighted: repeatMode != AudioServiceRepeatMode.none,
            tooltip: 'Repeat',
            onPressed: () => ref
                .read(playerServiceProvider)
                .setRepeatMode(nextRepeat()),
          ),
          NeuButton(
            icon: Icons.queue_music_rounded,
            size: compact ? 44 : 52,
            tooltip: 'Queue',
            onPressed: widget.onQueueTap,
          ),
          NeuButton(
            icon: Icons.playlist_add_rounded,
            size: compact ? 44 : 52,
            tooltip: 'Add to playlist',
            onPressed: () => showAddCurrentToPlaylist(context, ref),
          ),
        ],
      ),
    );
  }
}
