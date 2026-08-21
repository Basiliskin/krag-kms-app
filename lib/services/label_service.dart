import 'package:hive_flutter/hive_flutter.dart';

class LabelService {
  static const String _boxName = 'labels_box';
  late Box<String> _box;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _box = await Hive.openBox<String>(_boxName);
    _isInitialized = true;
  }

  List<String> getLabels() {
    if (!_isInitialized) return [];
    final labels = _box.values.toList();
    labels.sort();
    return labels;
  }

  Future<void> addLabel(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    if (!_box.values.contains(trimmed)) {
      await _box.add(trimmed);
    }
  }

  Future<void> removeLabel(String name) async {
    final key = _box.keys.firstWhere(
      (k) => _box.get(k) == name,
      orElse: () => null,
    );

    if (key != null) {
      await _box.delete(key);
    }
  }

  bool hasLabel(String name) {
    return _box.values.contains(name);
  }

  Future<void> initializeFromNotes(Map<String, dynamic> notes) async {
    // Logic to scan notes and populate labels if they don't exist
    // This mimics the TS behavior of rebuilding the label list from notes
    final allLabels = <String>{};
    for (var note in notes.values) {
      if (note['labels'] != null) {
        for (var label in note['labels']) {
          allLabels.add(label as String);
        }
      }
    }

    for (var label in allLabels) {
      await addLabel(label);
    }
  }
}
