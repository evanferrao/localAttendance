import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class TeacherAuthService {
  TeacherAuthService._();
  static final TeacherAuthService instance = TeacherAuthService._();

  /// Hash a plaintext password with a unique cryptographic salt
  static String hashPassword(String password, {String? salt}) {
    final effectiveSalt = salt ?? _generateSalt();
    final bytes = utf8.encode('$effectiveSalt:$password');
    final digest = sha256.convert(bytes);
    return '$effectiveSalt:${digest.toString()}';
  }

  /// Verify a plaintext password against the stored salt:hash string
  static bool verifyPassword(String password, String storedHash) {
    final parts = storedHash.split(':');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final expectedHash = hashPassword(password, salt: salt);
    return expectedHash == storedHash;
  }

  static String _generateSalt() {
    final rand = Random.secure();
    final values = List<int>.generate(16, (i) => rand.nextInt(256));
    return base64Url.encode(values);
  }
}
