/// Unified song model shared by every data source.
///
/// Built from MediaStore entries on Android, or from the recursive folder
/// scan with embedded tags on Windows — both filtered to the user's picked
/// folders, so no UI changes are needed when sources change.
class Song {
  /// Stable id. MediaStore-backed songs use `media:<id>`,
  /// Windows files use `file:<path>`.
  final String id;
  final String title;
  final String artist;
  final String? album;

  /// Playable file path handed to just_audio.
  final String path;

  /// Track length in milliseconds.
  final int durationMs;

  /// MediaStore audio id for artwork lookup. Null for non-MediaStore songs.
  final int? artworkId;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    required this.path,
    required this.durationMs,
    this.artworkId,
  });

  /// `m:ss` for lists, `h:mm:ss` once an hour or longer.
  String get formattedDuration => formatTrackDuration(
      Duration(milliseconds: durationMs));
}

/// Formats a nullable track position/length for lists and sliders.
/// Null or negative becomes `0:00` so widgets never crash on missing data.
String formatTrackDuration(Duration? duration) {
  final totalSeconds =
      ((duration ?? Duration.zero).inMilliseconds ~/ 1000).clamp(0, 1 << 31);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}
