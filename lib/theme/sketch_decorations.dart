import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';
import 'package:scribble_guess/theme/app_spacing.dart';

/// The hand-drawn outline every panel, button and dialog in the app is drawn
/// with.
///
/// A perfectly straight rounded rectangle reads as "software"; a line that
/// wobbles slightly reads as "someone drew this". The wobble here is
/// *deterministic*: the jitter is derived from [seed] through a small integer
/// hash, so a given widget's border looks identical on every frame. Randomising
/// per paint would make the whole UI shimmer, which is both ugly and, for
/// motion-sensitive players, genuinely unpleasant.
///
/// Two passes are stroked with slightly different jitter, the way a pen doubles
/// back over a line, which is what sells the effect at a glance.
class SketchBorderPainter extends CustomPainter {
  const SketchBorderPainter({
    required this.color,
    required this.seed,
    this.strokeWidth = AppSpacing.border,
    this.radius = AppSpacing.radiusMd,
    this.fillColor,
    this.amplitude = 1.1,
    this.passes = 2,
  });

  /// Ink colour of the outline.
  final Color color;

  /// Fixes the wobble. Equal seeds produce identical borders.
  final int seed;

  final double strokeWidth;
  final double radius;

  /// Painted inside the outline when set.
  final Color? fillColor;

  /// How far, in logical pixels, the line may stray from true.
  final double amplitude;

  /// How many times the outline is traced. Two looks hand-drawn; one looks thin.
  final int passes;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Rect rect = Offset.zero & size;
    final double r = math.min(radius, math.min(size.width, size.height) / 2);

    if (fillColor != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r)),
        Paint()
          ..color = fillColor!
          ..style = PaintingStyle.fill,
      );
    }

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (int pass = 0; pass < passes; pass++) {
      canvas.drawPath(_wobblyRRect(rect, r, seed + pass * 7919), paint);
    }
  }

  /// Walks the rounded rectangle and nudges each sampled point off true.
  Path _wobblyRRect(Rect rect, double r, int passSeed) {
    final Path source = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));

    final Path out = Path();
    // Sample roughly every 9 logical pixels: dense enough that the wobble
    // reads as a drawn line, sparse enough to stay cheap on a repaint.
    const double step = 9;
    int index = 0;

    for (final PathMetric metric in source.computeMetrics()) {
      final double length = metric.length;
      if (length <= 0) continue;
      final int samples = math.max(4, (length / step).ceil());
      bool started = false;

      for (int i = 0; i <= samples; i++) {
        final double distance = length * (i / samples);
        final Tangent? tangent = metric.getTangentForOffset(distance);
        if (tangent == null) continue;

        // Displace along the normal so the line bulges in and out rather than
        // sliding along itself, which would just shorten the path.
        final double noise = SketchNoise.at(passSeed, index++) * amplitude;
        final Offset normal = Offset(-tangent.vector.dy, tangent.vector.dx);
        final Offset point = tangent.position + normal * noise;

        if (!started) {
          out.moveTo(point.dx, point.dy);
          started = true;
        } else {
          out.lineTo(point.dx, point.dy);
        }
      }
      out.close();
    }
    return out;
  }

  @override
  bool shouldRepaint(SketchBorderPainter old) =>
      old.color != color ||
      old.seed != seed ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius ||
      old.fillColor != fillColor ||
      old.amplitude != amplitude ||
      old.passes != passes;
}

/// Wraps [child] in a hand-drawn outline.
///
/// Prefer this over a `BoxDecoration` border anywhere the shape is part of the
/// game's chrome. The painter sits behind the child, so padding belongs on the
/// child, not here.
class SketchBorder extends StatelessWidget {
  const SketchBorder({
    required this.child,
    required this.color,
    this.seed,
    this.strokeWidth = AppSpacing.border,
    this.radius = AppSpacing.radiusMd,
    this.fillColor,
    super.key,
  });

  final Widget child;
  final Color color;

  /// Defaults to a hash of the widget's key or identity when omitted, which
  /// keeps neighbouring panels from sharing an identical wobble.
  final int? seed;

  final double strokeWidth;
  final double radius;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SketchBorderPainter(
        color: color,
        seed: seed ?? identityHashCode(key ?? child),
        strokeWidth: strokeWidth,
        radius: radius,
        fillColor: fillColor,
      ),
      child: child,
    );
  }
}

/// Deterministic seeds for the sketch borders, so a widget's wobble is stable
/// across rebuilds but differs from its neighbours'.
abstract final class SketchSeeds {
  /// A seed derived from any stable string, such as a player or room id.
  static int of(String value) {
    int hash = 0x811C9DC5;
    for (final int unit in value.codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0x7FFFFFFF;
    }
    return hash;
  }

  /// A seed for the nth item of a list.
  static int index(int i) => 0x5BF03635 ^ (i * 0x9E3779B1) & 0x7FFFFFFF;
}

/// The wobble behind every hand-drawn line in the app.
///
/// A plain integer hash (the finaliser from MurmurHash3), not a `Random`: it
/// needs no state, so any point of any stroke can be evaluated on its own and
/// always produces the same answer. That is what keeps a border — or the brand
/// mark — identical on every frame instead of shimmering.
abstract final class SketchNoise {
  /// A stable pseudo-random value in `[-1, 1]` for `(seed, index)`.
  static double at(int seed, int index) {
    int h = (seed * 0x9E3779B1) ^ (index * 0x85EBCA77);
    h &= 0x7FFFFFFF;
    h ^= h >> 15;
    h = (h * 0x2C1B3C6D) & 0x7FFFFFFF;
    h ^= h >> 12;
    h = (h * 0x297A2D39) & 0x7FFFFFFF;
    h ^= h >> 15;
    return (h % 2000) / 1000.0 - 1.0;
  }
}
