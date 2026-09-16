import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/player_service.dart';
import '../player/volume_repository.dart';
import 'playlist_name_dialog.dart';
import 'playlists_repository.dart';
import 'volume_trim_dialog.dart';

/// Bottom sheet to add a song to a playlist (or a new one on the spot),
/// plus its per-song balancer fix.
/// Callers: Library song rows and the player "Add to playlist" buttons.
Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required String songId,
  required String songTitle,
  required String songArtist,
}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => _AddSheet(
      songId: songId,
      songTitle: songTitle,
      songArtist: songArtist,
    ),
  );
}

/// Opens the sheet for the currently playing song, or a snackbar when
/// nothing is loaded. Shared by the player "Add to playlist" buttons.
Future<void> showAddCurrentToPlaylist(
    BuildContext context, WidgetRef ref) async {
  final current = ref.read(playerCurrentProvider).value;
  if (current == null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Play something first, then add it.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    return;
  }
  return showAddToPlaylistSheet(
    context,
    songId: current.id,
    songTitle: current.title,
    songArtist: current.artist ?? 'Unknown artist',
  );
}

class _AddSheet extends ConsumerWidget {
  final String songId;
  final String songTitle;
  final String songArtist;

  const _AddSheet({
    required this.songId,
    required this.songTitle,
    required this.songArtist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final trim = ref.watch(volumeSettingsProvider).trimFor(songId);

    void snack(String message) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    }

    Future<void> addTo(String playlistId, String playlistName) async {
      final added = await ref
          .read(playlistsProvider.notifier)
          .addSong(playlistId, songId);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      snack(added
          ? 'Added to “$playlistName”.'
          : 'Already in “$playlistName”.');
    }

    Future<void> createNew() async {
      final name = await showPlaylistNameDialog(
        context,
        title: 'New playlist',
      );
      if (name == null || !context.mounted) return;
      final notifier = ref.read(playlistsProvider.notifier);
      final error = await notifier.create(name);
      if (!context.mounted) return;
      if (error != null) {
        snack(error);
        return;
      }
      final matches =
          ref.read(playlistsProvider).where((p) => p.name == name).toList();
      if (matches.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      await addTo(matches.last.id, matches.last.name);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add to playlist',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.volume_up_outlined),
                    title: const Text('Balance volume'),
                    subtitle: Text(trim == 0
                        ? 'No fix yet'
                        : '${trim > 0 ? '+' : ''}${trim.toStringAsFixed(1)} dB'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onTap: () => showVolumeTrimDialog(
                      context,
                      ref,
                      songId: songId,
                      songTitle: songTitle,
                      songArtist: songArtist,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('New playlist'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onTap: createNew,
                  ),
                  for (final p in playlists)
                    ListTile(
                      leading: const Icon(Icons.queue_music_rounded),
                      title: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${p.songIds.length} song${p.songIds.length == 1 ? '' : 's'}',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () => addTo(p.id, p.name),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
