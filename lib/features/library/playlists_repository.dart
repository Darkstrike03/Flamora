import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'playlist.dart';

/// User playlists, persisted in Hive.
///
/// Same pattern as the folder store: the box is opened in `main()` before
/// `runApp`, so it is always available here. Stored as plain maps under
/// one key (no adapters needed). Mutations return an error message for
/// UI feedback, or null on success.
const _boxName = 'flamora';
const _playlistsKey = 'playlists';

final playlistsProvider =
    NotifierProvider<PlaylistsNotifier, List<Playlist>>(
        PlaylistsNotifier.new);

class PlaylistsNotifier extends Notifier<List<Playlist>> {
  late final Box _box;

  @override
  List<Playlist> build() {
    _box = Hive.box(_boxName);
    final stored = _box.get(_playlistsKey, defaultValue: const []);
    return (stored as List)
        .map((e) => Playlist.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _persist() =>
      _box.put(_playlistsKey, [for (final p in state) p.toMap()]);

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Playlist? _byId(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool _nameTaken(String name, [String? exceptId]) {
    final needle = name.trim().toLowerCase();
    return state.any((p) =>
        p.id != exceptId && p.name.trim().toLowerCase() == needle);
  }

  /// Creates a playlist. Returns an error message, or null on success.
  Future<String?> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty.';
    if (_nameTaken(trimmed)) {
      return 'A playlist with this name already exists.';
    }
    state = [
      ...state,
      Playlist(
        id: _newId(),
        name: trimmed,
        songIds: const [],
        createdAt: DateTime.now(),
      ),
    ];
    await _persist();
    return null;
  }

  /// Renames a playlist. Returns an error message, or null on success.
  Future<String?> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty.';
    if (_nameTaken(trimmed, id)) {
      return 'A playlist with this name already exists.';
    }
    state = [
      for (final p in state)
        if (p.id == id) p.copyWith(name: trimmed) else p,
    ];
    await _persist();
    return null;
  }

  Future<void> delete(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _persist();
  }

  /// Adds a song id. Returns false when it was already present.
  Future<bool> addSong(String id, String songId) async {
    final playlist = _byId(id);
    if (playlist == null || playlist.songIds.contains(songId)) return false;
    state = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(songIds: [...p.songIds, songId])
        else
          p,
    ];
    await _persist();
    return true;
  }

  Future<void> removeSong(String id, String songId) async {
    state = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(
              songIds: p.songIds.where((s) => s != songId).toList())
        else
          p,
    ];
    await _persist();
  }

  Future<void> moveSong(String id, int oldIndex, int newIndex) async {
    final playlist = _byId(id);
    if (playlist == null) return;
    final ids = List.of(playlist.songIds);
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    final target = newIndex.clamp(0, ids.length - 1);
    if (target == oldIndex) return;
    final songId = ids.removeAt(oldIndex);
    ids.insert(target, songId);
    state = [
      for (final p in state)
        if (p.id == id) p.copyWith(songIds: ids) else p,
    ];
    await _persist();
  }
}
