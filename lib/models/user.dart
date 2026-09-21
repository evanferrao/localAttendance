/// Represents a registered face embedding user in the local Hive database.
/// Each user maps to a student via their [id] (student ID or register number).
class User {
  final String id; // unique key in Hive
  final String? name;
  final String? email;
  final String? phone;
  final List<double>? array; // 512-dimensional ArcFace embedding

  const User({
    required this.id,
    this.name,
    this.email,
    this.phone,
    this.array,
  });

  /// Creates a copy with selectively replaced fields.
  User copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    List<double>? array,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      array: array ?? this.array,
    );
  }

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
        array: map['array'] != null ? List<double>.from(map['array']) : null,
      );
}
