import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// User-picked music folders, persisted in Hive.
///
/// The box is opened in `main()` before `runApp`, so it is always
/// available here. The folder picker + scan pipeline read and write
/// through this notifier; the library query watches it and rescans
/// automatically on every change.
const _boxName = 'flamora';
const _foldersKey = 'musicFolders';

final foldersProvider =
    NotifierProvider<FoldersNotifier, List<String>>(FoldersNotifier.new);

class FoldersNotifier extends Notifier<List<String>> {
  late final Box _box;

  @override
  List<String> build() {
    _box = Hive.box(_boxName);
    final stored = _box.get(_foldersKey, defaultValue: const <String>[]);
    return (stored as List).map((e) => e.toString()).toList();
  }

  /// Adds a folder unless the same (normalized) path is already tracked.
  Future<void> addFolder(String path) async {
    final normalized = _normalize(path);
    if (state.any((f) => _normalize(f) == normalized)) return;
    state = [...state, path];
    await _box.put(_foldersKey, state);
  }

  Future<void> removeFolder(String path) async {
    state = state.where((f) => f != path).toList();
    await _box.put(_foldersKey, state);
  }

  static String _normalize(String path) {
    var p = path.replaceAll('\\', '/');
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    if (Platform.isAndroid) return p.toLowerCase();
    return p;
  }
}
