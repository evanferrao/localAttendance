class ClassModel {
  final int? id;
  final String name;
  final String createdAt;
  final List<int> teacherIds;
  final List<int> studentIds;
  final int teachersCount;
  final int studentsCount;

  const ClassModel({
    this.id,
    required this.name,
    required this.createdAt,
    this.teacherIds = const [],
    this.studentIds = const [],
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
    List<int> studentIds = const [],
    int? teachersCount,
    int? studentsCount,
  }) =>
      ClassModel(
        id: map['id'] as int?,
        name: map['name'] as String,
        createdAt: map['created_at'] as String,
        teacherIds: teacherIds,
        studentIds: studentIds,
        teachersCount: teachersCount ?? teacherIds.length,
        studentsCount: studentsCount ?? studentIds.length,
      );

  ClassModel copyWith({
    int? id,
    String? name,
    String? createdAt,
    List<int>? teacherIds,
    List<int>? studentIds,
    int? teachersCount,
    int? studentsCount,
  }) {
    return ClassModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      teacherIds: teacherIds ?? this.teacherIds,
      studentIds: studentIds ?? this.studentIds,
      teachersCount: teachersCount ?? this.teachersCount,
      studentsCount: studentsCount ?? this.studentsCount,
    );
  }
}
