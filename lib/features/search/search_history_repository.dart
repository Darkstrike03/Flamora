import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Recent search queries, persisted in Hive. Most-recent-first, capped,
/// case-insensitive dedupe. Recorded on keyboard submit (typing alone
/// doesn't save).
const _boxName = 'flamora';
const _searchHistoryKey = 'searchHistory';
const maxSearchHistory = 8;

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
        SearchHistoryNotifier.new);

class SearchHistoryNotifier extends Notifier<List<String>> {
  late final Box _box;

  @override
  List<String> build() {
    _box = Hive.box(_boxName);
    final stored = _box.get(_searchHistoryKey, defaultValue: const <String>[]);
    return (stored as List).map((e) => e.toString()).toList();
  }

  Future<void> _persist() => _box.put(_searchHistoryKey, state);

  Future<void> record(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final needle = trimmed.toLowerCase();
    state = [
      trimmed,
      for (final q in state)
        if (q.toLowerCase() != needle) q,
    ].take(maxSearchHistory).toList();
    await _persist();
  }

  Future<void> remove(String query) async {
    final needle = query.trim().toLowerCase();
    state = state.where((q) => q.toLowerCase() != needle).toList();
    await _persist();
  }

  Future<void> clear() async {
    if (state.isEmpty) return;
    state = const [];
    await _persist();
  }
}
