import 'package:face_att/models/user.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveBoxes {
  HiveBoxes._();
  static const usersBox = "users_box";
  static const settingsBox = "settings_box";
  static Box get _box => Hive.box(usersBox);
  static Box get settings => Hive.box(settingsBox);

  static Future<void> initialize() async {
    await Hive.openBox(usersBox);
    await Hive.openBox(settingsBox);
  }

  static Future<void> clearAllBox() async {
    await _box.clear();
    await settings.clear();
  }
}

class LocalDB {
  static bool get isBoxOpen => Hive.isBoxOpen(HiveBoxes.usersBox);
  static Box? get _boxOrNull => isBoxOpen ? HiveBoxes._box : null;

  static bool get hasUsers => getUsers().isNotEmpty;

  /// All registered users — skips malformed entries
  static List<User> getUsers() {
    final box = _boxOrNull;
    if (box == null) return [];
    final result = <User>[];
    for (final v in box.values) {
      try {
        if (v is Map) {
          final user = User.fromMap(Map.from(v));
          if (user.registerNumber.isNotEmpty) {
            result.add(user);
          }
        }
      } catch (e) {
        debugPrint("LocalDB.getUsers warning: $e");
      }
    }
    return result;
  }

  /// All registered users with valid 512-dimensional ArcFace embeddings
  static List<User> getValidEnrolledUsers() {
    return getUsers().where((u) => u.array != null && u.array!.length == 512).toList();
  }

  /// Single user by registerNumber
  static User? getUser(String registerNumber) {
    final box = _boxOrNull;
    if (box == null) return null;
    final raw = box.get(registerNumber);
    if (raw == null) return null;
    try {
      return User.fromMap(Map.from(raw as Map));
    } catch (e) {
      debugPrint("LocalDB.getUser($registerNumber) warning: $e");
      return null;
    }
  }

  /// Save or update a user (keyed by user.registerNumber)
  static Future<void> saveUser(User user) async {
    final box = _boxOrNull ?? await Hive.openBox(HiveBoxes.usersBox);
    await box.put(user.registerNumber, user.toMap());
  }

  /// Delete a user by registerNumber
  static Future<void> deleteUser(String registerNumber) async {
    final box = _boxOrNull;
    if (box != null) {
      await box.delete(registerNumber);
    }
  }
}

