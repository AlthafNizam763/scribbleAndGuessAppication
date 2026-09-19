import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/widgets/avatar_art.dart';

/// Draws one [AvatarFace] into whatever box it is given.
///
/// Every character is composed in a fixed 100x100 design box and scaled to
/// fit, so the same drawing serves a 26px row avatar and a 96px profile hero
/// without a second asset. Nothing here is an image: the app ships no avatar
/// files at all, which is why a face costs nothing to add and never has to be
/// downloaded before a room can start.
///
/// ## Ten cats, one skull
///
/// Every character is the same head — [_ears] then [_head] — with a different
/// expression drawn on it. That is not laziness, it is the brand: these are
/// meant to read as ten moods of one animal, the one in the app icon, rather
/// than as ten unrelated drawings. A new cat is a new [AvatarShape] case and a
/// handful of lines, and it cannot drift out of family because it inherits the
/// silhouette.
///
/// Order of construction is always the same — shoulders, ears, head, then the
/// features — so overlaps read as depth rather than as stacked outlines.
class AvatarArtPainter extends CustomPainter {
  /// Paints [face], tracing its outlines [weight] times as thick as the base.
  const AvatarArtPainter({required this.face, this.weight = 1});

  /// The side of the square design box every character is drawn in.
  static const double box = 100;

  /// Base outline width, in design units.
  static const double _stroke = 3;

  /// The character to draw.
  final AvatarFace face;

  /// Outline multiplier.
  ///
  /// Line weight is scaled down with the avatar like everything else, so at
  /// row size the outlines would thin to nothing; small avatars pass a value
  /// above one to hold the drawing together.
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) {
      return;
    }
    canvas.save();
    canvas.scale(size.width / box, size.height / box);

    final void Function(Canvas canvas) draw = switch (face.shape) {
      AvatarShape.sleeping => _sleeping,
      AvatarShape.laughing => _laughing,
      AvatarShape.angry => _angry,
      AvatarShape.confused => _confused,
      AvatarShape.shocked => _shocked,
      AvatarShape.dancing => _dancing,
      AvatarShape.lazy => _lazy,
      AvatarShape.smug => _smug,
      AvatarShape.scared => _scared,
      AvatarShape.chaotic => _chaotic,
    };
    draw(canvas);

    canvas.restore();
  }

  @override
  bool shouldRepaint(AvatarArtPainter old) =>
      old.face.id != face.id || old.weight != weight;

  // ------------------------------------------------------------------ pens ---

  Paint _fill(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  Paint _pen([double scale = 1]) => Paint()
    ..color = AvatarPigments.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = _stroke * weight * scale
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  /// Fills [path] and traces it, the way every shape in the app is drawn.
  void _ink(Canvas c, Path path, Color color, [double scale = 1]) {
    c.drawPath(path, _fill(color));
    c.drawPath(path, _pen(scale));
  }

  /// Runs [draw], then runs it again flipped about the vertical centre line.
  ///
  /// Ears, eyes and whiskers are only ever described once, on the left.
  void _mirror(Canvas c, void Function(Canvas canvas) draw) {
    draw(c);
    c.save();
    c.translate(box, 0);
    c.scale(-1, 1);
    draw(c);
    c.restore();
  }

  // ---------------------------------------------------------------- pieces ---

  /// Head and shoulders, cut off by the disc.
  void _bust(Canvas c) {
    final Path body = Path()
      ..moveTo(4, 104)
      ..cubicTo(9, 86, 28, 76, 50, 76)
      ..cubicTo(72, 76, 91, 86, 96, 104)
      ..close();
    _ink(c, body, face.cloth);
  }

  /// The oval every cat's head is built on.
  static final Rect _skull = Rect.fromCenter(
    center: const Offset(50, 50),
    width: 60,
    height: 56,
  );

  void _head(Canvas c) => _ink(c, Path()..addOval(_skull), face.fur);

  /// The two ears.
  ///
  /// [droop] folds them down — a scared or sleeping cat pins its ears, and it
  /// is the single strongest signal of mood in the whole drawing, worth more
  /// than any amount of work on the eyes.
  void _ears(Canvas c, {double droop = 0}) {
    _mirror(c, (Canvas m) {
      final double tipX = 27 + droop * 6;
      final double tipY = 8 + droop * 26;

      final Path ear = Path()
        ..moveTo(24, 40)
        ..lineTo(tipX, tipY)
        ..lineTo(48, 27)
        ..close();
      _ink(m, ear, face.fur);

      final Path inner = Path()
        ..moveTo(30, 33)
        ..lineTo(tipX + 5, tipY + 9)
        ..lineTo(42, 27)
        ..close();
      _ink(m, inner, AvatarPigments.petal, 0.6);
    });
  }

  /// Three whiskers a side.
  void _whiskers(Canvas c, {double y = 53}) {
    _mirror(c, (Canvas m) {
      for (int i = 0; i < 3; i++) {
        final double row = y + i * 5;
        m.drawLine(Offset(29, row), Offset(9, row - 5), _pen(0.7));
      }
    });
  }

  /// The little triangular nose.
  void _nose(Canvas c, {double y = 54, double width = 11}) {
    final Path snout = Path()
      ..moveTo(50 - width / 2, y)
      ..lineTo(50 + width / 2, y)
      ..lineTo(50, y + width * 0.46)
      ..close();
    _ink(c, snout, AvatarPigments.petal, 0.65);
  }

  void _blush(Canvas c, {double y = 58, double dx = 21, double width = 11}) {
    final Paint warm = _fill(AvatarPigments.blush.withValues(alpha: 0.42));
    _mirror(c, (Canvas m) {
      m.drawOval(
        Rect.fromCenter(
          center: Offset(50 - dx, y),
          width: width,
          height: width * 0.58,
        ),
        warm,
      );
    });
  }

  // ------------------------------------------------------------------ eyes ---

  /// Two round eyes with a catchlight. [r] carries most of the mood.
  void _dotEyes(Canvas c, {double y = 47, double dx = 12, double r = 4.6}) {
    _mirror(c, (Canvas m) {
      final Offset eye = Offset(50 - dx, y);
      m.drawCircle(eye, r, _fill(AvatarPigments.line));
      m.drawCircle(
        eye.translate(-r * 0.3, -r * 0.34),
        r * 0.3,
        _fill(AvatarPigments.light),
      );
    });
  }

  /// Wide eyes with a visible white, for shock and fear.
  void _wideEyes(Canvas c, {double y = 46, double dx = 12, double r = 8}) {
    _mirror(c, (Canvas m) {
      final Offset eye = Offset(50 - dx, y);
      m.drawCircle(eye, r, _fill(AvatarPigments.light));
      m.drawCircle(eye, r, _pen(0.6));
      m.drawCircle(eye.translate(0, 1), r * 0.42, _fill(AvatarPigments.line));
    });
  }

  /// Arcs opening downward: eyes shut in delight.
  void _happyEyes(Canvas c, {double y = 47, double dx = 12, double width = 13}) {
    _mirror(c, (Canvas m) {
      final double cx = 50 - dx;
      final Path arc = Path()
        ..moveTo(cx - width / 2, y + 4)
        ..quadraticBezierTo(cx, y - 6, cx + width / 2, y + 4);
      m.drawPath(arc, _pen(1.2));
    });
  }

  /// Flat closed lids: asleep, not laughing.
  void _shutEyes(Canvas c, {double y = 47, double dx = 12, double width = 13}) {
    _mirror(c, (Canvas m) {
      final double cx = 50 - dx;
      final Path arc = Path()
        ..moveTo(cx - width / 2, y - 2)
        ..quadraticBezierTo(cx, y + 5, cx + width / 2, y - 2);
      m.drawPath(arc, _pen(1.2));
    });
  }

  /// Half-lidded: a lid drawn across an open eye.
  void _lidEyes(Canvas c, {double y = 47, double dx = 12, double r = 5}) {
    _mirror(c, (Canvas m) {
      final Offset eye = Offset(50 - dx, y);
      m.drawCircle(eye, r, _fill(AvatarPigments.line));
      // The lid, in coat colour, clipping the top half off the eye.
      m.drawRect(
        Rect.fromLTRB(eye.dx - r - 1, y - r - 1, eye.dx + r + 1, y - r * 0.15),
        _fill(face.fur),
      );
      m.drawLine(
        Offset(eye.dx - r - 1, y - r * 0.15),
        Offset(eye.dx + r + 1, y - r * 0.15),
        _pen(0.9),
      );
    });
  }

  /// Brows. [angle] tilts them: negative is cross, positive is worried.
  void _brows(Canvas c, {double y = 36, double dx = 12, double width = 13, double angle = 0}) {
    _mirror(c, (Canvas m) {
      final double cx = 50 - dx;
      m.drawLine(
        Offset(cx - width / 2, y - angle),
        Offset(cx + width / 2, y + angle),
        _pen(0.95),
      );
    });
  }

  // ---------------------------------------------------------------- mouths ---

  /// A closed curve. Negative [depth] is a frown.
  void _mouth(Canvas c, {double y = 62, double width = 13, double depth = 6, double scale = 0.9}) {
    final Path path = Path()
      ..moveTo(50 - width / 2, y)
      ..quadraticBezierTo(50, y + depth, 50 + width / 2, y);
    c.drawPath(path, _pen(scale));
  }

  /// An open mouth, with a tongue. The house laugh.
  void _openMouth(Canvas c, {double y = 60, double width = 20, double height = 14}) {
    final Path maw = Path()
      ..addOval(Rect.fromCenter(center: Offset(50, y + height / 2), width: width, height: height));
    _ink(c, maw, AvatarPigments.maw, 0.7);

    final Path tongue = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(50, y + height * 0.78),
          width: width * 0.52,
          height: height * 0.42,
        ),
      );
    c.drawPath(tongue, _fill(AvatarPigments.petal));
  }

  /// The two lines under the nose every closed-mouth cat has.
  void _lips(Canvas c, {double y = 59}) {
    final Path path = Path()
      ..moveTo(50, y)
      ..lineTo(50, y + 3)
      ..moveTo(50, y + 3)
      ..quadraticBezierTo(45, y + 7, 40.5, y + 1.5)
      ..moveTo(50, y + 3)
      ..quadraticBezierTo(55, y + 7, 59.5, y + 1.5);
    c.drawPath(path, _pen(0.75));
  }

  // ---------------------------------------------------------------- the ten ---

  /// Sleeping: ears down, eyes shut, and a `z` floating off.
  void _sleeping(Canvas c) {
    _bust(c);
    _ears(c, droop: 0.55);
    _head(c);
    _shutEyes(c);
    _whiskers(c);
    _nose(c);
    _lips(c);
    _snore(c);
  }

  /// The `Z` of a sleeping cat, as three strokes.
  ///
  /// Drawn rather than typeset, like everything else in this file. A
  /// `TextPainter` inside a painter renders whatever font happens to be
  /// ambient — which in a test environment is none at all, and the glyph comes
  /// out as a filled box. Geometry has no such dependency.
  void _snore(Canvas c) {
    final Path z = Path()
      ..moveTo(74, 14)
      ..lineTo(88, 14)
      ..lineTo(74, 28)
      ..lineTo(88, 28);
    c.drawPath(z, _pen(0.9));
  }

  /// Laughing: the app icon's own face.
  void _laughing(Canvas c) {
    _bust(c);
    _ears(c);
    _head(c);
    _happyEyes(c);
    _whiskers(c);
    _nose(c, y: 50);
    _openMouth(c, y: 57);
    _blush(c, y: 56);
  }

  /// Angry: pinned ears, slanted brows, a hard frown.
  void _angry(Canvas c) {
    _bust(c);
    _ears(c, droop: 0.25);
    _head(c);
    _brows(c, y: 36, angle: 4.5);
    // Whites rather than plain dots: this is the darkest coat on the roster,
    // and ink-on-ink loses the eyes entirely at row size. The brows carry the
    // mood regardless, so the extra contrast costs nothing.
    _wideEyes(c, y: 47, r: 5.6);
    _whiskers(c);
    _nose(c);
    // Negative depth: the same curve, upside down.
    _mouth(c, y: 66, depth: -5);
  }

  /// Confused: head tilted, one brow up, mouth off to one side.
  void _confused(Canvas c) {
    _bust(c);

    // The whole head leans, which is what reads as "confused" before any of
    // the features do. Rotated about the chin so the neck does not detach.
    c.save();
    c.translate(50, 76);
    c.rotate(-0.13);
    c.translate(-50, -76);

    _ears(c);
    _head(c);

    // Asymmetric brows, so they are drawn individually rather than mirrored.
    c.drawLine(const Offset(31, 38), const Offset(44, 33), _pen(0.95));
    c.drawLine(const Offset(56, 34), const Offset(69, 36), _pen(0.95));

    _dotEyes(c, y: 47, r: 4.4);
    _whiskers(c);
    _nose(c);

    // A mouth that gives up halfway across.
    final Path mouth = Path()
      ..moveTo(43, 64)
      ..quadraticBezierTo(50, 68, 57, 62);
    c.drawPath(mouth, _pen(0.9));

    c.restore();

    // The question mark sits outside the tilt, so it stays upright. Drawn as
    // a hook and a dot for the same reason the snore is drawn: a typeset glyph
    // depends on whatever font is ambient.
    final Path hook = Path()
      ..moveTo(75, 16)
      ..cubicTo(75, 8, 89, 8, 88, 16)
      ..cubicTo(87, 22, 82, 22, 82, 27);
    c.drawPath(hook, _pen(0.9));
    c.drawCircle(const Offset(82, 33), 1.9, _fill(AvatarPigments.line));
  }

  /// Shocked: enormous eyes and a tiny mouth.
  void _shocked(Canvas c) {
    _bust(c);
    _ears(c);
    _head(c);
    _brows(c, y: 31, angle: -2);
    _wideEyes(c, y: 46, dx: 13, r: 8.5);
    _whiskers(c, y: 56);
    _nose(c, y: 57, width: 9);

    // A small O. Round, not a curve: surprise is a shape, not a line.
    c.drawCircle(const Offset(50, 68), 4.2, _fill(AvatarPigments.maw));
    c.drawCircle(const Offset(50, 68), 4.2, _pen(0.6));
  }

  /// Dancing: eyes shut in bliss, head tilted, music alongside.
  void _dancing(Canvas c) {
    _bust(c);

    c.save();
    c.translate(50, 76);
    c.rotate(0.15);
    c.translate(-50, -76);

    _ears(c);
    _head(c);
    _happyEyes(c, y: 46);
    _whiskers(c);
    _nose(c, y: 52);
    _openMouth(c, y: 59, width: 16, height: 11);
    _blush(c, y: 57);

    c.restore();

    // A quaver: stem, flag and head, drawn rather than typeset.
    final Color ink = face.trim ?? AvatarPigments.line;
    final Paint stem = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke * weight * 0.85
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    c.drawLine(const Offset(86, 12), const Offset(86, 30), stem);
    c.drawPath(
      Path()
        ..moveTo(86, 12)
        ..quadraticBezierTo(94, 15, 92, 22),
      stem,
    );
    c.drawCircle(const Offset(82, 31), 4, _fill(ink));
  }

  /// Lazy: half-lidded eyes and a yawn.
  void _lazy(Canvas c) {
    _bust(c);
    _ears(c, droop: 0.3);
    _head(c);
    _lidEyes(c, y: 46);
    _whiskers(c);
    _nose(c, y: 52);
    // A tall, narrow mouth: a yawn rather than a laugh.
    _openMouth(c, y: 57, width: 14, height: 17);
  }

  /// Smug: narrowed eyes and a one-sided smirk.
  void _smug(Canvas c) {
    _bust(c);
    _ears(c);
    _head(c);

    // Narrow slits rather than lids: half closed, and enjoying it.
    _mirror(c, (Canvas m) {
      m.drawLine(const Offset(32, 46), const Offset(45, 44), _pen(1.2));
    });

    _whiskers(c);
    _nose(c);

    // One corner lifts and the other does not. Drawn asymmetrically on
    // purpose — a mirrored smirk is just a smile.
    final Path smirk = Path()
      ..moveTo(41, 63)
      ..quadraticBezierTo(50, 67, 60, 59);
    c.drawPath(smirk, _pen(1));

    if (face.trim != null) {
      // A collar tag, because this one would absolutely wear one.
      c.drawCircle(const Offset(50, 84), 5, _fill(face.trim!));
      c.drawCircle(const Offset(50, 84), 5, _pen(0.6));
    }
  }

  /// Scared: pinned ears, huge eyes, a wobbling frown.
  void _scared(Canvas c) {
    _bust(c);
    _ears(c, droop: 0.5);
    _head(c);
    _brows(c, y: 33, angle: -4);
    _wideEyes(c, y: 47, dx: 12, r: 7.5);
    _whiskers(c, y: 56);
    _nose(c, y: 57, width: 9);

    // A wavy line: a mouth that cannot hold still.
    final Path wobble = Path()..moveTo(41, 68);
    for (int i = 0; i < 3; i++) {
      final double x = 41 + (i + 1) * 6;
      wobble.quadraticBezierTo(x - 3, 68 + (i.isEven ? 4 : -4), x, 68);
    }
    c.drawPath(wobble, _pen(0.85));

    // A sweat drop, which is the whole gag.
    final Path drop = Path()
      ..moveTo(74, 30)
      ..cubicTo(79, 38, 80, 44, 74, 44)
      ..cubicTo(68, 44, 69, 38, 74, 30)
      ..close();
    _ink(c, drop, AvatarPigments.light, 0.55);
  }

  /// Chaotic: mismatched eyes, a manic grin, fur out of control.
  void _chaotic(Canvas c) {
    _bust(c);

    // Tufts sticking out behind the head, drawn first so they read as behind.
    _mirror(c, (Canvas m) {
      for (final double angle in <double>[0.4, 0.9, 1.4]) {
        final Offset from = Offset(
          50 - math.cos(angle) * 30,
          50 - math.sin(angle) * 27,
        );
        final Offset to = Offset(
          50 - math.cos(angle) * 44,
          50 - math.sin(angle) * 40,
        );
        m.drawLine(from, to, _pen(0.9));
      }
    });

    _ears(c);
    _head(c);

    // Mismatched: one enormous, one a pinprick. Drawn individually, because
    // the entire joke is that they do not match.
    c.drawCircle(const Offset(38, 46), 8, _fill(AvatarPigments.light));
    c.drawCircle(const Offset(38, 46), 8, _pen(0.6));
    c.drawCircle(const Offset(38, 47), 3, _fill(AvatarPigments.line));

    c.drawCircle(const Offset(62, 46), 6, _fill(AvatarPigments.light));
    c.drawCircle(const Offset(62, 46), 6, _pen(0.6));
    c.drawCircle(const Offset(63, 45), 5, _fill(AvatarPigments.line));

    _whiskers(c, y: 55);
    _nose(c, y: 55, width: 9);

    // A wide grin with teeth.
    final Path grin = Path()
      ..addOval(Rect.fromCenter(center: const Offset(50, 68), width: 26, height: 13));
    _ink(c, grin, AvatarPigments.maw, 0.7);

    // Clipped to the grin, so the teeth sit inside the mouth rather than
    // floating as a bar across it.
    c.save();
    c.clipPath(grin);
    c.drawRect(const Rect.fromLTWH(36, 62, 28, 4), _fill(AvatarPigments.light));
    c.restore();
  }
}

