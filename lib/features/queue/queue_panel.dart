import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/flamora_colors.dart';
import '../../features/library/song.dart';
import '../player/player_service.dart';

/// Reusable queue content: live player queue in play order with
/// drag-to-reorder, swipe-to-remove, an Up Next strip, and auto-scroll
/// to the current track.
///
/// Used inline in the wide two-pane layout and wrapped with slide/scrim
/// by [QueueDrawer] in portrait / medium layouts. Tapping a row jumps
/// playback to that queue item. Reordering is a manual takeover: the
/// handler switches shuffle + repeat off and keeps the arranged order.
class QueuePanel extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final bool showCloseButton;

  const QueuePanel({super.key, this.onClose, this.showCloseButton = false});

  @override
  ConsumerState<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<QueuePanel> {
  late final ScrollController _controller;
  String? _lastScrolledId;

  /// Fixed row height so auto-scroll can target indices directly.
  static const _rowHeight = 64.0;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// ReorderableListView reports the post-removal position when moving
  /// down — adjust to the final index the handler expects.
  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final state = ref.read(playerStateProvider).value;
    final hadShuffle =
        (state?.shuffleMode ?? AudioServiceShuffleMode.none) !=
            AudioServiceShuffleMode.none;
    final hadRepeat = (state?.repeatMode ?? AudioServiceRepeatMode.none) !=
        AudioServiceRepeatMode.none;
    try {
      await ref.read(playerServiceProvider).moveQueueItem(oldIndex, newIndex);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not reorder queue.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    if (!mounted) return;
    if (hadShuffle || hadRepeat) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Custom order kept · Shuffle off · Repeat off'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Removes by id (looked up fresh — builder indices can go stale).
  Future<void> _remove(String id) async {
    final items = ref.read(playerQueueProvider).value ?? const <MediaItem>[];
    final index = items.indexWhere((m) => m.id == id);
    if (index < 0) return;
    try {
      await ref.read(playerServiceProvider).removeQueueItemAt(index);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not remove song.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Scrolls the current track into view on open and on track change.
  void _maybeScrollTo(String? currentId, List<MediaItem> items) {
    if (currentId == null || currentId == _lastScrolledId) return;
    _lastScrolledId = currentId;
    final index = items.indexWhere((m) => m.id == currentId);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateTo(
        (index * _rowHeight).clamp(0.0, _controller.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final queueAsync = ref.watch(playerQueueProvider);
    final currentId = ref.watch(playerCurrentProvider).value?.id;
    final playback = ref.watch(playerStateProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Queue',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      queueAsync.when(
                        data: (q) => q.isEmpty
                            ? 'Nothing queued yet'
                            : '${q.length} song${q.length == 1 ? '' : 's'} · drag to reorder · swipe to remove',
                        loading: () => 'Loading queue…',
                        error: (_, _) => 'Queue unavailable',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (widget.showCloseButton)
                IconButton(
                  tooltip: 'Close queue',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: queueAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not load the queue.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Queue is empty — play something from the Library.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              _maybeScrollTo(currentId, items);
              // Up Next lives outside the ReorderableListView so it stays
              // pinned while the queue scrolls beneath it.
              return Column(
                children: [
                  _upNextStrip(scheme, items, currentId, playback),
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollController: _controller,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 110),
                      itemExtent: _rowHeight,
                      proxyDecorator: (child, _, _) => Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.transparent,
                        child: child,
                      ),
                      onReorder: _reorder,
                      itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isCurrent = item.id == currentId;
                  return Dismissible(
                    key: ValueKey('queue:${item.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: scheme.errorContainer,
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    onDismissed: (_) => _remove(item.id),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => ref
                          .read(playerServiceProvider)
                          .skipToQueueItem(index),
                      child: SizedBox(
                        height: _rowHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: isCurrent
                                    ? const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            FlamoraColors.flame,
                                            FlamoraColors.flameDeep,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        shape: BoxShape.circle,
                                      )
                                    : BoxDecoration(
                                        color: scheme.surfaceContainerHighest
                                            .withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                child: Icon(
                                  isCurrent
                                      ? Icons.equalizer_rounded
                                      : Icons.music_note_rounded,
                                  size: 20,
                                  color: isCurrent
                                      ? Colors.white
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isCurrent
                                            ? scheme.primary
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.artist ?? 'Unknown artist'} · ${formatTrackDuration(item.duration)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    size: 20,
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
          ),
        ),
      ],
    );
  }

  /// Strip calling out the song that plays next (repeat-aware), or a
  /// quiet "ends here" note at the tail with repeat off.
  Widget _upNextStrip(
    ColorScheme scheme,
    List<MediaItem> items,
    String? currentId,
    PlaybackState? playback,
  ) {
    final currentIndex =
        currentId == null ? -1 : items.indexWhere((m) => m.id == currentId);
    final repeat = playback?.repeatMode ?? AudioServiceRepeatMode.none;

    int? nextIndex;
    String label = 'Up next';
    if (currentIndex < 0) {
      nextIndex = 0;
    } else if (repeat == AudioServiceRepeatMode.one) {
      nextIndex = currentIndex;
      label = 'Repeating';
    } else if (currentIndex + 1 < items.length) {
      nextIndex = currentIndex + 1;
    } else if (repeat == AudioServiceRepeatMode.all ||
        repeat == AudioServiceRepeatMode.group) {
      nextIndex = 0;
      label = 'Up next · loops to top';
    }

    if (nextIndex == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Text('Queue ends after this song'),
      );
    }
    final next = items[nextIndex];
    final target = nextIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            ref.read(playerServiceProvider).skipToQueueItem(target),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.queue_music_rounded,
                  size: 20, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: scheme.onPrimaryContainer
                            .withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${next.title} · ${next.artist ?? 'Unknown artist'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.skip_next_rounded,
                  color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
