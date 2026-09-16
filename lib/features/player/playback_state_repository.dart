import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../library/library_provider.dart';
import 'player_service.dart';

/// Last playback session, persisted in Hive: queue (song ids only, so any
/// size stays cheap), current index, and position. Restored paused on next
/// launch so the player never starts empty. Ids that no longer resolve
/// against the library are skipped at restore time.
const _boxName = 'flamora';
const _playbackKey = 'playback';

class PlaybackSnapshot {
  final List<String> songIds;
  final int index;
  final int positionMs;

  const PlaybackSnapshot({
    required this.songIds,
    required this.index,
    required this.positionMs,
  });

  Map<String, dynamic> toMap() => {
        'songIds': List.of(songIds),
        'index': index,
        'positionMs': positionMs,
      };

  factory PlaybackSnapshot.fromMap(Map<String, dynamic> map) {
    final rawIds = map['songIds'];
    return PlaybackSnapshot(
      songIds: rawIds is List
          ? rawIds.map((e) => e.toString()).toList()
          : const <String>[],
      index: ((map['index'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
      positionMs: ((map['positionMs'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
    );
  }
}

final playbackSnapshotProvider =
    NotifierProvider<PlaybackSnapshotNotifier, PlaybackSnapshot?>(
        PlaybackSnapshotNotifier.new);

class PlaybackSnapshotNotifier extends Notifier<PlaybackSnapshot?> {
  late final Box _box;

  @override
  PlaybackSnapshot? build() {
    _box = Hive.box(_boxName);
    final stored = _box.get(_playbackKey);
    if (stored is! Map) return null;
    final snap =
        PlaybackSnapshot.fromMap(Map<String, dynamic>.from(stored));
    return snap.songIds.isEmpty ? null : snap;
  }

  Future<void> save({
    required List<String> songIds,
    required int index,
    required int positionMs,
  }) async {
    if (songIds.isEmpty) {
      await clear();
      return;
    }
    state = PlaybackSnapshot(
      songIds: List.of(songIds),
      index: index.clamp(0, songIds.length - 1),
      positionMs: positionMs.clamp(0, 1 << 31),
    );
    await _box.put(_playbackKey, state!.toMap());
  }

  Future<void> clear() async {
    state = null;
    await _box.delete(_playbackKey);
  }
}

/// Persists the live session for next-launch restore. Watched once by
/// AppShell. Saves on queue/track change, on pause (final position), and
/// throttled while playing. Never wipes an untouched session: the box is
/// only cleared after this session owned a queue.
final playbackSaverProvider = Provider<void>((ref) {
  var everHadQueue = false;
  var lastPosSave = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> save() async {
    final service = ref.read(playerServiceProvider);
    if (!service.isReady) return;
    final queue = ref.read(playerQueueProvider).value ?? const <MediaItem>[];
    final notifier = ref.read(playbackSnapshotProvider.notifier);
    if (queue.isEmpty) {
      if (everHadQueue) {
        everHadQueue = false;
        await notifier.clear();
      }
      return;
    }
    everHadQueue = true;
    final currentId = ref.read(playerCurrentProvider).value?.id;
    var index = queue.indexWhere((m) => m.id == currentId);
    if (index < 0) index = 0;
    final positionMs =
        ref.read(playerPositionProvider).value?.inMilliseconds ?? 0;
    await notifier.save(
      songIds: [for (final m in queue) m.id],
      index: index,
      positionMs: positionMs,
    );
  }

  ref.listen(playerQueueProvider, (_, _) => save());
  ref.listen(playerCurrentProvider, (_, _) => save());
  ref.listen(playerPositionProvider, (_, _) {
    final now = DateTime.now();
    if (now.difference(lastPosSave).inSeconds >= 10) {
      lastPosSave = now;
      save();
    }
  });
  ref.listen(playerStateProvider, (prev, next) {
    if ((prev?.value?.playing ?? false) && !(next.value?.playing ?? true)) {
      lastPosSave = DateTime.now();
      save();
    }
  });
});

/// One-shot paused restore on launch. Runs once the library first loads
/// with the player still idle; later library reloads are ignored because
/// the player is initialized by then. Ids that no longer resolve are
/// skipped and the index is remapped by id.
final playbackRestoreProvider = FutureProvider<void>((ref) async {
  final library = await ref.watch(librarySongsProvider.future);
  final service = ref.read(playerServiceProvider);
  if (service.isReady) return;
  final snap = ref.read(playbackSnapshotProvider);
  if (snap == null || snap.songIds.isEmpty) return;
  final byId = {for (final s in library) s.id: s};
  final songs = [
    for (final id in snap.songIds)
      if (byId.containsKey(id)) byId[id]!,
  ];
  if (songs.isEmpty) return;
  var index = 0;
  if (snap.index < snap.songIds.length) {
    final found = songs.indexWhere((s) => s.id == snap.songIds[snap.index]);
    if (found >= 0) index = found;
  }
  final startAt = Duration(
      milliseconds: snap.positionMs.clamp(0, songs[index].durationMs));
  await service.playSongs(
    songs,
    initialIndex: index,
    autoplay: false,
    startAt: startAt.inMilliseconds > 0 ? startAt : null,
  );
});
