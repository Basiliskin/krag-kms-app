import 'package:hive_flutter/hive_flutter.dart';

class PersistenceService {
  static const String _boxName = 'krag_persistence';

  /// Saves a value to local storage.
  /// [value] must be a type supported by Hive (primitives, Lists, Maps, HiveObjects).
  static Future<void> save(String key, dynamic value) async {
    final box = await Hive.openBox(_boxName);
    await box.put(key, value);
  }

  /// Loads a value from local storage.
  static Future<dynamic> load(String key) async {
    final box = await Hive.openBox(_boxName);
    return box.get(key);
  }

  /// Deletes a value from local storage.
  static Future<void> delete(String key) async {
    final box = await Hive.openBox(_boxName);
    await box.delete(key);
  }

  /// Clears all data in the persistence box.
  static Future<void> clear() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
  }
}
