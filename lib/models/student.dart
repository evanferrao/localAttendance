class Student {
  final String registerNumber;
  final String name;
  final String email;
  final String phone;
  final String createdAt;
  final bool hasFaceEnrolled;

  const Student({
    required this.registerNumber,
    this.name = '',
    this.email = '',
    this.phone = '',
    String? createdAt,
    this.hasFaceEnrolled = false,
  }) : createdAt = createdAt ?? '';

  String get displayName => name.trim().isNotEmpty ? name.trim() : registerNumber;

  Map<String, dynamic> toMap() => {
        'register_number': registerNumber,
        'name': name,
        'email': email,
        'phone': phone,
        'created_at': createdAt,
      };

  factory Student.fromMap(Map<String, dynamic> map, {bool hasFaceEnrolled = false}) => Student(
        registerNumber: (map['register_number'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
        phone: (map['phone'] as String?) ?? '',
        createdAt: (map['created_at'] as String?) ?? '',
        hasFaceEnrolled: hasFaceEnrolled,
      );

  Student copyWith({
    String? registerNumber,
    String? name,
    String? email,
    String? phone,
    String? createdAt,
    bool? hasFaceEnrolled,
  }) {
    return Student(
      registerNumber: registerNumber ?? this.registerNumber,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      hasFaceEnrolled: hasFaceEnrolled ?? this.hasFaceEnrolled,
    );
  }
}

