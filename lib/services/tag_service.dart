import 'package:hive_flutter/hive_flutter.dart';
import '../models/note_models.dart';

class TagService {
  static const String _boxName = 'tags_box';
  late Box<Tag> _box;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Register adapter if not already registered
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(TagAdapter());
    }

    _box = await Hive.openBox<Tag>(_boxName);
    _isInitialized = true;
  }

  List<Tag> getTags() {
    if (!_isInitialized) return [];
    return _box.values.toList();
  }

  Future<Tag> createTag(String name, String color) async {
    if (_box.values.any((t) => t.name == name)) {
      return _box.values.firstWhere((t) => t.name == name);
    }

    final tag = Tag(name: name, color: color);
    await _box.add(tag);
    return tag;
  }

  Future<void> renameTag(String oldName, String newName) async {
    final tag = _box.values.where((t) => t.name == oldName).firstOrNull;
    if (tag != null) {
      tag.name = newName;
      await tag.save();
    }
  }

  Future<void> setTagColor(String name, String color) async {
    final tag = _box.values.where((t) => t.name == name).firstOrNull;
    if (tag != null) {
      tag.color = color;
      await tag.save();
    }
  }

  Future<void> deleteTag(String name) async {
    final tag = _box.values.where((t) => t.name == name).firstOrNull;
    if (tag != null) {
      await tag.delete();
    }
  }
}
