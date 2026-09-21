/// Represents a 2D coordinate point with sub-pixel precision.
class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point2D &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2D($x, $y)';
}
