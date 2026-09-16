# Flamora

A beautiful, fully offline local music player built with Flutter — Material 3 with a Neumorphic soul. Your files never leave the device.

## Features

- **Folder-based library** — pick music folders in Settings; Android reads MediaStore, Windows scans files with embedded tags (title, artist, album, duration)
- **Songs + Playlists tabs** — user playlists (create, rename, delete, reorder) plus automatic folder playlists, no setup needed
- **Queue** — play-order list with drag-to-reorder, swipe-to-remove, Up Next strip, auto-scroll to the current track; manual reorder takes over shuffle/repeat
- **Playback** — play/pause/seek/skip, shuffle (handler-owned, titles always in sync), repeat none/all/one, gapless album flow
- **Volume Balancer** — per-song dB trims (−12…+12) plus master volume, applied automatically at track changes
- **Equalizer** (Android) — native 5-band EQ with 8 presets + custom tuning
- **Search** — live title/artist search with recent-search pills
- **Session restore** — queue, track, and position reload paused on next launch
- **System integration** — Android playback notification (+ lockscreen), Windows SMTC volume-flyout + hardware media keys
- **Responsive everywhere** — portrait phone, medium, and wide two-pane desktop layouts with floating nav

## Platform status

| Platform | Status |
| -------- | ------ |
| Android  | ✅ Supported (API 21+ via MediaStore) |
| Windows  | ✅ Supported (mpv backend via `just_audio_media_kit`) |
| iOS / macOS | 🧱 Scaffold only, untested |
| Linux    | ❌ Not started |

## Tech stack

- Flutter 3.38 · Dart 3.10 · Riverpod · Hive (local storage) · `just_audio` + `audio_service`
- Windows audio: `just_audio_media_kit` + `media_kit_libs_windows_audio`; Windows SMTC: `flutter_media_session`
- Tags on desktop: `audiotags`; folder picking: `file_picker`
- `on_audio_query` is consumed via the [rozpo fork](https://github.com/rozpo/on_audio_query) (adds the AGP 8 `namespace` upstream lacks); `permission_handler` is pinned to v12 (v13's Android impl requires AGP 9, this project is on AGP 8)

## Getting started

Prerequisites: Flutter 3.38.x, Java 17, and (for Android) the Android SDK.

```bash
flutter pub get
flutter run -d windows    # desktop
flutter run               # Android device/emulator
```

Useful checks:

```bash
flutter analyze
flutter test
```

## Building distributables

```bash
# Android: one APK per ABI (arm64-v8a, armeabi-v7a, x86_64)
flutter build apk --release --split-per-abi

# Windows: Release folder, then the Inno Setup installer (see below)
flutter build windows --release
```

Tagged releases (`v*`) are built by CI (`.github/workflows/release.yml`): split APKs + a Windows `Flamora-Setup-<version>.exe` attached to the GitHub Release. Release flow:

```bash
# 1. bump `version:` in pubspec.yaml, commit
# 2. tag and push
git tag v1.0.0
git push origin v1.0.0
```

> **Signing note:** release builds currently sign with debug keys (see the TODO in `android/app/build.gradle.kts`), so CI artifacts are testing-grade, not store-ready. Proper release signing is on the roadmap.

## Permissions (Android)

| Permission | Why |
| ---------- | --- |
| `READ_MEDIA_AUDIO` (13+) / `READ_EXTERNAL_STORAGE` (≤ 32) | Read your music files |
| `POST_NOTIFICATIONS` (13+) | Playback notification controls |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Background playback |
| `WAKE_LOCK` | Keep CPU awake during playback |

No accounts, no analytics, no network calls for playback — everything stays on-device.

## Project layout

```
lib/
  main.dart                  # App shell, adaptive nav, global watchers
  core/                      # Theme, neumorphic widgets, storage, connectivity pref
  features/
    library/                 # Songs/playlists providers, Hive repos, detail + sheets
    player/                  # Audio handler, service, volume/EQ/session/SMTC bridges
    queue/                   # Queue panel + drawer
    search/                  # Search + history
    settings/                # Settings cards, equalizer screen
test/                        # Widget tests
android/ windows/ ios/       # Platform runners
windows/installer/           # Inno Setup script
.github/workflows/           # CI + release pipelines
```

## Roadmap

- Android tap-to-play hardening across OEMs (content-URI path in place)
- Real cover art everywhere (MediaStore + embedded pictures)
- Sleep timer, favorites + auto-playlists, save-queue-as-playlist
- Lyrics, playback speed, tag editor, stats
- Release signing, MSIX packaging, green test suite
- Equalizer on desktop (needs engine with DSP support)

## License

Apache License 2.0 — see [LICENSE](LICENSE).
