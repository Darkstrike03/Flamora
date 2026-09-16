import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Online/offline preference, persisted in Hive.
///
/// Currently a pure preference (the app is fully local) that future
/// network features — streaming, scrobbling, artwork fetch — will read
/// before doing any I/O. Defaults to online.
const _boxName = 'flamora';
const _onlineModeKey = 'onlineMode';

final onlineModeProvider =
    NotifierProvider<OnlineModeNotifier, bool>(OnlineModeNotifier.new);

class OnlineModeNotifier extends Notifier<bool> {
  late final Box _box;

  @override
  bool build() {
    _box = Hive.box(_boxName);
    return _box.get(_onlineModeKey, defaultValue: true) == true;
  }

  Future<void> setOnline(bool value) async {
    state = value;
    await _box.put(_onlineModeKey, value);
  }

  Future<void> toggle() => setOnline(!state);
}
