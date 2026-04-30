class User {
  final String id; // unique key in Hive
  String? name;
  String? email;
  String? phone;
  List? array;

  User({
    required this.id,
    this.name,
    this.email,
    this.phone,
    this.array,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'array': array,
      };

  factory User.fromMap(Map map) => User(
        id: map['id'] as String,
        name: map['name'] as String?,
        email: map['email'] as String?,
        phone: map['phone'] as String?,
        array: map['array'] != null ? List.from(map['array']) : null,
      );
}
