import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/painting.dart';
import 'package:scribble_guess/theme/app_colors.dart';

/// The Scribble & Guess mark, as pure geometry.
///
/// One continuous pen stroke that starts as a scribble and ends as a question
/// mark — the two things a player actually does, drawn without lifting the
/// pen. The stroke is deliberately smooth at every junction (each curve leaves
/// a point in the direction the previous one arrived), so it reads as one
/// confident line rather than several pieces stuck together.
///
/// It is described exactly once, here, in an abstract 100×100 box. Everything
/// else — the in-app logo, the launcher icons on five platforms, the splash
/// art — is this same path scaled to fit, so there is no master PNG anywhere
/// that can drift out of sync with the app.
///
/// See `tool/generate_brand_assets.dart` for the renderer that turns it into
/// platform bitmaps.
abstract final class Brand {
  /// The abstract box the geometry below is expressed in.
  static const Size designSize = Size(100, 100);

  /// Pen width, in design units.
  static const double strokeWidth = 5.2;

  /// Centre of the question mark's dot, in design units.
  static const Offset dotCenter = Offset(57.5, 82);

  /// Radius of that dot. Slightly fatter than the pen, the way a marker dab is.
  static const double dotRadius = 4.3;

  /// The one stroke: scribble, then question mark.
  ///
  /// Read it as a pen moving. It shades back and forth in the lower left,
  /// climbs out of the last pass, loops over the top, comes down the right
  /// shoulder and curls into the stem.
  static Path pen() {
    return Path()
      // The scribble: two shading passes, left to right and back.
      ..moveTo(14, 80)
      ..lineTo(35, 74.5)
      ..lineTo(14, 68)
      ..lineTo(36, 61.5)
      // Out of the scribble and up into the hook.
      ..cubicTo(41, 57, 40, 46, 39, 38)
      // Over the top.
      ..cubicTo(36, 24, 47, 13, 61, 15)
      // Down the right shoulder.
      ..cubicTo(75, 17, 81, 31, 72, 40)
      // Curl in to meet the stem.
      ..cubicTo(66, 46, 60, 49, 59, 58)
      // The stem.
      ..lineTo(58, 70);
  }

  /// Everything [pen] and the dot cover, ink width included.
  ///
  /// Used to centre and scale the mark into whatever box it is given, so the
  /// composition sits true without anyone hand-tuning offsets per platform.
  static final Rect bounds = _measure();

  /// Walks the stroke and takes the extremes of where it actually goes.
  ///
  /// Deliberately not `Path.getBounds()`: that returns the bounds of the
  /// control points, and this path is mostly cubics whose handles reach well
  /// outside the curve. Trusting it would pad the right edge and the top with
  /// space nothing is drawn in, and every icon would sit visibly low and left.
  static Rect _measure() {
    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;

    for (final PathMetric metric in pen().computeMetrics()) {
      final int samples = math.max(32, (metric.length / 1.5).ceil());
      for (int i = 0; i <= samples; i++) {
        final Tangent? point = metric.getTangentForOffset(
          metric.length * (i / samples),
        );
        if (point == null) continue;
        left = math.min(left, point.position.dx);
        top = math.min(top, point.position.dy);
        right = math.max(right, point.position.dx);
        bottom = math.max(bottom, point.position.dy);
      }
    }

    return Rect.fromLTRB(left, top, right, bottom)
        .inflate(strokeWidth / 2)
        .expandToInclude(Rect.fromCircle(center: dotCenter, radius: dotRadius));
  }

  /// Fraction of a launcher icon's width the mark should occupy.
  ///
  /// Distinct from the adaptive/maskable value below because a plain icon is
  /// never cropped, so it can afford to be bolder.
  static const double iconScale = 0.62;

  /// Fraction for icons the platform is allowed to crop.
  ///
  /// An Android adaptive icon is drawn on a 108dp canvas of which only the
  /// central 72dp is guaranteed to survive the launcher's mask, and Material's
  /// keyline for a square inside that is 60dp — which is what this is: 60 of
  /// 108. A web maskable icon guarantees a more generous central 80%, so the
  /// same number is safe there too and the mark stays one size across both.
  static const double maskableScale = 0.56;

  /// Ink for the platform icons.
  ///
  /// Fixed rather than theme-aware: a launcher icon is baked once and has no
  /// idea what the phone's brightness will be, so it carries its own paper
  /// with it and reads on any home screen.
  static const Color iconInk = AppColors.ink;

  /// The paper every platform icon is printed on.
  static const Color iconPaper = AppColors.paper;

  /// The one spot of colour: the dot under the question mark.
  static const Color iconAccent = AppColors.accentRed;
}
