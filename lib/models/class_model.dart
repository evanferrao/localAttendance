class ClassModel {
  final int? id;
  final String name;
  final String createdAt;
  final List<int> teacherIds;
  final List<String> studentRegisterNumbers;
  final int teachersCount;
  final int studentsCount;

  const ClassModel({
    this.id,
    required this.name,
    required this.createdAt,
    this.teacherIds = const [],
    this.studentRegisterNumbers = const [],
    this.teachersCount = 0,
    this.studentsCount = 0,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'created_at': createdAt,
      };

  factory ClassModel.fromMap(
    Map<String, dynamic> map, {
    List<int> teacherIds = const [],
    List<String> studentRegisterNumbers = const [],
    int? teachersCount,
    int? studentsCount,
  }) =>
      ClassModel(
        id: map['id'] as int?,
        name: map['name'] as String,
        createdAt: map['created_at'] as String,
        teacherIds: teacherIds,
        studentRegisterNumbers: studentRegisterNumbers,
        teachersCount: teachersCount ?? teacherIds.length,
        studentsCount: studentsCount ?? studentRegisterNumbers.length,
      );

  ClassModel copyWith({
    int? id,
    String? name,
    String? createdAt,
    List<int>? teacherIds,
    List<String>? studentRegisterNumbers,
    int? teachersCount,
    int? studentsCount,
  }) {
    return ClassModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      teacherIds: teacherIds ?? this.teacherIds,
      studentRegisterNumbers: studentRegisterNumbers ?? this.studentRegisterNumbers,
      teachersCount: teachersCount ?? this.teachersCount,
      studentsCount: studentsCount ?? this.studentsCount,
    );
  }
}

