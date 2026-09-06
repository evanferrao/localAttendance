class Student {
  final int? id;
  final String registerNumber;
  final String name;
  final String email;
  final String phone;
  final String createdAt;
  final bool hasFaceEnrolled;

  const Student({
    this.id,
    required this.registerNumber,
    required this.name,
    required this.email,
    required this.phone,
    required this.createdAt,
    this.hasFaceEnrolled = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'register_number': registerNumber,
        'name': name,
        'email': email,
        'phone': phone,
        'created_at': createdAt,
      };

  factory Student.fromMap(Map<String, dynamic> map, {bool hasFaceEnrolled = false}) => Student(
        id: map['id'] as int?,
        registerNumber: map['register_number'] as String,
        name: map['name'] as String,
        email: map['email'] as String,
        phone: map['phone'] as String,
        createdAt: map['created_at'] as String,
        hasFaceEnrolled: hasFaceEnrolled,
      );

  Student copyWith({
    int? id,
    String? registerNumber,
    String? name,
    String? email,
    String? phone,
    String? createdAt,
    bool? hasFaceEnrolled,
  }) {
    return Student(
      id: id ?? this.id,
      registerNumber: registerNumber ?? this.registerNumber,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      hasFaceEnrolled: hasFaceEnrolled ?? this.hasFaceEnrolled,
    );
  }
}
