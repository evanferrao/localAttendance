import 'dart:math';

class FrameBuffer {
  final int maxFrames;
  final List<List<double>> _frames = [];

  FrameBuffer({this.maxFrames = 5});

  void add(List<double> embedding) {
    if (_frames.length >= maxFrames) _frames.removeAt(0);
    _frames.add(embedding);
  }

  bool get isFull => _frames.length >= maxFrames;
  int get length => _frames.length;

  List<double> get average {
    final size = _frames.first.length;
    final avg = List<double>.filled(size, 0.0);
    for (final f in _frames) {
      for (int i = 0; i < size; i++) {
        avg[i] += f[i];
      }
    }
    return avg.map((e) => e / _frames.length).toList();
  }

  /// Mean frame-to-frame distance — low variance = static image (spoof)
  double get motionVariance {
    if (_frames.length < 2) return 1.0; // assume ok if not enough data
    double total = 0;
    for (int i = 1; i < _frames.length; i++) {
      total += _distance(_frames[i], _frames[i - 1]);
    }
    return total / (_frames.length - 1);
  }

  double _distance(List<double> a, List<double> b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sqrt(sum);
  }

  void reset() => _frames.clear();
}
