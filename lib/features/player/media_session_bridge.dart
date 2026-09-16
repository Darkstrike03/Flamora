import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter_media_session/flutter_media_session.dart' as ms;
import 'package:flutter_media_session/flutter_media_session_platform_interface.dart'
    as msp;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_service.dart';

/// Windows SMTC bridge (volume flyout, lock screen, hardware media keys).
/// No-op off-Windows — Android/iOS/macOS keep audio_service.
///
/// Pushes our MediaItem/playback state to the OS and routes OS buttons
/// back through [PlayerService] (which owns shuffle order and queue, so
/// titles stay in sync). Watched once by AppShell.
final mediaSessionBridgeProvider = Provider<void>((ref) {
  if (!Platform.isWindows) return;
  final platform = msp.FlutterMediaSessionPlatform.instance;
  var activated = false;

  Future<void> ensureActive() async {
    if (activated) return;
    activated = true;
    try {
      await ms.FlutterMediaSession().activate();
    } catch (_) {
      activated = false;
    }
  }

  Future<void> pushMetadata() async {
    final current = ref.read(playerCurrentProvider).value;
    if (current == null) return;
    await ensureActive();
    try {
      await platform.updateMetadata(ms.MediaMetadata(
        title: current.title,
        artist: current.artist,
        album: current.album,
        duration: current.duration ?? Duration.zero,
      ));
    } catch (_) {}
  }

  Future<void> pushState() async {
    final state = ref.read(playerStateProvider).value;
    if (state == null) return;
    await ensureActive();
    final position = ref.read(playerPositionProvider).value ?? Duration.zero;
    try {
      await platform.updatePlaybackState(ms.PlaybackState(
        status: _statusOf(state),
        position: position,
        speed: state.speed,
        repeatMode: _repeatOf(state.repeatMode),
        shuffleModeEnabled:
            state.shuffleMode == AudioServiceShuffleMode.all,
      ));
      await platform.updateAvailableActions({
        ms.MediaAction.play,
        ms.MediaAction.pause,
        ms.MediaAction.seekTo,
        ms.MediaAction.stop,
        ms.MediaAction.skipToNext,
        ms.MediaAction.skipToPrevious,
      });
    } catch (_) {}
  }

  ref.listen(playerCurrentProvider, (_, _) {
    pushMetadata();
    pushState();
  });
  ref.listen(playerStateProvider, (_, _) => pushState());
  ref.listen(playerPositionProvider, (_, _) => pushState());

  final sub = platform.onMediaAction.listen((action) async {
    final service = ref.read(playerServiceProvider);
    try {
      switch (action.name) {
        case 'play':
          await service.play();
        case 'pause':
          await service.pause();
        case 'stop':
          await service.pause();
        case 'seekTo':
          final pos = action.seekPosition;
          if (pos != null) await service.seekTo(pos);
        case 'skipToNext':
          await service.skipToNext();
        case 'skipToPrevious':
          await service.skipToPrevious();
      }
    } catch (_) {}
  });
  ref.onDispose(() => unawaited(sub.cancel()));
});

ms.PlaybackStatus _statusOf(PlaybackState state) {
  switch (state.processingState) {
    case AudioProcessingState.loading:
    case AudioProcessingState.buffering:
      return ms.PlaybackStatus.buffering;
    case AudioProcessingState.completed:
      return ms.PlaybackStatus.ended;
    case AudioProcessingState.ready:
      return state.playing ? ms.PlaybackStatus.playing : ms.PlaybackStatus.paused;
    default:
      return ms.PlaybackStatus.idle;
  }
}

ms.MediaRepeatMode _repeatOf(AudioServiceRepeatMode mode) {
  switch (mode) {
    case AudioServiceRepeatMode.one:
      return ms.MediaRepeatMode.one;
    case AudioServiceRepeatMode.all:
    case AudioServiceRepeatMode.group:
      return ms.MediaRepeatMode.all;
    case AudioServiceRepeatMode.none:
      return ms.MediaRepeatMode.none;
  }
}
