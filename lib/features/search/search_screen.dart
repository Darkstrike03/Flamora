import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/folders_repository.dart';
import '../../core/widgets/screen_header.dart';
import '../library/add_to_playlist_sheet.dart';
import '../library/library_provider.dart';
import '../library/song.dart';
import '../player/player_service.dart';
import 'search_history_repository.dart';

/// Search: bar sits right under the header and autofocuses so the
/// keyboard opens immediately — no extra tap needed.
///
/// Searches the live library (songs inside the user's picked folders).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  String query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focus = FocusNode();
    // Re-request after first frame so the keyboard opens every time
    // the tab is visited, not just on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final folders = ref.watch(foldersProvider);
    final allSongs = ref.watch(librarySongsProvider).value ?? const [];
    final history = ref.watch(searchHistoryProvider);
    final q = query.trim().toLowerCase();
    final results = q.isEmpty
        ? const <Song>[]
        : allSongs
            .where((s) =>
                s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q))
            .toList();

    return Column(
      children: [
        const ScreenHeader(
          title: 'Search',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => query = v),
            onSubmitted: (v) {
              setState(() => query = v);
              ref.read(searchHistoryProvider.notifier).record(v);
            },
            decoration: InputDecoration(
              hintText: 'Songs, artists, playlists',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        setState(() => query = '');
                        _focus.requestFocus();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? ListView(
                  padding:
                      const EdgeInsets.fromLTRB(20, 12, 20, 110),
                  children: [
                    if (folders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Text(
                          'Add a music folder in Settings,\nthen search your library here.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (history.isNotEmpty) ...[
                      Row(
                        children: [
                          Text(
                            'Recent',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: scheme.primary,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => ref
                                .read(searchHistoryProvider.notifier)
                                .clear(),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final hint in history)
                            ActionChip(
                              label: Text(hint),
                              onPressed: () {
                                _controller.text = hint;
                                setState(() => query = hint);
                                ref
                                    .read(searchHistoryProvider.notifier)
                                    .record(hint);
                              },
                            ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        'Try',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final hint in [
                            'Ember',
                            'Neon',
                            'Midnight',
                            'Velvet',
                            'Solar'
                          ])
                            ActionChip(
                              label: Text(hint),
                              onPressed: () {
                                _controller.text = hint;
                                setState(() => query = hint);
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                )
              : results.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Text(
                        'No matches — try another search.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          20, 12, 20, 110),
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final song = results[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => ref
                              .read(playerServiceProvider)
                              .playSongs(results,
                                  initialIndex: i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 7),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${song.artist} · ${song.formattedDuration}',
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'More',
                                  onPressed: () =>
                                      showAddToPlaylistSheet(
                                    context,
                                    songId: song.id,
                                    songTitle: song.title,
                                    songArtist: song.artist,
                                  ),
                                  icon: const Icon(
                                      Icons.more_vert_rounded),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
