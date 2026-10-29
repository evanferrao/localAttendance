import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessStep { blink, turnLeft, turnRight, done }

class LivenessResult {
  final bool passed;
  final String instruction;
  LivenessResult({required this.passed, required this.instruction});
}

class LivenessService {
  LivenessStep _step = LivenessStep.blink;
  DateTime _stepStart = DateTime.now();

  // How long each step is allowed before resetting
  static const _stepTimeoutSec = 8;

  bool get isDone => _step == LivenessStep.done;

  /// 0=blink, 1=turnLeft, 2=turnRight, 3=done
  int get stepIndex {
    switch (_step) {
      case LivenessStep.blink:
        return 0;
      case LivenessStep.turnLeft:
        return 1;
      case LivenessStep.turnRight:
        return 2;
      case LivenessStep.done:
        return 3;
    }
  }

  String get currentInstruction {
    switch (_step) {
      case LivenessStep.blink:
        return "Blink your eyes";
      case LivenessStep.turnLeft:
        return "Turn your head LEFT";
      case LivenessStep.turnRight:
        return "Turn your head RIGHT";
      case LivenessStep.done:
        return "Hold still...";
    }
  }

  void reset() {
    _step = LivenessStep.blink;
    _stepStart = DateTime.now();
  }

  /// Returns true only when all liveness steps are complete.
  /// Updates internal state and returns the current instruction via [currentInstruction].
  bool process(Face face) {
    // Timeout — reset if user takes too long on a step
    if (DateTime.now().difference(_stepStart).inSeconds > _stepTimeoutSec) {
      reset();
      return false;
    }

    switch (_step) {
      case LivenessStep.blink:
        final l = face.leftEyeOpenProbability ?? 1.0;
        final r = face.rightEyeOpenProbability ?? 1.0;
        if (l < 0.25 && r < 0.25) {
          _advance(LivenessStep.turnLeft);
        }
        return false;

      case LivenessStep.turnLeft:
        if ((face.headEulerAngleY ?? 0) < -18) {
          _advance(LivenessStep.turnRight);
        }
        return false;

      case LivenessStep.turnRight:
        if ((face.headEulerAngleY ?? 0) > 18) {
          _advance(LivenessStep.done);
        }
        return false;

      case LivenessStep.done:
        return true;
    }
  }

  void _advance(LivenessStep next) {
    _step = next;
    _stepStart = DateTime.now();
  }
}
