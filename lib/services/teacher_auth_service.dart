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

  /// Verify a plaintext password against the stored salt:hash string using constant-time comparison
  static bool verifyPassword(String password, String storedHash) {
    final parts = storedHash.split(':');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final expectedHash = hashPassword(password, salt: salt);
    return constantTimeEquals(expectedHash, storedHash);
  }

  /// Constant-time string comparison to prevent timing attacks
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  static String _generateSalt() {
    final rand = Random.secure();
    final values = List<int>.generate(16, (i) => rand.nextInt(256));
    return base64Url.encode(values);
  }
}
