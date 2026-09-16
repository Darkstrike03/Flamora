import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/folders_repository.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/widgets/neu_card.dart';
import '../../core/widgets/screen_header.dart';
import '../player/equalizer_repository.dart';
import '../player/volume_repository.dart';
import 'equalizer_screen.dart';

/// Settings: Appearance, Equalizer, Folders, Check for updates,
/// What's new, About.
///
/// Portrait is a single list; wider screens flow the same cards into
/// a masonry-style column layout (2–3 columns, round-robin).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _picking = false;

  void _soon(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final cards = <Widget>[
      _appearanceCard(mode),
      _equalizerCard(),
      _balancerCard(),
      _foldersCard(),
      _updatesCard(),
      _whatsNewCard(),
      _aboutCard(),
    ];

    return Column(
      children: [
        const ScreenHeader(
          title: 'Settings',
          subtitle: 'v1.0.0 · local & private',
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              // Single list on phones; masonry columns once a column
              // stays phone-width (~320px+) so nothing squeezes.
              if (w < 700) {
                return ListView.separated(
                  padding:
                      const EdgeInsets.fromLTRB(20, 12, 20, 110),
                  itemCount: cards.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 16),
                  itemBuilder: (_, i) => cards[i],
                );
              }
              final cols = w >= 1100 ? 3 : 2;
              final columns = List.generate(
                cols,
                (c) => <Widget>[
                  for (var i = c; i < cards.length; i += cols) cards[i],
                ],
              );
              return SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(20, 12, 20, 110),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 1100),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var c = 0; c < cols; c++) ...[
                          if (c > 0) const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                for (var k = 0;
                                    k < columns[c].length;
                                    k++) ...[
                                  if (k > 0)
                                    const SizedBox(height: 16),
                                  columns[c][k],
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cardTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(title,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _appearanceCard(ThemeMode mode) {
    // Portrait phones get icon-only segments (room is tight);
    // wider layouts keep icon + label.
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.palette_outlined, 'Appearance'),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.settings_suggest_outlined),
                  label: portrait ? null : const Text('Auto')),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: portrait ? null : const Text('Light')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  label: portrait ? null : const Text('Dark')),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).set(s.first),
          ),
        ],
      ),
    );
  }

  Widget _equalizerCard() {
    // No EQ backend off-Android (mpv path exposes none) — show a quiet
    // note instead of dead controls.
    if (!Platform.isAndroid) {
      return NeuCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(Icons.tune_rounded, 'Equalizer'),
            const SizedBox(height: 6),
            const Text(
                'Equalizer needs Android — desktop support lands with a future engine update.'),
          ],
        ),
      );
    }
    final settings = ref.watch(equalizerSettingsProvider);
    final stateText = settings.enabled
        ? '${eqPresetName(settings.presetId)} — tap to tune.'
        : 'Off — tap to open.';
    return NeuCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EqualizerScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.tune_rounded, 'Equalizer'),
          const SizedBox(height: 6),
          Text(stateText),
        ],
      ),
    );
  }

  Widget _balancerCard() {
    final settings = ref.watch(volumeSettingsProvider);
    final notifier = ref.read(volumeSettingsProvider.notifier);
    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volume_up_outlined,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Volume Balancer',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: settings.balancerEnabled,
                onChanged: (v) => notifier.setEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
              'Evens out loud and quiet songs. Give a song its own fix from its More menu — cutting loud songs is safer than boosting quiet ones.'),
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, size: 20),
              Expanded(
                child: Slider(
                  value: settings.masterVolume,
                  onChanged: (v) => notifier.setMaster(v),
                ),
              ),
              const Icon(Icons.volume_up_rounded, size: 20),
              const SizedBox(width: 4),
              SizedBox(
                width: 44,
                child:
                    Text('${(settings.masterVolume * 100).round()}%'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Pick a music folder',
      );
      if (path == null) return; // user cancelled
      await ref.read(foldersProvider.notifier).addFolder(path);
      if (!mounted) return;
      _soon('Folder added — library rescanned.');
    } catch (_) {
      if (!mounted) return;
      _soon('Could not open the folder picker.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _foldersCard() {
    final folders = ref.watch(foldersProvider);
    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.folder_outlined, 'Music folders'),
          const SizedBox(height: 6),
          const Text(
              'Add folders and Flamora fetches every song inside.'),
          const SizedBox(height: 12),
          if (folders.isEmpty)
            Text(
              'No folders added yet.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final path in folders)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(
                      tooltip: 'Remove folder',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => ref
                          .read(foldersProvider.notifier)
                          .removeFolder(path),
                      icon:
                          const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          FilledButton.tonalIcon(
            onPressed: _picking ? null : _pickFolder,
            icon: _picking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
            label: const Text('Add folders'),
          ),
        ],
      ),
    );
  }

  Widget _updatesCard() {
    return NeuCard(
      onTap: () => _soon("You're up to date — Flamora v1.0.0."),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.system_update_rounded, 'Check for updates'),
          const SizedBox(height: 6),
          const Text('Flamora v1.0.0. Tap to check.'),
        ],
      ),
    );
  }

  Widget _whatsNewCard() {
    const notes = [
      'Two-pane desktop player with inline queue',
      'Library with Songs + Playlists tabs',
      'Per-screen headers across the app',
    ];
    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.new_releases_outlined, "What's new"),
          const SizedBox(height: 8),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return NeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/branding/appicon.png',
                  width: 36,
                  height: 36,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.music_note_outlined),
                ),
              ),
              const SizedBox(width: 10),
              const Text('About Flamora',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
              'A beautiful local music player. Fully offline — your files never leave the device.'),
          const SizedBox(height: 6),
          const Text('Coming later — v1 stays fully local and private.'),
        ],
      ),
    );
  }
}
