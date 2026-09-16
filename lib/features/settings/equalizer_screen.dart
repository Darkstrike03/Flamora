import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/screen_header.dart';
import '../player/equalizer_repository.dart';
import '../player/player_service.dart';

/// Android-only equalizer: enable switch, preset chips, and native
/// device band sliders. Off-Android this screen is unreachable (the
/// Settings card hides it); the handler no-ops every EQ call elsewhere.
///
/// Presets apply immediately when audio is loaded, and on next play
/// otherwise. Hand-tuned sliders flip to the Custom preset.
class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  Future<List<EqBand>>? _bands;

  /// Live slider positions shadowing device bands during a session.
  final Map<int, double> _live = {};

  @override
  void initState() {
    super.initState();
    _refreshBands();
  }

  void _refreshBands() {
    setState(() {
      _live.clear();
      _bands = ref.read(playerServiceProvider).equalizerBands();
    });
  }

  Future<void> _pickPreset(String id) async {
    await ref.read(equalizerSettingsProvider.notifier).setPreset(id);
    if (mounted) _refreshBands(); // sliders reflect the pushed gains
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(equalizerSettingsProvider);
    final notifier = ref.read(equalizerSettingsProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenHeader(
              leading: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: 'Equalizer',
              subtitle: settings.enabled
                  ? eqPresetName(settings.presetId)
                  : 'Off',
              actions: [
                IconButton(
                  tooltip: 'Reload bands',
                  onPressed: _refreshBands,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Enable equalizer',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Switch(
                    value: settings.enabled,
                    onChanged: (v) => notifier.setEnabled(v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final preset in eqPresets)
                    ChoiceChip(
                      label: Text(preset.name),
                      selected: settings.presetId == preset.id,
                      onSelected: (_) => _pickPreset(preset.id),
                    ),
                  if (settings.presetId == customPresetId)
                    ChoiceChip(
                      label: const Text('Custom'),
                      selected: true,
                      onSelected: (_) {},
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<EqBand>>(
                future: _bands,
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  final bands = snapshot.data ?? const <EqBand>[];
                  if (bands.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Start playback to tune individual bands — presets apply on next play.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    itemCount: bands.length,
                    itemBuilder: (context, i) {
                      final band = bands[i];
                      final value =
                          _live[band.index] ?? band.gain;
                      return Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              _fmtHz(band.centerHz),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              min: band.minDb,
                              max: band.maxDb,
                              value: value.clamp(band.minDb, band.maxDb),
                              label: '${_fmtDb(value)} dB',
                              onChanged: (v) {
                                setState(() => _live[band.index] = v);
                                notifier.setCustomGain(
                                    band.centerHz, v);
                              },
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: Text(
                              '${_fmtDb(value)} dB',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtHz(double hz) => hz >= 1000
    ? '${(hz / 1000).toStringAsFixed(1).replaceAll('.0', '')} kHz'
    : '${hz.round()} Hz';

String _fmtDb(double v) =>
    '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}';
