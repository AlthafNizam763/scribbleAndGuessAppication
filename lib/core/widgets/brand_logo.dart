import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The five colours one drawing of the mark is printed in.
///
/// Passed around as a set rather than read from a theme, because the same
/// painter serves both the in-app logo, which may follow brightness, and the
/// baked launcher icons, which cannot — a PNG has no idea what the phone will
/// be set to when somebody looks at it.
@immutable
class BrandInk {
  const BrandInk({
    required this.fur,
    required this.outline,
    required this.light,
    required this.accent,
  });

  /// The full-colour mark: orange cat, ink outline, cream face, pink ears.
  static const BrandInk full = BrandInk(
    fur: Brand.fur,
    outline: Brand.outline,
    light: Brand.light,
    accent: Brand.accent,
  );

  /// One flat colour throughout, for Android's themed icon layer and anywhere
  /// else that reads alpha and supplies its own colour.
  static BrandInk flat(Color color) =>
      BrandInk(fur: color, outline: color, light: color, accent: color);

  /// A two-tone cut for placement over a coloured surface: the coat takes the
  /// surface's own ink, and the face stays pale so the expression survives.
  static BrandInk mono({required Color ink, required Color paper}) =>
      BrandInk(fur: ink, outline: ink, light: paper, accent: paper);

  /// The coat.
  final Color fur;

  /// Every outline and crease.
  final Color outline;

  /// Muzzle, paw and the two shut eyes.
  final Color light;

  /// Inner ears.
  final Color accent;

  @override
  bool operator ==(Object other) =>
      other is BrandInk &&
      other.fur == fur &&
      other.outline == outline &&
      other.light == light &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(fur, outline, light, accent);
}

/// Paints the STUPID GAMES cat into whatever box it is given.
///
/// [Brand] holds the geometry; this holds the order things are laid down in,
/// which is the part that actually matters. The cat is built back to front —
/// tail, body, ears, face, then the raised paw last — so the paw sits over the
/// muzzle rather than beside it, and the whole thing reads as one creature
/// instead of a pile of shapes.
///
/// Outlines are proportional to the rendered size rather than fixed in design
/// units, so the mark carries the same visual weight as a 16-pixel favicon and
/// as a 1024-pixel store listing.
class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({this.ink = BrandInk.full, this.tilt = 0, this.hop = 0});

  /// The colours this drawing is printed in.
  final BrandInk ink;

  /// Lean, in radians, about [Brand.pivot]. Zero everywhere static; the splash
  /// rocks this through [Brand.laughTilt] and back.
  final double tilt;

  /// Rise, as a fraction of the design box's height. Positive lifts the cat.
  final double hop;

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

    if (tilt != 0 || hop != 0) {
      canvas.translate(Brand.pivot.dx, Brand.pivot.dy - hop * Brand.hopHeight);
      canvas.rotate(tilt);
      canvas.translate(-Brand.pivot.dx, -Brand.pivot.dy);
    }

    // Outline weight in design units: the fraction of the rendered width the
    // brand asks for, floored so it never antialiases away to nothing.
    final double pen = Brand.penFor(
      Brand.outlineRatio * Brand.bounds.width,
      scale,
    );

    final Paint fill = Paint()..isAntiAlias = true;
    final Paint stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ---- behind the cat --------------------------------------------------
    // The tail is drawn first and outlined by over-stroking: a fat outline
    // pass, then the coat laid inside it. Cheaper and more reliable than
    // asking Skia for the outline of a stroked path.
    stroke
      ..color = ink.outline
      ..strokeWidth = Brand.tailWidth + pen * 2;
    canvas.drawPath(Brand.tail(), stroke);
    stroke
      ..color = ink.fur
      ..strokeWidth = Brand.tailWidth;
    canvas.drawPath(Brand.tail(), stroke);

    // ---- the body --------------------------------------------------------
    final Path body = Brand.silhouette();
    fill.color = ink.fur;
    canvas.drawPath(body, fill);

    // Inner ears go on before the outline, so the outline closes over them.
    fill.color = ink.accent;
    canvas.drawPath(Brand.innerEar(mirrored: false), fill);
    canvas.drawPath(Brand.innerEar(mirrored: true), fill);

    stroke
      ..color = ink.outline
      ..strokeWidth = pen;
    canvas.drawPath(body, stroke);

    // ---- the face --------------------------------------------------------
    fill.color = ink.light;
    canvas.drawPath(Brand.muzzle(), fill);

    stroke
      ..color = ink.outline
      ..strokeWidth = Brand.eyeWidth;
    canvas.drawPath(Brand.eyes(), stroke);

    stroke
      ..color = ink.outline
      ..strokeWidth = Brand.whiskerWidth;
    canvas.drawPath(Brand.whiskers(), stroke);

    // ---- the raised paw, last, so it covers the mouth ---------------------
    //
    // The paw is drawn with no arm behind it, on purpose. Every version that
    // had one put a closed, outlined stub in the middle of the chest, which
    // reads as something hanging off the cat rather than as its own limb — and
    // at launcher size it is the first detail to turn to mush. The paw alone
    // on the muzzle carries the whole gag.
    final Path paw = Brand.paw();
    fill.color = ink.light;
    canvas.drawPath(paw, fill);
    stroke
      ..color = ink.outline
      ..strokeWidth = pen;
    canvas.drawPath(paw, stroke);
    stroke.strokeWidth = Brand.toeWidth;
    canvas.drawPath(Brand.toes(), stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandMarkPainter old) =>
      old.ink != ink || old.tilt != tilt || old.hop != hop;
}

/// The STUPID GAMES cat on its own, sized and inked for the theme.
///
/// Use this wherever the brand needs to appear without its name — a compact
/// app bar, an empty state, a loading beat. Pair it with [BrandWordmark], or
/// reach for [BrandLogo] to get both already locked up.
class BrandMark extends StatelessWidget {
  const BrandMark({
    this.size = 72,
    this.ink = BrandInk.full,
    this.tilt = 0,
    this.hop = 0,
    this.semanticLabel,
    super.key,
  });

  /// Edge of the square the mark is fitted into.
  final double size;

  /// The colours it is printed in.
  final BrandInk ink;

  /// Lean, in radians.
  final double tilt;

  /// Rise, as a fraction of [Brand.hopHeight].
  final double hop;

  /// Announced to screen readers. Leave null inside a lockup, where the
  /// wordmark beside it already says the name.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: BrandMarkPainter(ink: ink, tilt: tilt, hop: hop),
          isComplex: true,
          willChange: tilt != 0 || hop != 0,
        ),
      ),
    );
  }
}

/// The app name, set as the STUPID GAMES logotype.
///
/// Two halves doing two jobs. **STUPID** is the loud one: every letter is its
/// own tile, rocked a few degrees off true and alternating through the brand
/// colours, so the word looks like it fell downstairs. **GAMES** underneath is
/// straight, single-coloured and widely tracked — it is the half that has to
/// stay legible at a glance, and it steadies the word above it.
///
/// Both halves are outlined by painting each glyph twice: a stroked pass in
/// ink, then the fill on top. That is what makes the letters read as chunky
/// cartoon type rather than as a bold system font.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    this.height = 44,
    this.outline,
    this.semanticLabel,
    super.key,
  });

  /// Cap height of the STUPID row, in logical pixels. Everything else in the
  /// lockup is derived from it, so one number scales the whole logotype.
  final double height;

  /// Colour every glyph is outlined in. Defaults to the theme's ink, so the
  /// wordmark stays legible on both paper and night.
  final Color? outline;

  /// Announced to screen readers. Defaults to the app's name.
  final String? semanticLabel;

  /// The colours STUPID cycles through, letter by letter.
  static const List<Color> _riot = <Color>[
    AppColors.violet,
    AppColors.coral,
    AppColors.aqua,
    AppColors.brandOrange,
    AppColors.violet,
    AppColors.coral,
  ];

  /// How far each letter of STUPID leans, in degrees. Hand-set rather than
  /// random: the word has to look thrown, but identically thrown every time
  /// it is drawn, or the logo shimmers between frames.
  static const List<double> _lean = <double>[-7, 5, -3, 8, -5, 4];

  /// And how far each one sits off the baseline, as a fraction of [height].
  static const List<double> _drop = <double>[0.06, -0.04, 0.03, -0.06, 0.05, 0];

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final Color edge = outline ?? colors.text;
    const String loud = 'STUPID';

    return Semantics(
      label: semanticLabel ?? context.l10n.appName,
      image: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < loud.length; i++)
                  Transform.translate(
                    offset: Offset(0, _drop[i] * height),
                    child: Transform.rotate(
                      angle: _lean[i] * math.pi / 180,
                      child: _Glyph(
                        character: loud[i],
                        size: height,
                        fill: _riot[i],
                        outline: edge,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: height * 0.04),
            _Glyph(
              character: 'GAMES',
              size: height * 0.64,
              fill: AppColors.brandAqua,
              outline: edge,
              tracking: height * 0.1,
            ),
          ],
        ),
      ),
    );
  }
}

/// One outlined glyph — or one outlined word, for the calmer half.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.character,
    required this.size,
    required this.fill,
    required this.outline,
    this.tracking = 0,
  });

  final String character;
  final double size;
  final Color fill;
  final Color outline;
  final double tracking;

  @override
  Widget build(BuildContext context) {
    // Plus Jakarta Sans ExtraBold is the chunkiest face the app ships, and at
    // this weight it takes an outline without the counters filling in.
    final TextStyle base = TextStyle(
      fontFamily: AppTypography.bodyFamily,
      fontWeight: AppTypography.black,
      fontSize: size,
      height: 1,
      letterSpacing: tracking,
    );

    return Stack(
      children: <Widget>[
        Text(
          character,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.14
              ..strokeJoin = StrokeJoin.round
              ..color = outline
              ..isAntiAlias = true,
          ),
        ),
        Text(character, style: base.copyWith(color: fill)),
      ],
    );
  }
}

/// The full lockup: cat, name, and an optional line under it.
///
/// This is the app signature — the splash and the sign-in gate both open with
/// it, so the two stay identical without either screen owning the arrangement.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    this.markSize = 96,
    this.caption,
    this.captionColor,
    this.tilt = 0,
    this.hop = 0,
    super.key,
  });

  /// Edge of the square the cat is drawn in.
  final double markSize;

  /// A line under the name — the tagline, usually, or a status message.
  final String? caption;

  /// Colour of that line. Defaults to the theme's soft ink.
  final Color? captionColor;

  /// Lean passed through to the cat.
  final double tilt;

  /// Rise passed through to the cat.
  final double hop;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BrandMark(size: markSize, tilt: tilt, hop: hop),
        SizedBox(height: markSize * 0.14),
        BrandWordmark(height: markSize * 0.42),
        if (caption != null) ...<Widget>[
          SizedBox(height: markSize * 0.16),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: captionColor ?? colors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
