import 'dart:math';

import 'package:face_att/models/recognition_result.dart';
import 'package:face_att/models/user.dart';
import 'package:face_att/utils/local_db.dart';
import 'package:flutter/foundation.dart';

/// Service responsible for embedding comparison, cosine similarity, candidate filtering, and recognition decisions.
class FaceMatcher {
  static const int defaultEmbeddingDimension = 512;

  double similarityThreshold;
  double marginThreshold;

  FaceMatcher({
    this.similarityThreshold = 0.35,
    this.marginThreshold = 0.0001,
  });

  /// Normalize a vector to unit length (L2 norm = 1.0).
  static List<double> l2Normalize(List<double> v) {
    final norm = sqrt(v.fold(0.0, (s, e) => s + e * e));
    if (norm == 0.0) return v;
    return v.map((e) => e / norm).toList();
  }

  /// Dot product between two vectors (equivalent to cosine similarity if both vectors are L2-normalized).
  static double dotProduct(List<double> a, List<double> b) {
    double sum = 0.0;
    final len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  /// Euclidean distance between two vectors.
  static double euclideanDistance(List<double> a, List<double> b) {
    double sum = 0.0;
    final len = min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sqrt(sum);
  }

  /// Search top-k candidate matches against enrolled users.
  /// If [allowedStudentIds] is provided, only students belonging to that class are evaluated.
  List<RecognitionMatch> search(
    List<double> queryEmbedding, {
    int k = 5,
    Set<String>? allowedStudentIds,
    List<User>? enrolledUsers,
  }) {
    final normQuery = l2Normalize(queryEmbedding);
    final users = enrolledUsers ?? LocalDB.getUsers();
    if (users.isEmpty) return [];

    // Keep highest scoring entry per distinct student
    final studentBestMatch = <String, RecognitionMatch>{};

    for (int idx = 0; idx < users.length; idx++) {
      final u = users[idx];
      if (u.array == null || u.array!.isEmpty) continue;

      // Filter: if allowedStudentIds is specified, only consider students in active class
      if (allowedStudentIds != null && allowedStudentIds.isNotEmpty) {
        final uIdTrimmed = u.id.trim();
        final uNameTrimmed = (u.name ?? '').trim();
        final matchesId = allowedStudentIds.contains(uIdTrimmed) ||
            allowedStudentIds.contains(uIdTrimmed.toUpperCase()) ||
            allowedStudentIds.contains(uIdTrimmed.toLowerCase());
        final matchesName = uNameTrimmed.isNotEmpty &&
            (allowedStudentIds.contains(uNameTrimmed) ||
                allowedStudentIds.contains(uNameTrimmed.toLowerCase()));
        if (!matchesId && !matchesName) {
          continue;
        }
      }

      // Safety guard against legacy / incompatible embedding size
      if (u.array!.length != defaultEmbeddingDimension) {
        debugPrint("⚠️ Skipping user ${u.name} with incompatible embedding size (${u.array!.length})");
        continue;
      }

      final stored = l2Normalize(List<double>.from(u.array!));
      final score = dotProduct(normQuery, stored);

      final studentKey = (u.name != null && u.name!.trim().isNotEmpty)
          ? u.name!.trim().toLowerCase()
          : u.id.trim().toLowerCase();

      final existing = studentBestMatch[studentKey];
      if (existing == null || score > existing.score) {
        studentBestMatch[studentKey] = RecognitionMatch(
          studentId: u.id,
          name: u.name ?? "Unknown",
          score: score,
          index: idx,
          user: u,
        );
      }
    }

    final scored = studentBestMatch.values.toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(k).toList();
  }

  /// Evaluates face embedding and returns [RecognitionResult] based on similarity and margin thresholds.
  RecognitionResult match(
    List<double> faceEmbedding, {
    int k = 5,
    Set<String>? allowedStudentIds,
    List<User>? enrolledUsers,
  }) {
    final results = search(
      faceEmbedding,
      k: k,
      allowedStudentIds: allowedStudentIds,
      enrolledUsers: enrolledUsers,
    );

    if (results.isEmpty) {
      return const RecognitionResult(
        accepted: false,
        studentId: null,
        name: "Unknown",
        score: 0.0,
        secondScore: 0.0,
        margin: 0.0,
        matches: [],
      );
    }

    final best = results[0];

    // If only one candidate matched
    if (results.length < 2) {
      final accepted = best.score >= similarityThreshold;
      return RecognitionResult(
        accepted: accepted,
        studentId: accepted ? best.studentId : null,
        name: accepted ? best.name : "Unknown",
        score: best.score,
        secondScore: 0.0,
        margin: 0.0,
        matches: results,
        user: accepted ? best.user : null,
      );
    }

    final second = results[1];
    final bestScore = best.score;
    final secondScore = second.score;
    final margin = bestScore - secondScore;

    // A candidate is accepted when:
    // 1. bestScore exceeds the similarity threshold (>= 0.35)
    // 2. AND either second student is not a match (secondScore < threshold)
    //    OR the margin between top candidate and runner-up is sufficient (>= marginThreshold)
    final accepted = bestScore >= similarityThreshold &&
        (secondScore < similarityThreshold || margin >= marginThreshold);

    return RecognitionResult(
      accepted: accepted,
      studentId: accepted ? best.studentId : null,
      name: accepted ? best.name : "Unknown",
      score: bestScore,
      secondScore: secondScore,
      margin: margin,
      matches: results,
      user: accepted ? best.user : null,
    );
  }
}
