import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/song.dart';
import '../library/library_provider.dart';
import 'equalizer_repository.dart';
import 'flamora_audio_handler.dart';
import 'volume_repository.dart';

/// Single entry point the UI talks to. Hides the platform split:
///
/// - Android/iOS: handler runs in the background isolate; `AudioService.init`
///   returns a proxy whose streams and methods forward over the platform
///   channel, so UI code just uses the instance.
/// - Desktop: the same handler class runs in-process via just_audio.
///
/// Either way the widgets below expose identical streams, so screens stay
/// platform-agnostic. Initialization is lazy — the service starts on first
/// listen, never at app launch.
final playerServiceProvider =
    Provider<PlayerService>((ref) => PlayerService());

final playerQueueProvider = StreamProvider<List<MediaItem>>(
    (ref) => ref.watch(playerServiceProvider).queue);

final playerCurrentProvider = StreamProvider<MediaItem?>(
    (ref) => ref.watch(playerServiceProvider).current);

final playerStateProvider = StreamProvider<PlaybackState>(
    (ref) => ref.watch(playerServiceProvider).playbackState);

final playerPositionProvider = StreamProvider<Duration>(
    (ref) => ref.watch(playerServiceProvider).position);

/// Keeps player gain in sync with the current track + volume settings.
/// Watched once by AppShell (always mounted). Never initializes the
/// player itself — pushes only after first real use.
final volumeApplierProvider = Provider<void>((ref) {
  Future<void> push() async {
    final service = ref.read(playerServiceProvider);
    if (!service.isReady) return;
    final songId = ref.read(playerCurrentProvider).value?.id;
    final settings = ref.read(volumeSettingsProvider);
    await service.applyVolume(settings.effectiveFor(songId));
  }

  ref.listen(playerCurrentProvider, (_, _) => unawaited(push()));
  ref.listen(volumeSettingsProvider, (_, _) => unawaited(push()));
});

/// Pushes equalizer settings to the player (Android only; elsewhere the
/// handler no-ops). Watched alongside [volumeApplierProvider] by AppShell.
/// Listens to track changes too so settings land after every reload.
final equalizerApplierProvider = Provider<void>((ref) {
  Future<void> push() async {
    final service = ref.read(playerServiceProvider);
    if (!service.isReady) return;
    final settings = ref.read(equalizerSettingsProvider);
    await service.applyEqualizer(
      enabled: settings.enabled,
      gains: settings.effectiveGains(),
      freqs: eqReferenceFreqs,
    );
  }

  ref.listen(equalizerSettingsProvider, (_, _) => unawaited(push()));
  ref.listen(playerCurrentProvider, (_, _) => unawaited(push()));
});

class PlayerService {
  FlamoraAudioHandler? _handler;
  Future<FlamoraAudioHandler>? _initFuture;
  bool _remote = false;

  /// True once the handler was initialized (first play). The volume
  /// applier uses this to avoid eagerly starting audio at app launch.
  bool get isReady => _initFuture != null;

  Future<FlamoraAudioHandler> ensureInit() =>
      _initFuture ??= _init();

  Future<FlamoraAudioHandler> _init() async {
    if (Platform.isAndroid || Platform.isIOS) {
      _remote = true;
      _handler = await AudioService.init(
        builder: FlamoraAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'dev.flamora.audio',
          androidNotificationChannelName: 'Flamora playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } else {
      _handler = FlamoraAudioHandler();
    }
    return _handler!;
  }

  Stream<List<MediaItem>> get queue async* {
    yield* (await ensureInit()).queue;
  }

  Stream<MediaItem?> get current async* {
    yield* (await ensureInit()).mediaItem;
  }

  Stream<PlaybackState> get playbackState async* {
    yield* (await ensureInit()).playbackState;
  }

  Stream<Duration> get position async* {
    final handler = await ensureInit();
    // The handler proxy exposes no position stream; the framework helper
    // interpolates between playback-state updates on mobile.
    yield* _remote ? AudioService.position : handler.player.positionStream;
  }

  Future<void> playSongs(List<Song> songs,
      {int initialIndex = 0, bool autoplay = true, Duration? startAt}) async {
    // User-initiated plays (not session restore) get one shot at the
    // notification permission for the playback notification.
    if (autoplay) unawaited(ensureNotificationAccess());
    final handler = await ensureInit();
    if (_remote) {
      await handler.customAction('playSongs', {
        'index': initialIndex,
        'autoplay': autoplay,
        'startAtMs': startAt?.inMilliseconds ?? 0,
        'songs': [
          for (final s in songs)
            {
              'id': s.id,
              'title': s.title,
              'artist': s.artist,
              'album': s.album,
              'path': s.path,
              'durationMs': s.durationMs,
              'artworkId': s.artworkId,
            },
        ],
      });
    } else {
      await _handler!.playSongs(songs,
          initialIndex: initialIndex, autoplay: autoplay, startAt: startAt);
    }
  }

  Future<void> play() async => (await ensureInit()).play();

  Future<void> pause() async => (await ensureInit()).pause();

  Future<void> seekTo(Duration position) async =>
      (await ensureInit()).seek(position);

  Future<void> skipToNext() async => (await ensureInit()).skipToNext();

  Future<void> skipToPrevious() async =>
      (await ensureInit()).skipToPrevious();

  Future<void> skipToQueueItem(int index) async =>
      (await ensureInit()).skipToQueueItem(index);

  /// Standard QueueHandler methods forward over the platform channel on
  /// mobile and run in-process on desktop — same pattern as skipToQueueItem.
  /// (moveQueueItem is NOT an audio_service protocol method, so it goes
  /// through customAction on mobile like playSongs does.)
  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    final handler = await ensureInit();
    if (_remote) {
      await handler.customAction('moveQueueItem', {
        'oldIndex': oldIndex,
        'newIndex': newIndex,
      });
    } else {
      await handler.moveQueueItem(oldIndex, newIndex);
    }
  }

  Future<void> removeQueueItemAt(int index) async =>
      (await ensureInit()).removeQueueItemAt(index);

  Future<void> setShuffle(bool enabled) async =>
      (await ensureInit()).setShuffleMode(enabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none);

  Future<void> setRepeatMode(AudioServiceRepeatMode mode) async =>
      (await ensureInit()).setRepeatMode(mode);

  /// Sets the just_audio gain directly. Volume isn't an audio_service
  /// protocol method, so mobile goes through customAction (like playSongs)
  /// and desktop calls the player directly.
  Future<void> applyVolume(double volume) async {
    final handler = await ensureInit();
    final v = volume.clamp(0.0, maxEffectiveVolume);
    if (_remote) {
      await handler.customAction('applyVolume', {'volume': v});
    } else {
      await handler.player.setVolume(v);
    }
  }

  /// Pushes equalizer settings (Android only — the handler no-ops
  /// elsewhere). Same remote/local routing as [applyVolume].
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> gains,
    required List<double> freqs,
  }) async {
    final handler = await ensureInit();
    if (_remote) {
      await handler.customAction('applyEqualizer', {
        'enabled': enabled,
        'gains': gains,
        'freqs': freqs,
      });
    } else {
      await handler.applyEqualizer(
          enabled: enabled, gains: gains, freqs: freqs);
    }
  }

  /// Device band snapshot for EQ sliders. Empty off-Android or idle.
  Future<List<EqBand>> equalizerBands() async {
    final handler = await ensureInit();
    final raw = _remote
        ? await handler.customAction('getEqualizerBands')
        : await handler.equalizerBands();
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map)
          EqBand(
            index: (e['index'] as num?)?.toInt() ?? 0,
            centerHz: (e['centerHz'] as num?)?.toDouble() ?? 0,
            gain: (e['gain'] as num?)?.toDouble() ?? 0,
            minDb: (e['minDb'] as num?)?.toDouble() ?? -15,
            maxDb: (e['maxDb'] as num?)?.toDouble() ?? 15,
          ),
    ];
  }
}
