import 'package:face_att/models/user.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveBoxes {
  HiveBoxes._();

  static const userDetails = "user_details";

  static Box userDetailsBox() => Hive.box<Map>(userDetails);

  static Future<void> initialize() async {
    await Hive.openBox<Map>(userDetails);
  }

  static Future<void> clearAllBox() async {
    await userDetailsBox().clear();
  }
}

class LocalDB {
  static User getUser() => User.fromJson(HiveBoxes.userDetailsBox().toMap());

  static String getUserName() => HiveBoxes.userDetailsBox().toMap()[User.nameKey];

  static String getUserArray() => HiveBoxes.userDetailsBox().toMap()[User.arrayKey];

  static setUserDetails(User user) => HiveBoxes.userDetailsBox().putAll(user.toJson());
}
