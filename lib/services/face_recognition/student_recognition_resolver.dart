import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/recognition_result.dart';
import 'package:face_att/models/student.dart';

/// Helper utility for resolving recognized faces to student entity records.
class StudentRecognitionResolver {
  StudentRecognitionResolver._();

  /// Resolves a [RecognitionResult] to a [Student] model strictly by [registerNumber]
  /// by cross-referencing in-memory [enrolledStudents] first, and falling back to the [studentRepo].
  static Future<Student?> resolveStudentForResult({
    required RecognitionResult result,
    required List<Student> enrolledStudents,
    required StudentRepository studentRepo,
  }) async {
    final candidateRegNo = result.registerNumber;
    if (candidateRegNo == null || candidateRegNo.trim().isEmpty) return null;

    final trimmedRegNo = candidateRegNo.trim();
    final upperRegNo = trimmedRegNo.toUpperCase();

    // 1. Search in-memory enrolled students strictly by register number (case-insensitive)
    Student? matched = enrolledStudents.where(
      (s) => s.registerNumber.trim().toUpperCase() == upperRegNo,
    ).firstOrNull;

    // 2. Query persistent database strictly by register number
    matched ??= await studentRepo.getStudentByRegisterNumber(trimmedRegNo);

    return matched;
  }
}

