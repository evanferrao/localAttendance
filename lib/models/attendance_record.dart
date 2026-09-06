class AttendanceRecord {
  final int? id;
  final int sessionId;
  final int studentId;
  final String status; // 'present' | 'absent'
  final String? attendanceTime;

  // Historical student snapshot
  final String studentRegisterNumber;
  final String studentName;
  final String studentEmail;
  final String studentPhone;

  const AttendanceRecord({
    this.id,
    required this.sessionId,
    required this.studentId,
    required this.status,
    this.attendanceTime,
    required this.studentRegisterNumber,
    required this.studentName,
    required this.studentEmail,
    required this.studentPhone,
  });

  bool get isPresent => status == 'present';
  bool get isAbsent => status == 'absent';

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'student_id': studentId,
        'status': status,
        'attendance_time': attendanceTime,
        'student_register_number': studentRegisterNumber,
        'student_name': studentName,
        'student_email': studentEmail,
        'student_phone': studentPhone,
      };

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) => AttendanceRecord(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        studentId: map['student_id'] as int,
        status: map['status'] as String,
        attendanceTime: map['attendance_time'] as String?,
        studentRegisterNumber: map['student_register_number'] as String? ?? '',
        studentName: map['student_name'] as String? ?? '',
        studentEmail: map['student_email'] as String? ?? '',
        studentPhone: map['student_phone'] as String? ?? '',
      );

  AttendanceRecord copyWith({
    int? id,
    int? sessionId,
    int? studentId,
    String? status,
    String? attendanceTime,
    String? studentRegisterNumber,
    String? studentName,
    String? studentEmail,
    String? studentPhone,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      studentId: studentId ?? this.studentId,
      status: status ?? this.status,
      attendanceTime: attendanceTime ?? this.attendanceTime,
      studentRegisterNumber: studentRegisterNumber ?? this.studentRegisterNumber,
      studentName: studentName ?? this.studentName,
      studentEmail: studentEmail ?? this.studentEmail,
      studentPhone: studentPhone ?? this.studentPhone,
    );
  }
}
