class User {
  static const String nameKey = "user_name";
  static const String emailKey = "user_email";
  static const String phoneKey = "user_phone";
  static const String arrayKey = "user_array";

  String? name;
  String? email;
  String? phone;
  List? array;

  User({this.name, this.email, this.phone, this.array});

  Map<String, dynamic> toJson() => {
        nameKey: name,
        emailKey: email,
        phoneKey: phone,
        arrayKey: array,
      };
}
