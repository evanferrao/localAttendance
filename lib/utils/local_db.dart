import 'package:face_att/models/user.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveBoxes {
  HiveBoxes._();

  static const userBox = "user_box";

  static Box get _box => Hive.box(userBox);

  static Future<void> initialize() async {
    await Hive.openBox(userBox);
  }

  static Future<void> clearAllBox() async {
    await _box.clear();
  }
}

class LocalDB {
  static Box get _box => HiveBoxes._box;

  static bool get hasUser {
    final name = _box.get(User.nameKey);
    return name != null && (name as String).isNotEmpty;
  }

  static User getUser() {
    return User(
      name: _box.get(User.nameKey) as String?,
      array: _box.get(User.arrayKey) != null ? List.from(_box.get(User.arrayKey)) : null,
    );
  }

  static Future<void> setUserDetails(User user) async {
    await _box.put(User.nameKey, user.name);
    await _box.put(User.arrayKey, user.array);
  }
}
