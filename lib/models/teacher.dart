class Teacher {
  final int? id;
  final String username;
  final String passwordHash;
  final String displayName;
  final String createdAt;

  const Teacher({
    this.id,
    required this.username,
    required this.passwordHash,
    required this.displayName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'username': username,
        'password_hash': passwordHash,
        'display_name': displayName,
        'created_at': createdAt,
      };

  factory Teacher.fromMap(Map<String, dynamic> map) => Teacher(
        id: map['id'] as int?,
        username: map['username'] as String,
        passwordHash: map['password_hash'] as String,
        displayName: map['display_name'] as String,
        createdAt: map['created_at'] as String,
      );

  Teacher copyWith({
    int? id,
    String? username,
    String? passwordHash,
    String? displayName,
    String? createdAt,
  }) {
    return Teacher(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
