import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/folders_repository.dart';
import '../../core/widgets/screen_header.dart';
import '../player/player_service.dart';
import 'library_provider.dart';
import 'playlist.dart';
import 'playlist_name_dialog.dart';
import 'playlists_repository.dart';
import 'song.dart';

/// Playlist detail: play-all, drag-reorder, swipe/menu remove, rename,
/// delete. Songs are live references — entries whose files left the
/// library render greyed as unavailable and are skipped on play.
///
/// Folder mode ([folderPath]) shows a tracked folder as a read-only
/// auto-playlist: same rows and playback, but no rename/delete/reorder.
class PlaylistDetailScreen extends ConsumerWidget {
  final String? playlistId;
  final String? folderPath;

  /// Exactly one of [playlistId] (editable user playlist) or [folderPath]
  /// (read-only folder auto-playlist) must be set.
  const PlaylistDetailScreen({super.key, this.playlistId, this.folderPath})
      : assert(playlistId != null || folderPath != null,
            'Need a playlist id or a folder path');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFolder = folderPath != null;
    Playlist? playlist;
    late final List<Song> songs;
    var missing = 0;
    late final String title;
    if (isFolder) {
      final folders = ref.watch(foldersProvider);
      if (!folders.contains(folderPath)) {
        // Folder untracked while open — leave quietly on next frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
        return const SizedBox.shrink();
      }
      final library = ref.watch(librarySongsProvider).value ?? const <Song>[];
      songs = songsInFolder(library, folderPath!);
      title = folderDisplayName(folderPath!);
    } else {
      final playlists = ref.watch(playlistsProvider);
      final index = playlists.indexWhere((p) => p.id == playlistId);
      if (index < 0) {
        // Deleted elsewhere while open — leave quietly on next frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
        return const SizedBox.shrink();
      }
      playlist = playlists[index];
      final library = ref.watch(librarySongsProvider).value ?? const <Song>[];
      final resolved = resolvePlaylistSongs(playlist, library);
      songs = resolved.available;
      missing = resolved.missing;
      title = playlist.name;
    }

    void snack(String message) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    }

    Future<void> rename(String id, String current) async {
      final name = await showPlaylistNameDialog(
        context,
        title: 'Rename playlist',
        initialValue: current,
        confirmLabel: 'Rename',
      );
      if (name == null || !context.mounted) return;
      final error =
          await ref.read(playlistsProvider.notifier).rename(id, name);
      if (!context.mounted) return;
      if (error != null) snack(error);
    }

    Future<void> delete(String id, String name) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete playlist?'),
          content: Text(
              '“$name” will be removed. Your song files stay untouched.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await ref.read(playlistsProvider.notifier).delete(id);
      if (context.mounted) Navigator.of(context).pop();
    }

    Future<void> playAll() async {
      if (songs.isEmpty) {
        snack(isFolder
            ? 'No songs in this folder.'
            : 'No available songs in this playlist.');
        return;
      }
      await ref.read(playerServiceProvider).playSongs(songs);
      if (context.mounted) Navigator.of(context).pop();
    }

    final subtitle = isFolder
        ? (songs.isEmpty
            ? 'Empty folder'
            : 'Folder · ${songs.length} song${songs.length == 1 ? '' : 's'}')
        : (songs.isEmpty
            ? 'Empty playlist'
            : '${songs.length} song${songs.length == 1 ? '' : 's'}'
                '${missing > 0 ? ' · $missing unavailable' : ''}');
    final editable = playlist; // non-null unless in folder mode

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenHeader(
              leading: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: title,
              subtitle: subtitle,
              actions: [
                if (editable != null) ...[
                  IconButton(
                    tooltip: 'Rename',
                    onPressed: () => rename(editable.id, editable.name),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete playlist',
                    onPressed: () => delete(editable.id, editable.name),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: FilledButton.tonalIcon(
                onPressed: songs.isEmpty ? null : playAll,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play all'),
              ),
            ),
            Expanded(
              child: songs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          isFolder
                              ? 'No audio files found in this folder.'
                              : 'No songs here yet — add some from the Library.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _SongList(
                      playlist: playlist,
                      songs: songs,
                      missing: missing,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongList extends ConsumerWidget {
  /// Null in folder mode: plain list, no reorder/remove.
  final Playlist? playlist;
  final List<Song> songs;
  final int missing;

  const _SongList({
    required this.playlist,
    required this.songs,
    required this.missing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final listId = playlist?.id;
    if (listId == null) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 40),
        itemCount: songs.length,
        itemBuilder: (context, index) =>
            _row(context, ref, scheme, songs[index], index),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 40),
      // Dragging only from the handle (the trailing note row has none).
      buildDefaultDragHandles: false,
      itemCount: songs.length + (missing > 0 ? 1 : 0),
      proxyDecorator: (child, _, _) => Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: Colors.transparent,
        child: child,
      ),
      onReorder: (oldIndex, newIndex) {
        if (oldIndex < newIndex) newIndex -= 1;
        if (oldIndex == newIndex || oldIndex >= songs.length) return;
        if (newIndex > songs.length) newIndex = songs.length;
        ref
            .read(playlistsProvider.notifier)
            .moveSong(listId, oldIndex, newIndex.clamp(0, songs.length - 1));
      },
      itemBuilder: (context, index) {
        if (index >= songs.length) {
          return Padding(
            key: const ValueKey('playlist-missing-note'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(
              '$missing song${missing == 1 ? ' is' : 's are'} no longer in your library.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        final song = songs[index];
        return Dismissible(
          key: ValueKey('playlist:$listId:${song.id}'),
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
          onDismissed: (_) => ref
              .read(playlistsProvider.notifier)
              .removeSong(listId, song.id),
          child: _row(context, ref, scheme, song, index, draggable: true),
        );
      },
    );
  }

  /// Shared song row; the drag handle only appears in playlist mode.
  Widget _row(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
    Song song,
    int index, {
    bool draggable = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () =>
          ref.read(playerServiceProvider).playSongs(songs, initialIndex: index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.music_note_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${song.artist} · ${song.formattedDuration}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (draggable)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
