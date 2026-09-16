import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Volume balancer state, persisted in Hive.
///
/// - [masterVolume]: app volume multiplier (0…1, default 1). Always applied.
/// - [balancerEnabled]: when on, each song's personal trim is applied on
///   top of the master volume at track changes.
/// - [trims]: per-song gain offsets in dB (-12…+12, default 0).
///
/// Effective player volume = master × 10^(trim/20), clamped to 0…2.
/// Positive trims can clip hot masters — UI hints to prefer cutting loud
/// songs over boosting quiet ones.
const _boxName = 'flamora';
const _volumeKey = 'volume';

const double minTrimDb = -12;
const double maxTrimDb = 12;
const double maxEffectiveVolume = 2;

double dbToGain(double db) => math.pow(10, db / 20).toDouble();

final volumeSettingsProvider =
    NotifierProvider<VolumeSettingsNotifier, VolumeSettings>(
        VolumeSettingsNotifier.new);

class VolumeSettings {
  final double masterVolume;
  final bool balancerEnabled;
  final Map<String, double> trims;

  const VolumeSettings({
    required this.masterVolume,
    required this.balancerEnabled,
    required this.trims,
  });

  double trimFor(String songId) => trims[songId] ?? 0;

  /// Effective just_audio volume for [songId] (null = no song loaded).
  double effectiveFor(String? songId) {
    final trim =
        (balancerEnabled && songId != null) ? trimFor(songId) : 0.0;
    return (masterVolume * dbToGain(trim)).clamp(0.0, maxEffectiveVolume);
  }

  Map<String, dynamic> toMap() => {
        'master': masterVolume,
        'enabled': balancerEnabled,
        'trims': Map.of(trims),
      };

  factory VolumeSettings.fromMap(Map<String, dynamic> map) {
    final rawTrims = map['trims'];
    return VolumeSettings(
      masterVolume: ((map['master'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
      balancerEnabled: map['enabled'] == true,
      trims: rawTrims is Map
          ? {
              for (final e in rawTrims.entries)
                e.key.toString():
                    ((e.value as num?)?.toDouble() ?? 0.0).clamp(minTrimDb, maxTrimDb)
            }
          : const {},
    );
  }

  VolumeSettings copyWith({
    double? masterVolume,
    bool? balancerEnabled,
    Map<String, double>? trims,
  }) =>
      VolumeSettings(
        masterVolume: masterVolume ?? this.masterVolume,
        balancerEnabled: balancerEnabled ?? this.balancerEnabled,
        trims: trims ?? this.trims,
      );
}

class VolumeSettingsNotifier extends Notifier<VolumeSettings> {
  late final Box _box;

  @override
  VolumeSettings build() {
    _box = Hive.box(_boxName);
    final stored = _box.get(_volumeKey);
    if (stored is Map) {
      return VolumeSettings.fromMap(Map<String, dynamic>.from(stored));
    }
    return const VolumeSettings(
        masterVolume: 1, balancerEnabled: false, trims: {});
  }

  Future<void> _persist() => _box.put(_volumeKey, state.toMap());

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(balancerEnabled: value);
    await _persist();
  }

  Future<void> setMaster(double value) async {
    state = state.copyWith(masterVolume: value.clamp(0.0, 1.0));
    await _persist();
  }

  Future<void> setTrim(String songId, double db) async {
    final trims = Map.of(state.trims);
    final clamped = db.clamp(minTrimDb, maxTrimDb);
    if (clamped == 0) {
      trims.remove(songId);
    } else {
      trims[songId] = clamped;
    }
    state = state.copyWith(trims: trims);
    await _persist();
  }

  Future<void> clearTrim(String songId) async {
    if (!state.trims.containsKey(songId)) return;
    final trims = Map.of(state.trims)..remove(songId);
    state = state.copyWith(trims: trims);
    await _persist();
  }
}
