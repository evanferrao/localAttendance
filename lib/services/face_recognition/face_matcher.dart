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
  /// If [allowedRegisterNumbers] is provided, only students belonging to that class are evaluated.
  List<RecognitionMatch> search(
    List<double> queryEmbedding, {
    int k = 5,
    Set<String>? allowedRegisterNumbers,
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

      // Filter: if allowedRegisterNumbers is specified, only consider students in active class strictly by registration number
      if (allowedRegisterNumbers != null && allowedRegisterNumbers.isNotEmpty) {
        final uRegTrimmed = u.registerNumber.trim();
        final matchesId = allowedRegisterNumbers.contains(uRegTrimmed) ||
            allowedRegisterNumbers.contains(uRegTrimmed.toUpperCase()) ||
            allowedRegisterNumbers.contains(uRegTrimmed.toLowerCase());
        if (!matchesId) {
          continue;
        }
      }

      // Safety guard against legacy / incompatible embedding size
      if (u.array!.length != defaultEmbeddingDimension) {
        debugPrint("⚠️ Skipping user with incompatible embedding size (${u.array!.length})");
        continue;
      }

      final stored = l2Normalize(List<double>.from(u.array!));
      final score = dotProduct(normQuery, stored);

      // Student key: strictly group by registration number (case-insensitive)
      final studentKey = u.registerNumber.trim().toUpperCase();

      final existing = studentBestMatch[studentKey];
      if (existing == null || score > existing.score) {
        studentBestMatch[studentKey] = RecognitionMatch(
          registerNumber: u.registerNumber.trim(),
          name: (u.name != null && u.name!.trim().isNotEmpty) ? u.name!.trim() : u.registerNumber.trim(),
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
    Set<String>? allowedRegisterNumbers,
    List<User>? enrolledUsers,
  }) {
    final results = search(
      faceEmbedding,
      k: k,
      allowedRegisterNumbers: allowedRegisterNumbers,
      enrolledUsers: enrolledUsers,
    );

    if (results.isEmpty) {
      return const RecognitionResult(
        accepted: false,
        registerNumber: null,
        name: "Unknown",
        score: 0.0,
        secondScore: 0.0,
        margin: 0.0,
        matches: [],
      );
    }

    final best = results[0];

    // Find the best runner-up candidate that is a distinct student strictly by registration number
    RecognitionMatch? distinctRunnerUp;
    for (int i = 1; i < results.length; i++) {
      final cand = results[i];
      final isSameStudent = cand.registerNumber.trim().toUpperCase() == best.registerNumber.trim().toUpperCase();

      // Check embedding similarity to detect duplicate entries for the same student
      bool isSameEmbedding = false;
      if (best.user?.array != null && cand.user?.array != null) {
        final sim = dotProduct(l2Normalize(best.user!.array!), l2Normalize(cand.user!.array!));
        if (sim > 0.98) {
          isSameEmbedding = true;
        }
      }

      if (!isSameStudent && !isSameEmbedding) {
        distinctRunnerUp = cand;
        break;
      }
    }

    // If only one candidate matched or all matches belong to the same student
    if (distinctRunnerUp == null) {
      final accepted = best.score >= similarityThreshold;
      return RecognitionResult(
        accepted: accepted,
        registerNumber: accepted ? best.registerNumber : null,
        name: accepted ? best.name : "Unknown",
        score: best.score,
        secondScore: 0.0,
        margin: 0.0,
        matches: results,
        user: accepted ? best.user : null,
      );
    }

    final bestScore = best.score;
    final secondScore = distinctRunnerUp.score;
    final margin = bestScore - secondScore;

    // A candidate is accepted when:
    // 1. bestScore exceeds the similarity threshold (>= 0.35)
    // 2. AND either second student is not a match (secondScore < threshold)
    //    OR the margin between top candidate and runner-up is sufficient (>= marginThreshold)
    final accepted = bestScore >= similarityThreshold &&
        (secondScore < similarityThreshold || margin >= marginThreshold);

    return RecognitionResult(
      accepted: accepted,
      registerNumber: accepted ? best.registerNumber : null,
      name: accepted ? best.name : "Unknown",
      score: bestScore,
      secondScore: secondScore,
      margin: margin,
      matches: results,
      user: accepted ? best.user : null,
    );
  }
}
