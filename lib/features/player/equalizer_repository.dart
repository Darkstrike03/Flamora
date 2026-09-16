import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Equalizer state, persisted in Hive.
///
/// Android-only for now: it drives just_audio's native `AndroidEqualizer`,
/// which has no counterpart in the Windows (mpv) backend. The UI hides
/// the controls off-Android; the stored settings simply wait for a
/// platform that supports them.
///
/// Gains are authored against 5 reference frequencies. At apply time they
/// are mapped onto the device's actual bands by nearest center frequency,
/// so presets survive across devices with different band layouts.
const _boxName = 'flamora';
const _equalizerKey = 'equalizer';

/// Reference frequencies (Hz) presets are authored against.
const eqReferenceFreqs = [60.0, 230.0, 910.0, 3600.0, 14000.0];

class EqPreset {
  final String id;
  final String name;

  /// Gain per reference frequency, in dB.
  final List<double> gains;

  const EqPreset({
    required this.id,
    required this.name,
    required this.gains,
  });
}

const eqPresets = [
  EqPreset(id: 'flat', name: 'Flat', gains: [0, 0, 0, 0, 0]),
  EqPreset(id: 'bass', name: 'Bass Boost', gains: [6, 4, 0, 0, 1]),
  EqPreset(id: 'treble', name: 'Treble Boost', gains: [-1, 0, 2, 4, 6]),
  EqPreset(id: 'vocal', name: 'Vocal', gains: [-2, 0, 3, 4, 1]),
  EqPreset(id: 'rock', name: 'Rock', gains: [4, 2, -2, 2, 4]),
  EqPreset(id: 'jazz', name: 'Jazz', gains: [3, 2, 0, 2, 4]),
  EqPreset(id: 'classical', name: 'Classical', gains: [4, 3, 1, 3, 4]),
  EqPreset(id: 'pop', name: 'Pop', gains: [2, 4, 3, 1, 0]),
];

const customPresetId = 'custom';

/// Display name for a preset id (falls back to Custom).
String eqPresetName(String id) {
  for (final p in eqPresets) {
    if (p.id == id) return p.name;
  }
  return 'Custom';
}

/// A device band reading for UI sliders.
class EqBand {
  final int index;
  final double centerHz;
  final double gain;
  final double minDb;
  final double maxDb;

  const EqBand({
    required this.index,
    required this.centerHz,
    required this.gain,
    required this.minDb,
    required this.maxDb,
  });
}

class EqualizerSettings {
  final bool enabled;
  final String presetId;

  /// Custom gains by *reference* frequency index (0…4 into
  /// [eqReferenceFreqs]). Device bands resolve through these, so customs
  /// survive reloads and devices with different band layouts.
  final Map<int, double> customGains;

  const EqualizerSettings({
    required this.enabled,
    required this.presetId,
    required this.customGains,
  });

  /// Effective reference-frequency gains for [presetId]/[customGains].
  List<double> effectiveGains() {
    if (presetId != customPresetId) {
      final preset = eqPresets.where((p) => p.id == presetId).toList();
      return List.of((preset.isEmpty ? eqPresets.first : preset.first).gains);
    }
    return [
      for (var i = 0; i < eqReferenceFreqs.length; i++) customGains[i] ?? 0,
    ];
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'preset': presetId,
        'custom': {for (final e in customGains.entries) '${e.key}': e.value},
      };

  factory EqualizerSettings.fromMap(Map<String, dynamic> map) {
    final rawCustom = map['custom'];
    final custom = <int, double>{};
    if (rawCustom is Map) {
      for (final e in rawCustom.entries) {
        final key = int.tryParse(e.key.toString());
        if (key != null) {
          custom[key] = (e.value as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    return EqualizerSettings(
      enabled: map['enabled'] == true,
      presetId: map['preset'] as String? ?? 'flat',
      customGains: custom,
    );
  }

  EqualizerSettings copyWith({
    bool? enabled,
    String? presetId,
    Map<int, double>? customGains,
  }) =>
      EqualizerSettings(
        enabled: enabled ?? this.enabled,
        presetId: presetId ?? this.presetId,
        customGains: customGains ?? this.customGains,
      );
}

final equalizerSettingsProvider =
    NotifierProvider<EqualizerSettingsNotifier, EqualizerSettings>(
        EqualizerSettingsNotifier.new);

class EqualizerSettingsNotifier extends Notifier<EqualizerSettings> {
  late final Box _box;

  @override
  EqualizerSettings build() {
    _box = Hive.box(_boxName);
    final stored = _box.get(_equalizerKey);
    if (stored is Map) {
      return EqualizerSettings.fromMap(Map<String, dynamic>.from(stored));
    }
    return const EqualizerSettings(
        enabled: false, presetId: 'flat', customGains: {});
  }

  Future<void> _persist() => _box.put(_equalizerKey, state.toMap());

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    await _persist();
  }

  Future<void> setPreset(String id) async {
    state = state.copyWith(presetId: id);
    await _persist();
  }

  /// Records a hand-tuned device band (mapped to its nearest reference
  /// slot) and flips to the custom preset.
  Future<void> setCustomGain(double centerHz, double gain) async {
    final custom = Map.of(state.customGains)
      ..[nearestRefIndex(centerHz)] = gain;
    state = state.copyWith(presetId: customPresetId, customGains: custom);
    await _persist();
  }

  Future<void> clearCustom() async {
    state = state.copyWith(presetId: 'flat', customGains: const {});
    await _persist();
  }
}

/// Index into [eqReferenceFreqs] nearest to [centerHz]. Shared by the
/// settings store (device band → reference slot) and the player (device
/// band ← reference slot), so both directions agree.
int nearestRefIndex(double centerHz) {
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < eqReferenceFreqs.length; i++) {
    final dist = (eqReferenceFreqs[i] - centerHz).abs();
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
    }
  }
  return best;
}
