import 'package:face_att/models/student.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/services/face_recognition/ml_service.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:image_picker/image_picker.dart';

/// Centralized service for enrolling student faces from camera or photo.
/// Enforces dual-key indexing (student ID and register number) in local storage for fast O(1) lookup.
class FaceEnrollmentService {
  final MLService _mlService;
  final ImagePicker _picker;

  FaceEnrollmentService({
    MLService? mlService,
    ImagePicker? picker,
  })  : _mlService = mlService ?? MLService(),
        _picker = picker ?? ImagePicker();

  /// Enroll face embedding from a photo picked via gallery.
  /// Returns the enrolled [User] or `null` if user canceled or no face was found.
  Future<User?> enrollFromGallery(Student student) async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return null;

    final bytes = await xFile.readAsBytes();
    final studentKey = student.id?.toString() ?? student.registerNumber;

    final user = await _mlService.enrollFromImageBytes(
      bytes: bytes,
      studentId: studentKey,
      name: student.name,
      email: student.email,
      phone: student.phone,
    );

    // Enforce dual-key index under registerNumber
    await saveDualKeyEmbedding(
      studentId: student.id?.toString() ?? student.registerNumber,
      registerNumber: student.registerNumber,
      name: student.name,
      email: student.email,
      phone: student.phone,
      embedding: user.array,
    );

    return user;
  }

  /// Synchronize dual-key indexing after a camera enrollment session.
  Future<void> syncAfterCameraEnrollment(Student student) async {
    final primaryKey = student.id?.toString() ?? student.registerNumber;
    final enrolledUser = LocalDB.getUser(primaryKey);

    if (enrolledUser != null && enrolledUser.array != null) {
      await saveDualKeyEmbedding(
        studentId: primaryKey,
        registerNumber: student.registerNumber,
        name: student.name,
        email: student.email,
        phone: student.phone,
        embedding: enrolledUser.array,
      );
    }
  }

  /// Stores face embedding under both student ID and register number in LocalDB.
  static Future<void> saveDualKeyEmbedding({
    required String studentId,
    required String registerNumber,
    required String name,
    String? email,
    String? phone,
    required List<double>? embedding,
  }) async {
    if (embedding == null || embedding.length != 512) return;

    // 1. Primary entry
    await LocalDB.saveUser(User(
      id: studentId,
      name: name,
      email: email,
      phone: phone,
      array: embedding,
    ));

    // 2. Register number entry if different from studentId
    if (studentId != registerNumber) {
      await LocalDB.saveUser(User(
        id: registerNumber,
        name: name,
        email: email,
        phone: phone,
        array: embedding,
      ));
    }
  }
}
