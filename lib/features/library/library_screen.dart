import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/folders_repository.dart';
import '../../core/theme/flamora_colors.dart';
import '../../core/widgets/neu_card.dart';
import '../../core/widgets/screen_header.dart';
import '../player/player_service.dart';
import 'add_to_playlist_sheet.dart';
import 'library_provider.dart';
import 'playlist.dart';
import 'playlist_detail_screen.dart';
import 'playlist_name_dialog.dart';
import 'playlists_repository.dart';
import 'song.dart';

/// Library with two tabs: Songs + Playlists.
///
/// Songs are the live [librarySongsProvider] list (MediaStore entries on
/// Android, embedded-tag scan on Windows) inside the user's picked folders;
/// playlists are user collections stored in Hive.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songCount = ref.watch(librarySongsProvider).value?.length;
    final listCount = ref.watch(playlistsProvider).length +
        ref.watch(foldersProvider).length;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          ScreenHeader(
            title: 'Library',
            subtitle: songCount == null
                ? '$listCount playlists'
                : '$songCount songs · $listCount playlists',
            actions: [
              IconButton(
                tooltip: 'Rescan folders',
                onPressed: () {
                  ref.invalidate(audioAccessProvider);
                  ref.invalidate(librarySongsProvider);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Rescanning library…'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TabBar(
              tabs: [
                Tab(text: 'Songs'),
                Tab(text: 'Playlists'),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 800),
                child: TabBarView(
                  children: [
                    _SongsTab(),
                    _PlaylistsTab(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongsTab extends ConsumerStatefulWidget {
  const _SongsTab();

  @override
  ConsumerState<_SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends ConsumerState<_SongsTab> {
  String query = '';

  Future<void> _grantAccess() async {
    if (await requestAudioAccess()) {
      ref
        ..invalidate(audioAccessProvider)
        ..invalidate(librarySongsProvider);
      // Playback notification (Android 13+) — best-effort, never blocks.
      await ensureNotificationAccess();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Audio access denied — library stays empty.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final folders = ref.watch(foldersProvider);
    final songsAsync = ref.watch(librarySongsProvider);

    if (folders.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: const [
          SizedBox(height: 32),
          Icon(Icons.folder_open_rounded, size: 48),
          SizedBox(height: 12),
          Text(
            'No music folders yet.\nAdd one in Settings to build your library.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return songsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Could not read your songs.',
              textAlign: TextAlign.center),
        ),
      ),
      data: (allSongs) {
        // Empty with folders tracked means access is missing (the query
        // returns [] without permission) — offer the grant button.
        final accessAsync = ref.watch(audioAccessProvider);
        final access = accessAsync.value ?? true;
        if (allSongs.isEmpty && !access) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              const SizedBox(height: 32),
              const Icon(Icons.lock_outline_rounded, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Flamora needs audio access to read your folders.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Center(
                child: FilledButton.tonal(
                  onPressed: _grantAccess,
                  child: const Text('Grant access'),
                ),
              ),
            ],
          );
        }

        final q = query.trim().toLowerCase();
        final songs = q.isEmpty
            ? allSongs
            : allSongs
                .where((s) =>
                    s.title.toLowerCase().contains(q) ||
                    s.artist.toLowerCase().contains(q))
                .toList();

        return _songList(scheme, songs, allSongs);
      },
    );
  }

  Widget _songList(
      ColorScheme scheme, List<Song> songs, List<Song> allSongs) {
    return ListView(
      // Bottom inset clears the floating nav.
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search songs or artists',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            isDense: true,
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 8),
        if (songs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text(
                allSongs.isEmpty
                    ? 'No songs found in your folders yet.'
                    : 'No matches — try another search.',
                textAlign: TextAlign.center),
          )
        else
          for (var i = 0; i < songs.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => ref
                  .read(playerServiceProvider)
                  .playSongs(songs, initialIndex: i),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
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
                            songs[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${songs[i].artist} · ${songs[i].formattedDuration}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'More',
                      onPressed: () => showAddToPlaylistSheet(
                        context,
                        songId: songs[i].id,
                        songTitle: songs[i].title,
                        songArtist: songs[i].artist,
                      ),
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showPlaylistNameDialog(context, title: 'New playlist');
    if (name == null || !context.mounted) return;
    final error = await ref.read(playlistsProvider.notifier).create(name);
    if (error != null && context.mounted) _snack(context, error);
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, String id, String current) async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Rename playlist',
      initialValue: current,
      confirmLabel: 'Rename',
    );
    if (name == null || !context.mounted) return;
    final error =
        await ref.read(playlistsProvider.notifier).rename(id, name);
    if (error != null && context.mounted) _snack(context, error);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id, String name) async {
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
    if (confirmed == true && context.mounted) {
      await ref.read(playlistsProvider.notifier).delete(id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final playlists = ref.watch(playlistsProvider);
    final folders = ref.watch(foldersProvider);
    final library = ref.watch(librarySongsProvider).value ?? const <Song>[];
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: 1 + playlists.length + folders.length,
      itemBuilder: (context, i) {
        if (i == 0) {
          return NeuCard(
            onTap: () => _create(context, ref),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded,
                    size: 36, color: scheme.primary),
                const SizedBox(height: 8),
                const Text('New playlist',
                    style:
                        TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }
        final pi = i - 1;
        if (pi < playlists.length) {
          return _userCard(context, ref, scheme, playlists[pi]);
        }
        final folder = folders[pi - playlists.length];
        final count = songsInFolder(library, folder).length;
        return NeuCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(folderPath: folder),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        FlamoraColors.flame,
                        FlamoraColors.flameDeep
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  child: const Center(
                    child: Icon(Icons.folder_rounded,
                        color: Colors.white, size: 32),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(folderDisplayName(folder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                'Folder · $count track${count == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _userCard(
      BuildContext context, WidgetRef ref, ColorScheme scheme, Playlist p) {
    return NeuCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlistId: p.id),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        FlamoraColors.flame,
                        FlamoraColors.flameDeep
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  child: const Center(
                    child: Icon(Icons.music_note_rounded,
                        color: Colors.white, size: 32),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${p.songIds.length} track${p.songIds.length == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Playlist options',
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (value) {
                      if (value == 'rename') {
                        _rename(context, ref, p.id, p.name);
                      } else if (value == 'delete') {
                        _delete(context, ref, p.id, p.name);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
  }
}
