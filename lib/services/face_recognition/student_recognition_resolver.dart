import 'package:face_att/database/repositories/student_repository.dart';
import 'package:face_att/models/recognition_result.dart';
import 'package:face_att/models/student.dart';

/// Helper utility for resolving recognized faces to student entity records.
class StudentRecognitionResolver {
  StudentRecognitionResolver._();

  /// Resolves a [RecognitionResult] to a [Student] model by cross-referencing
  /// in-memory [enrolledStudents] first, and falling back to the [studentRepo].
  static Future<Student?> resolveStudentForResult({
    required RecognitionResult result,
    required List<Student> enrolledStudents,
    required StudentRepository studentRepo,
  }) async {
    final candidateId = result.studentId;
    if (candidateId == null || candidateId.trim().isEmpty) return null;

    final trimmedId = candidateId.trim();
    final lowerId = trimmedId.toLowerCase();
    final candidateNameLower = result.name.trim().toLowerCase();
    final parsedId = int.tryParse(trimmedId);

    // 1. Search in-memory enrolled students by numeric ID
    Student? matched;
    if (parsedId != null) {
      matched = enrolledStudents.where((s) => s.id == parsedId).firstOrNull;
    }

    // 2. Search in-memory enrolled students by register number (case-insensitive)
    matched ??= enrolledStudents.where(
      (s) => s.registerNumber.trim().toLowerCase() == lowerId,
    ).firstOrNull;

    // 3. Search in-memory enrolled students by student name (case-insensitive)
    matched ??= enrolledStudents.where(
      (s) => s.name.trim().toLowerCase() == candidateNameLower,
    ).firstOrNull;

    // 4. Fallback to persistent database queries if not found in memory
    if (matched == null) {
      if (parsedId != null) {
        matched = await studentRepo.getStudentById(parsedId);
      }
      matched ??= await studentRepo.getStudentByRegisterNumber(trimmedId);
    }

    return matched;
  }
}
