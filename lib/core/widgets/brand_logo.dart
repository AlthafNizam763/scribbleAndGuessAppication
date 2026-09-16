import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/theme/theme.dart';

/// Paints the Scribble & Guess mark into whatever box it is given.
///
/// [Brand] holds the geometry; this holds the hand. The path is resampled and
/// nudged off true with [SketchNoise] — the same deterministic jitter every
/// border in the app uses — then traced twice, the second pass fainter, the
/// way a pen doubles back over a line. Because the jitter is a pure function
/// of [seed], the logo looks identical on every frame instead of shimmering.
///
/// Colours are passed in rather than read from a theme, so one painter serves
/// both the in-app logo, which follows brightness, and the baked launcher
/// icons, which cannot.
class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({
    required this.ink,
    required this.accent,
    this.seed = defaultSeed,
    this.amplitude = 0.5,
    this.passes = 2,
  });

  /// The wobble the brand is drawn with. Pinned so the mark is the same shape
  /// in the app as it is in the launcher.
  static const int defaultSeed = 0x5C81BB;

  /// Colour of the stroke itself.
  final Color ink;

  /// Colour of the question mark's dot — the one spot of colour in the mark.
  final Color accent;

  /// Fixes the wobble. Equal seeds produce an identical mark.
  final int seed;

  /// How far, in design units, the line may stray from true.
  final double amplitude;

  /// How many times the stroke is traced. Two reads as pen; one reads as font.
  final int passes;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Rect box = Brand.bounds;
    final double scale = math.min(
      size.width / box.width,
      size.height / box.height,
    );

    canvas.save();
    // Centre the mark's true bounds in the box, rather than trusting the
    // design coordinates to already be centred.
    canvas.translate(
      (size.width - box.width * scale) / 2 - box.left * scale,
      (size.height - box.height * scale) / 2 - box.top * scale,
    );
    canvas.scale(scale);

    final Paint pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Brand.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final Path source = Brand.pen();
    for (int pass = 0; pass < passes; pass++) {
      pen.color = pass == 0 ? ink : ink.withValues(alpha: ink.a * 0.5);
      canvas.drawPath(
        _jitter(source, seed: seed + pass * 7919, amplitude: amplitude),
        pen,
      );
    }

    // The dot, laid down as a single short dab so it keeps the round end and
    // slight ovality of a real marker rather than looking like a stamped disc.
    const double lean = Brand.dotRadius * 0.16;
    canvas.drawLine(
      Brand.dotCenter.translate(SketchNoise.at(seed, 901) * amplitude, -lean),
      Brand.dotCenter.translate(SketchNoise.at(seed, 902) * amplitude, lean),
      Paint()
        ..color = accent
        ..strokeWidth = Brand.dotRadius * 2
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandMarkPainter old) =>
      old.ink != ink ||
      old.accent != accent ||
      old.seed != seed ||
      old.amplitude != amplitude ||
      old.passes != passes;
}

/// Resamples [source] and displaces each point along the path's normal.
///
/// Displacing along the normal rather than in a free direction makes the line
/// bulge in and out instead of sliding along itself, which would only shorten
/// it. The result is an open path: brand strokes are lines, never loops.
Path _jitter(
  Path source, {
  required int seed,
  required double amplitude,
  double step = 2.2,
}) {
  final Path out = Path();
  int index = 0;

  for (final PathMetric metric in source.computeMetrics()) {
    final double length = metric.length;
    if (length <= 0) continue;
    final int samples = math.max(8, (length / step).ceil());
    bool started = false;

    for (int i = 0; i <= samples; i++) {
      final Tangent? tangent = metric.getTangentForOffset(
        length * (i / samples),
      );
      if (tangent == null) continue;

      final double noise = SketchNoise.at(seed, index++) * amplitude;
      final Offset normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final Offset point = tangent.position + normal * noise;

      if (!started) {
        out.moveTo(point.dx, point.dy);
        started = true;
      } else {
        out.lineTo(point.dx, point.dy);
      }
    }
  }
  return out;
}

/// The Scribble & Guess symbol on its own, sized and inked for the theme.
///
/// Use this wherever the brand needs to appear without its name — a compact
/// app bar, an empty state, a loading beat. Pair it with [BrandWordmark], or
/// reach for [BrandLogo] to get both already locked up.
class BrandMark extends StatelessWidget {
  const BrandMark({
    this.size = 72,
    this.ink,
    this.accent,
    this.seed = BrandMarkPainter.defaultSeed,
    this.semanticLabel,
    super.key,
  });

  /// Edge of the square the mark is fitted into.
  final double size;

  /// Stroke colour. Defaults to the active theme's ink.
  final Color? ink;

  /// Dot colour. Defaults to the active theme's felt-tip red.
  final Color? accent;

  /// Fixes the wobble.
  final int seed;

  /// Announced to screen readers. Leave null inside a lockup, where the
  /// wordmark beside it already says the name.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: BrandMarkPainter(
            ink: ink ?? colors.ink,
            accent: accent ?? colors.accentRed,
            seed: seed,
          ),
          isComplex: true,
          willChange: false,
        ),
      ),
    );
  }
}

/// The app name, hand-lettered, over a drawn swash.
///
/// The swash is not decoration for its own sake: PatrickHand at display size
/// sits high and airy, and a line beneath gives the name something to stand
/// on, so it reads as a logotype rather than as a heading.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    this.style,
    this.color,
    this.underline = true,
    this.seed = 0x2D7A11,
    super.key,
  });

  /// Defaults to the theme's `displaySmall` — the marker face, at 36.
  final TextStyle? style;

  /// Letter colour. Defaults to the active theme's ink.
  final Color? color;

  /// Whether to draw the swash beneath the name.
  final bool underline;

  /// Fixes the swash's wobble.
  final int seed;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextStyle base =
        style ??
        Theme.of(context).textTheme.displaySmall ??
        const TextStyle(fontSize: 36);
    final TextStyle effective = base.copyWith(color: color ?? colors.ink);
    final double scale = effective.fontSize ?? 36;

    final Widget name = Text(
      context.l10n.appName,
      textAlign: TextAlign.center,
      style: effective,
    );
    if (!underline) return name;

    // IntrinsicWidth so the swash spans exactly the lettering, however wide
    // the name renders at this size, rather than the whole available width.
    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          name,
          SizedBox(
            height: scale * 0.22,
            child: CustomPaint(
              painter: _SwashPainter(
                color: effective.color ?? colors.ink,
                strokeWidth: scale * 0.055,
                seed: seed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line under the wordmark: one shallow arc, traced twice.
class _SwashPainter extends CustomPainter {
  const _SwashPainter({
    required this.color,
    required this.strokeWidth,
    required this.seed,
  });

  final Color color;
  final double strokeWidth;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Path source = Path()
      ..moveTo(size.width * 0.02, size.height * 0.74)
      ..quadraticBezierTo(
        size.width * 0.52,
        size.height * 0.04,
        size.width * 0.98,
        size.height * 0.56,
      );

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (int pass = 0; pass < 2; pass++) {
      paint.color = pass == 0 ? color : color.withValues(alpha: color.a * 0.4);
      canvas.drawPath(
        _jitter(
          source,
          seed: seed + pass * 7919,
          amplitude: strokeWidth * 0.6,
          step: size.width / 14,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SwashPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.seed != seed;
}

/// The full lockup: mark, name, and an optional line under it.
///
/// This is the app signature — the splash and the main menu both open with
/// it, so the two stay identical without either screen owning the arrangement.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    this.markSize = 72,
    this.caption,
    this.captionColor,
    this.nameStyle,
    super.key,
  });

  /// Edge of the square the symbol is drawn in.
  final double markSize;

  /// A line under the name — the tagline, usually, or a status message.
  final String? caption;

  /// Colour of that line. Defaults to the theme's soft ink.
  final Color? captionColor;

  /// Overrides the wordmark's type style.
  final TextStyle? nameStyle;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BrandMark(size: markSize),
        SizedBox(height: markSize * 0.22),
        BrandWordmark(style: nameStyle),
        if (caption != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: captionColor ?? colors.inkSoft,
            ),
          ),
        ],
      ],
    );
  }
}
