import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/storage/folders_repository.dart';
import 'song.dart';

final _audioQuery = OnAudioQuery();

/// True when the app may read audio files: `READ_MEDIA_AUDIO` on
/// Android 13+ or legacy storage below that. Windows always returns true —
/// there is no runtime permission model there; picking a folder in Settings
/// is the consent.
Future<bool> hasAudioAccess() async {
  if (Platform.isWindows) return true;
  if (!Platform.isAndroid) return false;
  return Permission.audio.isGranted.then((granted) async =>
      granted || await Permission.storage.isGranted);
}

/// Requests audio access, trying the granular media permission first
/// and falling back to legacy storage (no extra dependency needed to
/// branch on the OS version — the inapplicable request just denies).
/// Windows is a no-op returning true (see [hasAudioAccess]).
Future<bool> requestAudioAccess() async {
  if (Platform.isWindows) return true;
  if (!Platform.isAndroid) return false;
  if (await Permission.audio.isGranted) return true;
  if (await Permission.audio.request().isGranted) return true;
  if (await Permission.storage.isGranted) return true;
  return Permission.storage.request().isGranted;
}

bool _notificationAsked = false;

/// Best-effort notification permission for the playback notification
/// (Android 13+). Asks at most once per launch, never throws, never blocks
/// playback. No-op off-Android.
Future<void> ensureNotificationAccess() async {
  if (!Platform.isAndroid || _notificationAsked) return;
  _notificationAsked = true;
  try {
    if (await Permission.notification.isGranted) return;
    await Permission.notification.request();
  } catch (_) {}
}

/// Current audio-access state for empty-state UI. Invalidate after
/// [requestAudioAccess] to re-evaluate (which also refreshes
/// [librarySongsProvider] through its own watch chain — invalidate both
/// to be explicit).
final audioAccessProvider = FutureProvider<bool>((ref) async {
  ref.watch(foldersProvider);
  return hasAudioAccess();
});

/// Songs inside the user's picked folders, title-sorted.
///
/// Empty when no folders are tracked or access is missing. Watches
/// [foldersProvider], so adding/removing a folder rescans automatically.
/// Permission prompts stay in UI event handlers — this provider never
/// pops a system dialog by itself.
///
/// Data source per platform: MediaStore on Android ([OnAudioQuery]),
/// recursive folder scan with embedded tags on Windows ([_scanWindows]).
final librarySongsProvider = FutureProvider<List<Song>>((ref) async {
  final folders = ref.watch(foldersProvider);
  if (folders.isEmpty) return const <Song>[];
  if (!await hasAudioAccess()) return const <Song>[];

  if (Platform.isWindows) return _scanWindows(folders);
  if (!Platform.isAndroid) return const <Song>[];

  final models = await _audioQuery.querySongs(
    sortType: SongSortType.TITLE,
    orderType: OrderType.ASC_OR_SMALLER,
    uriType: UriType.EXTERNAL,
    ignoreCase: true,
  );

  final prefixes = folders.map(_withTrailingSlash).toList();
  bool inScope(String data) {
    final normalized = data.replaceAll('\\', '/');
    final candidate =
        Platform.isAndroid ? normalized.toLowerCase() : normalized;
    return prefixes.any((p) => candidate.startsWith(p));
  }

  final songs = <Song>[];
  for (final m in models) {
    if (!inScope(m.data)) continue;
    final title = m.title.trim();
    final artist = (m.artist ?? '').trim();
    songs.add(Song(
      id: 'media:${m.id}',
      title: title.isEmpty ? 'Unknown title' : title,
      artist: artist.isEmpty ? 'Unknown artist' : artist,
      album: m.album,
      path: m.data,
      durationMs: m.duration ?? 0,
      artworkId: m.id,
    ));
  }
  return songs;
});

String _withTrailingSlash(String folder) {
  var p = folder.replaceAll('\\', '/');
  if (!p.endsWith('/')) p = '$p/';
  if (Platform.isAndroid) return p.toLowerCase();
  return p;
}

/// Display name for a tracked folder (last path segment).
/// `C:\Music\Gym Mix` → `Gym Mix`.
String folderDisplayName(String folder) {
  var p = folder.replaceAll('\\', '/');
  while (p.endsWith('/') && p.length > 1) {
    p = p.substring(0, p.length - 1);
  }
  final segments = p.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? folder : segments.last;
}

/// Songs under [folder] (case-insensitive prefix match, both separators
/// tolerated). Powers folder auto-playlists; input order is preserved,
/// so results stay title-sorted like the library providers.
List<Song> songsInFolder(List<Song> songs, String folder) {
  var p = folder.replaceAll('\\', '/');
  if (!p.endsWith('/')) p = '$p/';
  final prefix = p.toLowerCase();
  return songs
      .where((s) => s.path.replaceAll('\\', '/').toLowerCase().startsWith(prefix))
      .toList();
}

/// Audio file extensions picked up by the Windows folder scan.
const _windowsAudioExts = {
  'mp3',
  'm4a',
  'aac',
  'flac',
  'wav',
  'ogg',
  'oga',
  'opus',
  'wma',
  'aiff',
  'aif',
  'alac',
};

/// Windows library: recursively scans [folders] with `dart:io` and reads
/// embedded tags (title/artist/album/duration) per file. One unreadable
/// file never fails the whole scan — it falls back to a filename entry.
/// Result is title-sorted (case-insensitive) like the Android query.
Future<List<Song>> _scanWindows(List<String> folders) async {
  final songs = <Song>[];
  for (final folder in folders) {
    final dir = Directory(folder);
    if (!await dir.exists()) continue;
    await for (final entity
        in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = entity.path.split('.').last.toLowerCase();
      if (!_windowsAudioExts.contains(ext)) continue;
      songs.add(await _windowsSong(entity));
    }
  }
  songs.sort((a, b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return songs;
}

/// Builds a [Song] from a Windows audio file, preferring embedded tags
/// and falling back to the file name (`Artist - Title` split supported).
Future<Song> _windowsSong(File file) async {
  final fileName = file.uri.pathSegments.last;
  final base = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
  var title = base;
  var artist = 'Unknown artist';
  String? album;
  var durationMs = 0;

  try {
    final tag = await AudioTags.read(file.path);
    if (tag != null) {
      final tagTitle = tag.title?.trim() ?? '';
      final tagArtist = tag.trackArtist?.trim() ?? '';
      if (tagTitle.isNotEmpty) title = tagTitle;
      if (tagArtist.isNotEmpty) {
        artist = tagArtist;
      } else if (tagTitle.isEmpty) {
        // No usable tags at all — try the file name convention.
        final split = _splitArtistTitle(base);
        if (split != null) {
          artist = split.$1;
          title = split.$2;
        }
      }
      final tagAlbum = tag.album?.trim() ?? '';
      if (tagAlbum.isNotEmpty) album = tagAlbum;
      // audiotags reports duration in seconds.
      if ((tag.duration ?? 0) > 0) {
        durationMs = tag.duration! * 1000;
      }
    } else {
      final split = _splitArtistTitle(base);
      if (split != null) {
        artist = split.$1;
        title = split.$2;
      }
    }
  } catch (_) {
    final split = _splitArtistTitle(base);
    if (split != null) {
      artist = split.$1;
      title = split.$2;
    }
  }

  title = title.trim();
  if (title.isEmpty) title = 'Unknown title';
  return Song(
    id: 'file:${file.path}',
    title: title,
    artist: artist,
    album: album,
    path: file.path,
    durationMs: durationMs,
    artworkId: null,
  );
}

/// Splits `Artist - Title` file names. Returns null when the convention
/// doesn't apply, leaving title/artist fallback to the caller.
(String, String)? _splitArtistTitle(String base) {
  final dash = base.indexOf(' - ');
  if (dash <= 0) return null;
  final artist = base.substring(0, dash).trim();
  final title = base.substring(dash + 3).trim();
  if (artist.isEmpty || title.isEmpty) return null;
  return (artist, title);
}
