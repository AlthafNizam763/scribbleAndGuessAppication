import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:scribble_guess/models/stroke_point.dart';

/// Pure canvas geometry: normalization, simplification and aspect fitting.
///
/// Stroke coordinates travel over the wire normalized to the `0..1` box so a
/// drawing looks identical on every screen size. Everything here is a pure
/// function of its arguments, which keeps it trivially testable.
abstract final class Geometry {
  /// Converts a local canvas [Offset] into a [StrokePoint] in `0..1`.
  ///
  /// A zero or non-finite [size] collapses to the origin instead of dividing
  /// by zero, and the result is always clamped to the canvas box.
  static StrokePoint normalize(Offset local, Size size) => StrokePoint(
        x: _clamp01(_ratio(local.dx, size.width)),
        y: _clamp01(_ratio(local.dy, size.height)),
      );

  /// Converts a normalized [p] back into a local [Offset] inside [size].
  static Offset denormalize(StrokePoint p, Size size) =>
      Offset(p.x * size.width, p.y * size.height);

  /// Reduces [points] with the Ramer-Douglas-Peucker algorithm.
  ///
  /// [tolerance] is expressed in normalized canvas units. The first and last
  /// points are always kept, the input order is preserved, and inputs of two
  /// points or fewer — or a non-positive [tolerance] — are returned untouched.
  /// The recursion is done with an explicit stack so long strokes cannot blow
  /// the call stack.
  static List<StrokePoint> simplify(List<StrokePoint> points, double tolerance) {
    if (points.length <= 2 || tolerance <= 0 || !tolerance.isFinite) {
      return points;
    }
    final int last = points.length - 1;
    final List<bool> keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[last] = true;
    final List<({int end, int start})> pending = <({int end, int start})>[
      (start: 0, end: last),
    ];
    while (pending.isNotEmpty) {
      final ({int end, int start}) span = pending.removeLast();
      double worst = 0;
      int worstIndex = -1;
      for (int i = span.start + 1; i < span.end; i++) {
        final double distance = distanceToSegment(
          points[i],
          points[span.start],
          points[span.end],
        );
        if (distance > worst) {
          worst = distance;
          worstIndex = i;
        }
      }
      if (worstIndex >= 0 && worst > tolerance) {
        keep[worstIndex] = true;
        pending.add((start: span.start, end: worstIndex));
        pending.add((start: worstIndex, end: span.end));
      }
    }
    return <StrokePoint>[
      for (int i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }

  /// Shortest distance from [p] to the segment `a..b`.
  ///
  /// A degenerate segment (`a == b`) falls back to the distance to [a].
  static double distanceToSegment(StrokePoint p, StrokePoint a, StrokePoint b) {
    final double dx = b.x - a.x;
    final double dy = b.y - a.y;
    final double lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 0) {
      return _length(p.x - a.x, p.y - a.y);
    }
    final double t =
        _clamp01(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared);
    return _length(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
  }

  /// The largest box of [aspectRatio] (width / height) that fits [available].
  ///
  /// Returns [Size.zero] when [available] has no room or [aspectRatio] is not
  /// a positive finite number.
  static Size fitAspect(Size available, double aspectRatio) {
    if (aspectRatio <= 0 || !aspectRatio.isFinite) {
      return Size.zero;
    }
    final double width = available.width;
    final double height = available.height;
    if (width <= 0 || height <= 0) {
      return Size.zero;
    }
    final double heightForWidth = width / aspectRatio;
    if (heightForWidth <= height) {
      return Size(width, heightForWidth);
    }
    return Size(height * aspectRatio, height);
  }

  /// [value] divided by [extent], or `0` when [extent] cannot be divided by.
  static double _ratio(double value, double extent) =>
      extent > 0 && extent.isFinite ? value / extent : 0;

  /// [value] pulled into `0..1`, mapping `NaN` to `0`.
  static double _clamp01(double value) {
    if (value.isNaN || value < 0) {
      return 0;
    }
    return value > 1 ? 1 : value;
  }

  /// Euclidean length of the vector `(dx, dy)`.
  static double _length(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}
