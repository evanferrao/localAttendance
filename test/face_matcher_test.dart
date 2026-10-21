import 'dart:math';

import 'package:face_att/models/user.dart';
import 'package:face_att/services/face_recognition/face_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FaceMatcher Vector Mathematics Tests', () {
    test('l2Normalize normalizes a vector to unit length', () {
      final vec = [3.0, 4.0];
      final normalized = FaceMatcher.l2Normalize(vec);

      expect(normalized[0], closeTo(0.6, 1e-5));
      expect(normalized[1], closeTo(0.8, 1e-5));

      final norm = sqrt(normalized[0] * normalized[0] + normalized[1] * normalized[1]);
      expect(norm, closeTo(1.0, 1e-5));
    });

    test('l2Normalize handles zero-length vector without division by zero', () {
      final zeroVec = [0.0, 0.0, 0.0];
      final result = FaceMatcher.l2Normalize(zeroVec);
      expect(result, equals(zeroVec));
    });

    test('dotProduct calculates accurate cosine similarity on normalized vectors', () {
      final a = [1.0, 0.0];
      final b = [1.0, 0.0];
      final c = [0.0, 1.0];

      expect(FaceMatcher.dotProduct(a, b), closeTo(1.0, 1e-5));
      expect(FaceMatcher.dotProduct(a, c), closeTo(0.0, 1e-5));
    });

    test('euclideanDistance computes geometric distance', () {
      final a = [0.0, 0.0];
      final b = [3.0, 4.0];
      expect(FaceMatcher.euclideanDistance(a, b), closeTo(5.0, 1e-5));
    });
  });

  group('FaceMatcher Candidate Search & Matching Tests', () {
    late FaceMatcher matcher;
    late List<double> student1Embedding;
    late List<double> student2Embedding;
    late List<User> testUsers;

    setUp(() {
      matcher = FaceMatcher(
        similarityThreshold: 0.35,
        marginThreshold: 0.05,
      );

      // Create synthetic 512-d unit vectors
      student1Embedding = List<double>.filled(512, 0.0);
      student1Embedding[0] = 1.0;

      student2Embedding = List<double>.filled(512, 0.0);
      student2Embedding[1] = 1.0;

      testUsers = [
        User(registerNumber: '23BRS1150', name: 'Alice Smith', array: student1Embedding),
        User(registerNumber: '23BRS1001', name: 'Bob Jones', array: student2Embedding),
      ];
    });

    test('search finds top matching student by registerNumber', () {
      final query = List<double>.filled(512, 0.0)..[0] = 0.95..[1] = 0.05;
      final results = matcher.search(query, enrolledUsers: testUsers);

      expect(results.isNotEmpty, isTrue);
      expect(results.first.registerNumber, equals('23BRS1150'));
      expect(results.first.name, equals('Alice Smith'));
      expect(results.first.score, greaterThan(0.9));
    });

    test('search filters out students not in allowedRegisterNumbers', () {
      final query = List<double>.filled(512, 0.0)..[0] = 1.0;
      // Only 23BRS1001 is in the active class
      final results = matcher.search(
        query,
        allowedRegisterNumbers: {'23BRS1001'},
        enrolledUsers: testUsers,
      );

      expect(results.length, equals(1));
      expect(results.first.registerNumber, equals('23BRS1001'));
    });

    test('match accepts candidate exceeding similarity threshold and margin', () {
      final query = List<double>.filled(512, 0.0)..[0] = 1.0;
      final result = matcher.match(query, enrolledUsers: testUsers);

      expect(result.accepted, isTrue);
      expect(result.registerNumber, equals('23BRS1150'));
      expect(result.name, equals('Alice Smith'));
      expect(result.score, closeTo(1.0, 1e-5));
      expect(result.margin, greaterThanOrEqualTo(0.05));
    });

    test('match rejects unknown face below similarity threshold', () {
      // Orthogonal vector [0, 0, 1, 0, ...]
      final query = List<double>.filled(512, 0.0)..[2] = 1.0;
      final result = matcher.match(query, enrolledUsers: testUsers);

      expect(result.accepted, isFalse);
      expect(result.registerNumber, isNull);
      expect(result.name, equals('Unknown'));
    });

    test('match accepts candidate when duplicate entries exist for the same student', () {
      final multiUsers = [
        User(registerNumber: '23BRS1150', name: '', array: student1Embedding),
        User(registerNumber: '23BRS1150', name: '', array: student1Embedding),
        User(registerNumber: '23BRS1001', name: 'Bob Jones', array: student2Embedding),
      ];

      final query = List<double>.filled(512, 0.0)..[0] = 1.0;
      final result = matcher.match(query, enrolledUsers: multiUsers);

      expect(result.accepted, isTrue);
      expect(result.registerNumber, equals('23BRS1150'));
      expect(result.score, closeTo(1.0, 1e-5));
      expect(result.secondScore, closeTo(0.0, 1e-5));
      expect(result.margin, closeTo(1.0, 1e-5));
    });

    test('User.fromMap safely handles register_number and numbers in array from Hive/JSON', () {
      final map = {
        'register_number': '23BRS1150',
        'name': 'Test Student',
        'email': 'test@example.com',
        'phone': '1234567890',
        'array': [0, 1, 0.5, 2],
      };

      final user = User.fromMap(map);
      expect(user.registerNumber, equals('23BRS1150'));
      expect(user.array, isNotNull);
      expect(user.array!, equals([0.0, 1.0, 0.5, 2.0]));
      expect(user.array!.first, isA<double>());
    });

    test('students without names are matched strictly by registration number', () {
      // Students with null and empty names
      final namelessUsers = [
        User(registerNumber: '23BRS1150', name: null, array: student1Embedding),
        User(registerNumber: '23BRS1001', name: '', array: student2Embedding),
      ];

      final query1 = List<double>.filled(512, 0.0)..[0] = 1.0;
      final result1 = matcher.match(query1, enrolledUsers: namelessUsers);

      expect(result1.accepted, isTrue);
      expect(result1.registerNumber, equals('23BRS1150'));
      expect(result1.name, equals('23BRS1150')); // Falls back to registration number
      expect(result1.score, closeTo(1.0, 1e-5));

      final query2 = List<double>.filled(512, 0.0)..[1] = 1.0;
      final result2 = matcher.match(query2, enrolledUsers: namelessUsers);

      expect(result2.accepted, isTrue);
      expect(result2.registerNumber, equals('23BRS1001'));
      expect(result2.name, equals('23BRS1001')); // Falls back to registration number
      expect(result2.score, closeTo(1.0, 1e-5));
    });
  });
}


