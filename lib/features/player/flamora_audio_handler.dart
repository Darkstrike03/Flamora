import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../library/song.dart';
import 'equalizer_repository.dart';
import 'volume_repository.dart';

/// Background-capable audio handler: `just_audio` does the decoding,
/// `audio_service` mirrors state to the system (notification, lockscreen,
/// screen-off playback) on mobile.
///
/// On Android this object lives in the background isolate (created by the
/// `AudioService.init` builder); on desktop it runs in-process. UI code
/// never touches it directly — see `PlayerService`, which routes calls
/// to the right place per platform.
class FlamoraAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  /// Native Android equalizer. Attached at player construction on Android
  /// only — just_audio activates every pipeline effect unconditionally, and
  /// the Windows backend throws on the Android-only parameter call, which
  /// would break all playback. Off-Android the default pipeline keeps
  /// behavior identical to before EQ existed.
  final AndroidEqualizer equalizer = AndroidEqualizer();
  late final AudioPlayer player = AudioPlayer(
    audioPipeline: Platform.isAndroid
        ? AudioPipeline(androidAudioEffects: [equalizer])
        : null,
  );

  /// Mirrored EQ settings so reloads re-apply automatically.
  bool _eqEnabled = false;
  List<double> _eqGains = const [0, 0, 0, 0, 0];

  /// Mirrored modes: just_audio shuffle/loop flips don't reliably emit
  /// playback events, so the transform below stamps every state with the
  /// last mode set here. Without this, each piped event resets the UI
  /// buttons back to none.
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  /// Natural song order. The live queue/sources may be a shuffled
  /// permutation of this list; backend shuffle stays off on every platform
  /// (mpv reports shuffled positions against the original sequence, which
  /// desyncs titles from audio), so ordering lives here instead.
  List<Song> _masterSongs = const [];

  FlamoraAudioHandler() {
    // Plain listen (not pipe/addStream): setShuffleMode/setRepeatMode push
    // manual playbackState updates that can interleave with piped events,
    // and rxdart throws ("cannot add items while items are being added
    // from addStream") on that re-entrancy. listen+add is equivalent here.
    player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });
    // Track the current item by audio-source tag (the song id), not by
    // queue index: backends may reorder playback (shuffle) so an index
    // can point at a different song than the one actually playing.
    player.sequenceStateStream.listen((state) {
      final tag = state.currentSource?.tag;
      if (tag == null) return;
      final currentQueue = queue.value;
      final index = currentQueue.indexWhere((m) => m.id == tag);
      if (index == -1) return;
      mediaItem.add(currentQueue[index]);
    });
  }

  /// Replaces the queue and starts playback at [initialIndex].
  /// When shuffle is already on, playback starts at the tapped song with
  /// the rest shuffled behind it. With [autoplay] false the queue loads
  /// paused at [startAt] (session restore).
  Future<void> playSongs(
    List<Song> songs, {
    int initialIndex = 0,
    bool autoplay = true,
    Duration? startAt,
  }) async {
    if (songs.isEmpty) return;
    _masterSongs = List.of(songs);
    final tapped = songs[initialIndex.clamp(0, songs.length - 1)];
    await _loadQueue(
      _orderForPlayback(startSong: tapped),
      initialSongId: tapped.id,
      autoplay: autoplay,
      startAt: startAt,
    );
  }

  /// Playback order for [startSong]: natural master order, or the start
  /// song first with the rest shuffled when shuffle is enabled.
  List<Song> _orderForPlayback({required Song startSong}) {
    if (_shuffleMode == AudioServiceShuffleMode.none) {
      return List.of(_masterSongs);
    }
    final rest = _masterSongs.where((s) => s.id != startSong.id).toList()
      ..shuffle();
    return [startSong, ...rest];
  }

  /// Loads [ordered] songs into the queue and player, starting at
  /// [initialSongId]. With [preserveState], position and play/pause state
  /// survive the reload (shuffle toggle, reorder); otherwise playback
  /// restarts from [startAt] (or zero) and plays unless [autoplay] is false
  /// (session restore loads paused).
  Future<void> _loadQueue(
    List<Song> ordered, {
    required String initialSongId,
    bool preserveState = false,
    bool autoplay = true,
    Duration? startAt,
  }) async {
    final resumePosition =
        startAt ?? (preserveState ? player.position : Duration.zero);
    final resumePlaying = autoplay && (preserveState ? player.playing : true);
    final items = ordered.map(_toMediaItem).toList();
    queue.add(items);
    var start = ordered.indexWhere((s) => s.id == initialSongId);
    if (start < 0) start = 0;
    mediaItem.add(items[start]);
    await player.setAudioSources(
      ordered.map((s) => AudioSource.uri(_playbackUri(s), tag: s.id)).toList(),
      initialIndex: start,
    );
    // Reloads drop effect state — re-push mirrored EQ gains.
    await _pushEqualizer();
    if (resumePosition > Duration.zero) {
      await player.seek(resumePosition);
    }
    if (resumePlaying) await player.play();
  }

  /// Playback URI for a song. Android MediaStore songs play through their
  /// `content://` URI: raw file paths ([Song.path]) are unreadable under
  /// scoped storage with only media-read permission, so `Uri.file` loads
  /// fail there. Windows (plain files) keeps `Uri.file`.
  Uri _playbackUri(Song s) {
    if (Platform.isAndroid && s.id.startsWith('media:')) {
      final mediaId = s.id.substring('media:'.length);
      return Uri.parse('content://media/external/audio/media/$mediaId');
    }
    return Uri.file(s.path);
  }

  /// Handler-wide [MediaItem] mapping; queue and sources always share
  /// the same order, so indices stay valid everywhere.
  MediaItem _toMediaItem(Song s) => MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: Duration(milliseconds: s.durationMs),
        extras: {'path': s.path},
      );

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() =>
      player.hasNext ? player.seekToNext() : Future.value();

  @override
  Future<void> skipToPrevious() =>
      player.hasPrevious ? player.seekToPrevious() : Future.value();

  @override
  Future<void> skipToQueueItem(int index) async {
    final currentQueue = queue.value;
    if (index < 0 || index >= currentQueue.length) return;
    mediaItem.add(currentQueue[index]);
    await player.seek(Duration.zero, index: index);
  }

  /// Reorders the live queue, preserving position and play state.
  /// Indices are final positions (callers adjust the ReorderableListView
  /// `newIndex` first). Queue, player sources, and [_masterSongs] stay in
  /// lockstep so later shuffle toggles preserve the user's arrangement.
  /// Manual reorder takes over playback order, so shuffle + repeat are
  /// switched off (no extra rebuild — the order below is already final).
  ///
  /// Sources are rebuilt rather than dynamically moved: the Windows
  /// backend mis-maps move indices, so a dynamic move desyncs its play
  /// order from the queue (next plays the wrong song). The load path
  /// builds the backend playlist in exact order.
  ///
  /// Not an audio_service protocol method, so the mobile proxy can't
  /// forward it — [PlayerService] routes it through `customAction`
  /// (see below) on Android/iOS and calls it directly on desktop.
  Future<void> moveQueueItem(int currentIndex, int newIndex) async {
    final currentQueue = List.of(queue.value);
    if (currentIndex < 0 || currentIndex >= currentQueue.length) return;
    final target = newIndex.clamp(0, currentQueue.length - 1);
    if (target == currentIndex) return;
    final item = currentQueue.removeAt(currentIndex);
    currentQueue.insert(target, item);
    queue.add(currentQueue);
    _syncMasterToQueue(currentQueue);
    final byId = {for (final s in _masterSongs) s.id: s};
    final ordered = [
      for (final m in currentQueue)
        if (byId.containsKey(m.id)) byId[m.id]!,
    ];
    if (ordered.isEmpty) return;
    final currentId = mediaItem.value?.id ?? item.id;
    await _loadQueue(
      ordered,
      initialSongId: currentId,
      preserveState: true,
    );
    await _clearModesWithoutRebuild();
  }

  /// Removes a queue entry. Removing the playing song continues with
  /// whatever slid into its slot (clamped to the tail); emptying the
  /// queue stops playback.
  @override
  Future<void> removeQueueItemAt(int index) async {
    final currentQueue = List.of(queue.value);
    if (index < 0 || index >= currentQueue.length) return;
    final removed = currentQueue[index];
    final wasCurrent = mediaItem.value?.id == removed.id;
    final source = player.audioSource;
    // Same justification as the move above.
    // ignore: deprecated_member_use
    if (source is ConcatenatingAudioSource) {
      await source.removeAt(index);
    }
    currentQueue.removeAt(index);
    _masterSongs.removeWhere((s) => s.id == removed.id);
    queue.add(currentQueue);
    if (currentQueue.isEmpty) {
      await player.stop();
      mediaItem.add(null);
      return;
    }
    if (wasCurrent) {
      final next = index.clamp(0, currentQueue.length - 1);
      mediaItem.add(currentQueue[next]);
      await player.seek(Duration.zero, index: next);
    }
  }

  /// Keeps the natural order in sync with a manually reordered queue so
  /// a later shuffle-off preserves the arrangement. Master songs missing
  /// from the live queue are appended, never dropped.
  void _syncMasterToQueue(List<MediaItem> ordered) {
    if (_masterSongs.isEmpty) return;
    final byId = {for (final s in _masterSongs) s.id: s};
    final synced = [
      for (final m in ordered)
        if (byId.containsKey(m.id)) byId[m.id]!,
    ];
    final seen = synced.map((s) => s.id).toSet();
    synced.addAll(_masterSongs.where((s) => !seen.contains(s.id)));
    _masterSongs = synced;
  }

  /// Switches shuffle + repeat off without rebuilding queue/sources.
  /// Used after manual reorder/remove, where the live order is final.
  Future<void> _clearModesWithoutRebuild() async {
    _shuffleMode = AudioServiceShuffleMode.none;
    _repeatMode = AudioServiceRepeatMode.none;
    await player.setShuffleModeEnabled(false);
    await player.setLoopMode(LoopMode.off);
    playbackState.add(_transformEvent(player.playbackEvent));
    await super.setShuffleMode(AudioServiceShuffleMode.none);
    await super.setRepeatMode(AudioServiceRepeatMode.none);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    // Backend shuffle is never enabled: mpv's shuffled playlist positions
    // can't be mapped back to just_audio's sequence (wrong titles), so the
    // queue/sources are rebuilt in the desired order instead. This only
    // guarantees the backend stays unshuffled on every platform.
    await player.setShuffleModeEnabled(false);
    if (queue.value.isNotEmpty && _masterSongs.isNotEmpty) {
      final currentId = mediaItem.value?.id ?? queue.value.first.id;
      final startSong = _masterSongs.firstWhere(
        (s) => s.id == currentId,
        orElse: () => _masterSongs.first,
      );
      await _loadQueue(
        _orderForPlayback(startSong: startSong),
        initialSongId: startSong.id,
        preserveState: true,
      );
    }
    // Shuffle/loop flips don't emit a playback event, so push state manually.
    playbackState.add(_transformEvent(player.playbackEvent));
    await super.setShuffleMode(shuffleMode);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    await player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
    });
    playbackState.add(_transformEvent(player.playbackEvent));
    await super.setRepeatMode(repeatMode);
  }

  /// Applies equalizer settings (Android only). Gains align to the shared
  /// reference table ([eqReferenceFreqs]) and are mapped onto the device's
  /// bands here, where the band layout is known. Settings are mirrored so
  /// reloads re-apply automatically. [freqs] is reserved for future tables
  /// and currently must match the reference table.
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> gains,
    required List<double> freqs,
  }) async {
    _eqEnabled = enabled;
    _eqGains = List.of(gains);
    await _pushEqualizer();
  }

  Future<void> _pushEqualizer() async {
    if (!Platform.isAndroid || player.audioSource == null) return;
    try {
      final params = await equalizer.parameters;
      await equalizer.setEnabled(_eqEnabled);
      for (final band in params.bands) {
        final gain = _nearestRefGain(band.centerFrequency)
            .clamp(params.minDecibels, params.maxDecibels);
        await band.setGain(gain);
      }
    } catch (_) {
      // EQ must never break playback.
    }
  }

  double _nearestRefGain(double centerHz) {
    // Pushes always carry the shared reference table, so the shared
    // mapping agrees with the settings store by construction.
    if (_eqGains.isEmpty) return 0;
    return _eqGains[nearestRefIndex(centerHz).clamp(0, _eqGains.length - 1)];
  }

  /// Device band snapshot for UI sliders (Android with a loaded source,
  /// empty list elsewhere).
  Future<List<Map<String, dynamic>>> equalizerBands() async {
    if (!Platform.isAndroid || player.audioSource == null) return [];
    try {
      final params = await equalizer.parameters;
      return [
        for (final b in params.bands)
          {
            'index': b.index,
            'centerHz': b.centerFrequency,
            'gain': b.gain,
            'minDb': params.minDecibels,
            'maxDb': params.maxDecibels,
          },
      ];
    } catch (_) {
      return [];
    }
  }

  /// Remote entry points: the UI proxy forwards custom calls through here.
  /// `playSongs`, `moveQueueItem`, `applyVolume`, `applyEqualizer`, and
  /// `getEqualizerBands` aren't audio_service protocol methods, so mobile
  /// reaches them this way; desktop calls directly.
  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'applyEqualizer' && extras != null) {
      await applyEqualizer(
        enabled: extras['enabled'] == true,
        gains: (extras['gains'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const <double>[],
        freqs: (extras['freqs'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const <double>[],
      );
      return null;
    }
    if (name == 'getEqualizerBands') {
      return equalizerBands();
    }
    if (name == 'applyVolume' && extras != null) {
      final v = (extras['volume'] as num?)?.toDouble() ?? 1.0;
      await player.setVolume(v.clamp(0.0, maxEffectiveVolume));
      return null;
    }
    if (name == 'moveQueueItem' && extras != null) {
      await moveQueueItem(
        extras['oldIndex'] as int? ?? 0,
        extras['newIndex'] as int? ?? 0,
      );
      return null;
    }
    if (name == 'playSongs' && extras != null) {
      final raw = extras['songs'] as List;
      final songs = raw
          .map(
            (e) => Song(
              id: e['id'] as String,
              title: e['title'] as String,
              artist: e['artist'] as String,
              album: e['album'] as String?,
              path: e['path'] as String,
              durationMs: e['durationMs'] as int,
              artworkId: e['artworkId'] as int?,
            ),
          )
          .toList();
      final startAtMs = (extras['startAtMs'] as num?)?.toInt() ?? 0;
      await playSongs(
        songs,
        initialIndex: extras['index'] as int? ?? 0,
        autoplay: extras['autoplay'] as bool? ?? true,
        startAt: startAtMs > 0 ? Duration(milliseconds: startAtMs) : null,
      );
      return null;
    }
    return super.customAction(name, extras);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: switch (event.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
      shuffleMode: _shuffleMode,
      repeatMode: _repeatMode,
    );
  }
}
