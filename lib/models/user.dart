/// Represents a registered face embedding user in the local Hive database.
/// Each user maps to a student via their [registerNumber].
class User {
  final String registerNumber; // unique key in Hive
  final String? name;
  final String? email;
  final String? phone;
  final List<double>? array; // 512-dimensional ArcFace embedding

  const User({
    required this.registerNumber,
    this.name,
    this.email,
    this.phone,
    this.array,
  });

  /// Creates a copy with selectively replaced fields.
  User copyWith({
    String? registerNumber,
    String? name,
    String? email,
    String? phone,
    List<double>? array,
  }) {
    return User(
      registerNumber: registerNumber ?? this.registerNumber,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      array: array ?? this.array,
    );
  }

  Map<String, dynamic> toMap() => {
        'register_number': registerNumber,
        'name': name,
        'email': email,
        'phone': phone,
        'array': array,
      };

  factory User.fromMap(Map map) => User(
        registerNumber: (map['register_number'] ?? map['id'])?.toString() ?? '',
        name: map['name'] as String?,
        email: map['email'] as String?,
        phone: map['phone'] as String?,
        array: map['array'] != null
            ? (map['array'] as List).map((e) => (e as num).toDouble()).toList()
            : null,
      );
}

