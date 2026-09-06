class AttendanceSession {
  final int? id;
  final int classId;
  final int teacherId;
  final String attendanceDate;
  final String startedAt;
  final String? endedAt;
  final String status; // 'active' | 'completed'

  // Joined display attributes
  final String? className;
  final String? teacherName;
  final String? teacherUsername;
  final int presentCount;
  final int totalCount;

  const AttendanceSession({
    this.id,
    required this.classId,
    required this.teacherId,
    required this.attendanceDate,
    required this.startedAt,
    this.endedAt,
    required this.status,
    this.className,
    this.teacherName,
    this.teacherUsername,
    this.presentCount = 0,
    this.totalCount = 0,
  });

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'class_id': classId,
        'teacher_id': teacherId,
        'attendance_date': attendanceDate,
        'started_at': startedAt,
        'ended_at': endedAt,
        'status': status,
      };

  factory AttendanceSession.fromMap(Map<String, dynamic> map) => AttendanceSession(
        id: map['id'] as int?,
        classId: map['class_id'] as int,
        teacherId: map['teacher_id'] as int,
        attendanceDate: map['attendance_date'] as String,
        startedAt: map['started_at'] as String,
        endedAt: map['ended_at'] as String?,
        status: map['status'] as String,
        className: map['class_name'] as String?,
        teacherName: map['teacher_name'] as String?,
        teacherUsername: map['teacher_username'] as String?,
        presentCount: (map['present_count'] as num?)?.toInt() ?? 0,
        totalCount: (map['total_count'] as num?)?.toInt() ?? 0,
      );

  AttendanceSession copyWith({
    int? id,
    int? classId,
    int? teacherId,
    String? attendanceDate,
    String? startedAt,
    String? endedAt,
    String? status,
    String? className,
    String? teacherName,
    String? teacherUsername,
    int? presentCount,
    int? totalCount,
  }) {
    return AttendanceSession(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      teacherId: teacherId ?? this.teacherId,
      attendanceDate: attendanceDate ?? this.attendanceDate,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      className: className ?? this.className,
      teacherName: teacherName ?? this.teacherName,
      teacherUsername: teacherUsername ?? this.teacherUsername,
      presentCount: presentCount ?? this.presentCount,
      totalCount: totalCount ?? this.totalCount,
    );
  }
}
