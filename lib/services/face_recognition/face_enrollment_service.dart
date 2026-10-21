import 'package:face_att/models/student.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/services/face_recognition/ml_service.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:image_picker/image_picker.dart';

/// Centralized service for enrolling student faces from camera or photo.
/// Uses registerNumber strictly as the unique primary key in local storage.
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
    final regNo = student.registerNumber.trim();

    final user = await _mlService.enrollFromImageBytes(
      bytes: bytes,
      registerNumber: regNo,
      name: student.name,
      email: student.email,
      phone: student.phone,
    );

    // Save strictly under registerNumber as the only primary key
    await saveRegistrationEmbedding(
      registerNumber: regNo,
      name: student.name,
      email: student.email,
      phone: student.phone,
      embedding: user.array,
    );

    return user;
  }

  /// Synchronize indexing after a camera enrollment session.
  Future<void> syncAfterCameraEnrollment(Student student) async {
    final regNo = student.registerNumber.trim();
    final enrolledUser = LocalDB.getUser(regNo);

    if (enrolledUser != null && enrolledUser.array != null) {
      await saveRegistrationEmbedding(
        registerNumber: regNo,
        name: student.name,
        email: student.email,
        phone: student.phone,
        embedding: enrolledUser.array,
      );
    }
  }

  /// Stores face embedding strictly keyed by register number in LocalDB.
  static Future<void> saveRegistrationEmbedding({
    required String registerNumber,
    required String name,
    String? email,
    String? phone,
    required List<double>? embedding,
  }) async {
    if (embedding == null || embedding.length != 512) return;

    final regTrimmed = registerNumber.trim();

    await LocalDB.saveUser(User(
      registerNumber: regTrimmed,
      name: name,
      email: email,
      phone: phone,
      array: embedding,
    ));
  }
}

