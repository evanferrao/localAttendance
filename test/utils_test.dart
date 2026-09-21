import 'package:face_att/services/teacher_auth_service.dart';
import 'package:face_att/utils/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateTimeUtils Tests', () {
    test('formatTime formats ISO strings properly', () {
      expect(DateTimeUtils.formatTime(null), equals('--'));
      expect(DateTimeUtils.formatTime(''), equals('--'));
      expect(DateTimeUtils.formatTime('invalid'), equals('invalid'));
      expect(
        DateTimeUtils.formatTime('2026-09-21T09:05:08.000'),
        equals('09:05:08'),
      );
    });

    test('formatTimeShort formats short time properly', () {
      expect(DateTimeUtils.formatTimeShort(null), equals(''));
      expect(DateTimeUtils.formatTimeShort(''), equals(''));
      expect(
        DateTimeUtils.formatTimeShort('2026-09-21T14:30:45.000'),
        equals('14:30'),
      );
    });

    test('formatDate and formatDateString format date properly', () {
      final dt = DateTime(2026, 9, 5);
      expect(DateTimeUtils.formatDate(dt), equals('2026-09-05'));
      expect(DateTimeUtils.formatDateString('2026-09-05T12:00:00.000'), equals('2026-09-05'));
      expect(DateTimeUtils.formatDateString(null), equals('--'));
    });
  });

  group('StringUtils Tests', () {
    test('slugify converts text to safe slug', () {
      expect(StringUtils.slugify('B.Tech CSE - Section A'), equals('b_tech_cse_section_a'));
      expect(StringUtils.slugify('Hello World! 123'), equals('hello_world_123'));
      expect(StringUtils.slugify('___test___'), equals('test'));
    });

    test('initials extracts first letter capitalized', () {
      expect(StringUtils.initials('john'), equals('J'));
      expect(StringUtils.initials(''), equals('?'));
      expect(StringUtils.initials(null), equals('?'));
      expect(StringUtils.initials('  Arun Kumar'), equals('A'));
    });

    test('capitalize capitalizes the first character', () {
      expect(StringUtils.capitalize('hello'), equals('Hello'));
      expect(StringUtils.capitalize(''), equals(''));
      expect(StringUtils.capitalize('Hello'), equals('Hello'));
    });
  });

  group('ValidationUtils Tests', () {
    test('isValidEmail checks valid and invalid email addresses', () {
      expect(ValidationUtils.isValidEmail('user@example.com'), isTrue);
      expect(ValidationUtils.isValidEmail('first.last@domain.co.in'), isTrue);
      expect(ValidationUtils.isValidEmail(''), isFalse);
      expect(ValidationUtils.isValidEmail(null), isFalse);
      expect(ValidationUtils.isValidEmail('invalid'), isFalse);
      expect(ValidationUtils.isValidEmail('@domain.com'), isFalse);
      expect(ValidationUtils.isValidEmail('user@'), isFalse);
    });

    test('isValidPhone checks phone number requirements', () {
      expect(ValidationUtils.isValidPhone('9876543210'), isTrue);
      expect(ValidationUtils.isValidPhone('+91 98765 43210'), isTrue);
      expect(ValidationUtils.isValidPhone('12345'), isFalse); // too short
      expect(ValidationUtils.isValidPhone(''), isFalse);
      expect(ValidationUtils.isValidPhone(null), isFalse);
      expect(ValidationUtils.isValidPhone('abc1234567'), isFalse);
    });

    test('isValidRegisterNumber checks register number format', () {
      expect(ValidationUtils.isValidRegisterNumber('23BRS1150'), isTrue);
      expect(ValidationUtils.isValidRegisterNumber('CS-101'), isTrue);
      expect(ValidationUtils.isValidRegisterNumber(''), isFalse);
      expect(ValidationUtils.isValidRegisterNumber(null), isFalse);
      expect(ValidationUtils.isValidRegisterNumber('23 BRS 1150'), isFalse); // contains space
    });

    test('isValidUsername validates username format', () {
      expect(ValidationUtils.isValidUsername('teacher_1'), isTrue);
      expect(ValidationUtils.isValidUsername('profSmith'), isTrue);
      expect(ValidationUtils.isValidUsername('ab'), isFalse); // too short
      expect(ValidationUtils.isValidUsername('user@name'), isFalse); // invalid char
      expect(ValidationUtils.isValidUsername(null), isFalse);
    });

    test('isValidPassword validates password length', () {
      expect(ValidationUtils.isValidPassword('123456'), isTrue);
      expect(ValidationUtils.isValidPassword('secretPass'), isTrue);
      expect(ValidationUtils.isValidPassword('12345'), isFalse); // < 6
      expect(ValidationUtils.isValidPassword(null), isFalse);
    });
  });

  group('TeacherAuthService Security Tests', () {
    test('constantTimeEquals returns true for identical strings and false for differing strings', () {
      expect(TeacherAuthService.constantTimeEquals('hello', 'hello'), isTrue);
      expect(TeacherAuthService.constantTimeEquals('hello', 'world'), isFalse);
      expect(TeacherAuthService.constantTimeEquals('hello', 'hell'), isFalse);
      expect(TeacherAuthService.constantTimeEquals('', ''), isTrue);
      expect(TeacherAuthService.constantTimeEquals('a', ''), isFalse);
    });

    test('verifyPassword verifies correct password and rejects invalid password', () {
      final hash = TeacherAuthService.hashPassword('securePass123');
      expect(TeacherAuthService.verifyPassword('securePass123', hash), isTrue);
      expect(TeacherAuthService.verifyPassword('wrongPassword', hash), isFalse);
      expect(TeacherAuthService.verifyPassword('securePass123', 'invalid:format:hash'), isFalse);
    });
  });
}
