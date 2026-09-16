import 'song.dart';

/// A user playlist. Songs are stored as live references (song ids) and
/// resolved against the current library on read, so renames/rescans flow
/// through automatically. Ids missing from the library (deleted files,
/// removed folders) resolve as unavailable instead of failing.
class Playlist {
  /// Unique id (timestamp-based, generated at creation).
  final String id;
  final String name;

  /// Song ids in play order (`media:<id>` on Android, `file:<path>`
  /// on Windows — see [Song.id]).
  final List<String> songIds;
  final DateTime createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'songIds': List.of(songIds),
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Playlist.fromMap(Map<String, dynamic> map) => Playlist(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? 'Untitled',
        songIds: ((map['songIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );

  Playlist copyWith({String? name, List<String>? songIds}) => Playlist(
        id: id,
        name: name ?? this.name,
        songIds: songIds ?? this.songIds,
        createdAt: createdAt,
      );
}

/// Splits [playlist]'s stored ids into songs present in [library] (in
/// playlist order) plus the count of ids that no longer resolve.
({List<Song> available, int missing}) resolvePlaylistSongs(
  Playlist playlist,
  List<Song> library,
) {
  final byId = {for (final s in library) s.id: s};
  final available = [
    for (final id in playlist.songIds)
      if (byId.containsKey(id)) byId[id]!,
  ];
  return (available: available, missing: playlist.songIds.length - available.length);
}
