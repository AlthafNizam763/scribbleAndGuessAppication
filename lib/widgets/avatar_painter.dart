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
/// Order of construction is always the same — shoulders, whatever sits behind
/// the head, the head, whatever sits in front of it, then the features — so
/// overlaps read as depth rather than as stacked outlines.
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
      AvatarShape.bowlCut => _bowlCut,
      AvatarShape.ponytail => _ponytail,
      AvatarShape.curls => _curls,
      AvatarShape.ballCap => _ballCap,
      AvatarShape.topBun => _topBun,
      AvatarShape.beard => _beard,
      AvatarShape.cat => _cat,
      AvatarShape.dog => _dog,
      AvatarShape.bear => _bear,
      AvatarShape.fox => _fox,
      AvatarShape.panda => _panda,
      AvatarShape.bunny => _bunny,
      AvatarShape.animeLong => _animeLong,
      AvatarShape.animeSpiky => _animeSpiky,
      AvatarShape.animeTwinTails => _animeTwinTails,
      AvatarShape.animeNinja => _animeNinja,
      AvatarShape.animeCatGirl => _animeCatGirl,
      AvatarShape.animeCool => _animeCool,
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

  /// A deeper [color], for ears and markings that must read against the coat
  /// they sit on.
  Color _deepen(Color color, [double amount = 0.24]) =>
      Color.lerp(color, AvatarPigments.line, amount)!;

  // ---------------------------------------------------------------- pieces ---

  /// Head and shoulders, cut off by the disc.
  void _bust(Canvas c, {bool collar = true}) {
    final Path body = Path()
      ..moveTo(4, 104)
      ..cubicTo(9, 86, 28, 76, 50, 76)
      ..cubicTo(72, 76, 91, 86, 96, 104)
      ..close();
    _ink(c, body, face.cloth);
    if (collar) {
      final Path neckline = Path()
        ..moveTo(42, 77)
        ..quadraticBezierTo(50, 85, 58, 77);
      c.drawPath(neckline, _pen(0.75));
    }
  }

  /// The oval a person's face is built on.
  static final Rect _personFace = Rect.fromCenter(
    center: const Offset(50, 46),
    width: 54,
    height: 58,
  );

  /// The rounder oval an animal's head is built on.
  static final Rect _beastFace = Rect.fromCenter(
    center: const Offset(50, 50),
    width: 60,
    height: 56,
  );

  void _personHead(Canvas c) {
    _mirror(c, (Canvas m) {
      final Path ear = Path()
        ..addOval(
          Rect.fromCenter(
            center: const Offset(24, 51),
            width: 10,
            height: 14,
          ),
        );
      _ink(m, ear, face.skin, 0.85);
    });
    _ink(c, Path()..addOval(_personFace), face.skin);
  }

  void _beastHead(Canvas c) => _ink(c, Path()..addOval(_beastFace), face.skin);

  /// The tapered chin an anime face is built on.
  void _animeHead(Canvas c) {
    _mirror(c, (Canvas m) {
      final Path ear = Path()
        ..addOval(
          Rect.fromCenter(center: const Offset(25, 48), width: 9, height: 13),
        );
      _ink(m, ear, face.skin, 0.8);
    });
    final Path head = Path()
      ..moveTo(24, 42)
      ..cubicTo(24, 22, 35, 13, 50, 13)
      ..cubicTo(65, 13, 76, 22, 76, 42)
      ..cubicTo(76, 61, 64, 77, 50, 77)
      ..cubicTo(36, 77, 24, 61, 24, 42)
      ..close();
    _ink(c, head, face.skin);
  }

  /// Two round eyes with a catchlight.
  void _dotEyes(Canvas c, {double y = 49, double dx = 11, double r = 4.6}) {
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

  /// Two tall anime eyes, iris coloured to match the hair.
  void _animeEyes(
    Canvas c, {
    double y = 52,
    double dx = 12.5,
    double width = 14,
    double height = 16,
  }) {
    final Color iris = face.hair;
    _mirror(c, (Canvas m) {
      final Offset eye = Offset(50 - dx, y);
      final Rect white = Rect.fromCenter(
        center: eye,
        width: width,
        height: height,
      );
      m.drawOval(white, _fill(AvatarPigments.light));
      m.drawOval(
        Rect.fromCenter(
          center: eye.translate(0, 1),
          width: width * 0.8,
          height: height * 0.82,
        ),
        _fill(iris),
      );
      m.drawOval(
        Rect.fromCenter(
          center: eye.translate(0, 2),
          width: width * 0.44,
          height: height * 0.46,
        ),
        _fill(AvatarPigments.line),
      );
      m.drawOval(
        Rect.fromCenter(
          center: eye.translate(-width * 0.19, -height * 0.21),
          width: width * 0.32,
          height: height * 0.3,
        ),
        _fill(AvatarPigments.light),
      );
      m.drawOval(
        Rect.fromCenter(
          center: eye.translate(width * 0.17, height * 0.22),
          width: width * 0.17,
          height: height * 0.15,
        ),
        _fill(AvatarPigments.light.withValues(alpha: 0.8)),
      );
      m.drawOval(white, _pen(0.8));
      final Path lash = Path()
        ..moveTo(eye.dx - width * 0.55, eye.dy - height * 0.34)
        ..quadraticBezierTo(
          eye.dx,
          eye.dy - height * 0.8,
          eye.dx + width * 0.55,
          eye.dy - height * 0.3,
        );
      m.drawPath(lash, _pen(1.2));
    });
  }

  /// Two happy closed arcs.
  void _happyEyes(Canvas c, {double y = 52, double dx = 12, double width = 12}) {
    _mirror(c, (Canvas m) {
      final double cx = 50 - dx;
      final Path arc = Path()
        ..moveTo(cx - width / 2, y + 3)
        ..quadraticBezierTo(cx, y - 6, cx + width / 2, y + 3);
      m.drawPath(arc, _pen(1.25));
    });
  }

  /// Straight brows, for a face that needs a little resolve.
  void _brows(Canvas c, {double y = 40, double dx = 12, double width = 12}) {
    _mirror(c, (Canvas m) {
      final double cx = 50 - dx;
      m.drawLine(
        Offset(cx - width / 2, y + 2),
        Offset(cx + width / 2, y - 1),
        _pen(0.8),
      );
    });
  }

  void _smile(
    Canvas c, {
    double y = 62,
    double width = 13,
    double depth = 6,
    double scale = 0.9,
  }) {
    final Path mouth = Path()
      ..moveTo(50 - width / 2, y)
      ..quadraticBezierTo(50, y + depth, 50 + width / 2, y);
    c.drawPath(mouth, _pen(scale));
  }

  /// An open grin with a tongue behind it.
  void _openSmile(Canvas c, {double y = 62, double width = 17, double depth = 10}) {
    final Path mouth = Path()
      ..moveTo(50 - width / 2, y)
      ..quadraticBezierTo(50, y + depth, 50 + width / 2, y)
      ..close();
    c.drawPath(mouth, _fill(AvatarPigments.line));
    final Path tongue = Path()
      ..moveTo(50 - width * 0.26, y + depth * 0.42)
      ..quadraticBezierTo(
        50,
        y + depth * 1.02,
        50 + width * 0.26,
        y + depth * 0.42,
      )
      ..close();
    c.drawPath(tongue, _fill(AvatarPigments.petal));
    c.drawPath(mouth, _pen(0.8));
  }

  /// A muzzle: nose triangle over a two-arc mouth.
  void _muzzle(Canvas c, {double y = 55, Color? nose, double width = 12}) {
    final Path snout = Path()
      ..moveTo(50 - width / 2, y)
      ..lineTo(50 + width / 2, y)
      ..lineTo(50, y + width * 0.46)
      ..close();
    _ink(c, snout, nose ?? AvatarPigments.petal, 0.65);
    final double lip = y + width * 0.46;
    final Path mouth = Path()
      ..moveTo(50, lip)
      ..lineTo(50, lip + 3)
      ..moveTo(50, lip + 3)
      ..quadraticBezierTo(45, lip + 7, 40.5, lip + 1.5)
      ..moveTo(50, lip + 3)
      ..quadraticBezierTo(55, lip + 7, 59.5, lip + 1.5);
    c.drawPath(mouth, _pen(0.75));
  }

  void _blush(Canvas c, {double y = 58, double dx = 20, double width = 11}) {
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

  /// The one gloss stroke that stops a block of hair reading flat.
  void _shine(Canvas c, Offset from, Offset to, {double bend = 5}) {
    final Path gloss = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        (from.dx + to.dx) / 2,
        (from.dy + to.dy) / 2 - bend,
        to.dx,
        to.dy,
      );
    c.drawPath(
      gloss,
      Paint()
        ..color = AvatarPigments.light.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke * weight * 1.3
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  // ---------------------------------------------------------------- people ---

  void _bowlCut(Canvas c) {
    _bust(c);
    _personHead(c);
    final Path hair = Path()
      ..moveTo(21, 47)
      ..cubicTo(19, 23, 33, 14, 50, 14)
      ..cubicTo(67, 14, 81, 23, 79, 47)
      ..cubicTo(76, 38, 70, 34, 62, 34)
      ..cubicTo(56, 34, 53, 38, 45, 38)
      ..cubicTo(35, 38, 27, 40, 21, 47)
      ..close();
    _ink(c, hair, face.hair);
    _shine(c, const Offset(32, 27), const Offset(46, 20), bend: 4);
    _dotEyes(c, y: 50);
    _blush(c, y: 58);
    _smile(c, y: 62);
  }

  void _ponytail(Canvas c) {
    _bust(c);
    final Path tail = Path()
      ..moveTo(70, 28)
      ..cubicTo(88, 24, 96, 40, 91, 56)
      ..cubicTo(87, 69, 75, 68, 71, 57)
      ..close();
    _ink(c, tail, face.hair);
    _personHead(c);
    final Path hair = Path()
      ..moveTo(21, 46)
      ..cubicTo(19, 22, 34, 13, 51, 13)
      ..cubicTo(68, 13, 82, 23, 79, 46)
      ..cubicTo(77, 33, 67, 28, 55, 31)
      ..cubicTo(45, 34, 33, 32, 26, 41)
      ..cubicTo(24, 43, 22, 45, 21, 46)
      ..close();
    _ink(c, hair, face.hair);
    final Path band = Path()
      ..addOval(Rect.fromCircle(center: const Offset(73, 33), radius: 5));
    _ink(c, band, face.trim ?? _deepen(face.hair), 0.75);
    _shine(c, const Offset(34, 24), const Offset(48, 19), bend: 4);
    _dotEyes(c, y: 50);
    _blush(c, y: 58);
    _smile(c, y: 62);
  }

  void _curls(Canvas c) {
    _bust(c);
    Path halo = Path();
    for (final Offset knot in const <Offset>[
      Offset(25, 36),
      Offset(28, 22),
      Offset(41, 13),
      Offset(57, 13),
      Offset(70, 20),
      Offset(76, 34),
    ]) {
      halo = Path.combine(
        PathOperation.union,
        halo,
        Path()..addOval(Rect.fromCircle(center: knot, radius: 13)),
      );
    }
    _ink(c, halo, face.hair);
    _personHead(c);
    Path fringe = Path();
    for (final Offset knot in const <Offset>[
      Offset(28, 31),
      Offset(40, 24),
      Offset(53, 23),
      Offset(65, 26),
      Offset(74, 34),
    ]) {
      fringe = Path.combine(
        PathOperation.union,
        fringe,
        Path()..addOval(Rect.fromCircle(center: knot, radius: 12)),
      );
    }
    _ink(c, fringe, face.hair);
    _dotEyes(c, y: 51);
    _blush(c, y: 59);
    _smile(c, y: 63);
  }

  void _ballCap(Canvas c) {
    _bust(c);
    _personHead(c);
    final Path hair = Path()
      ..moveTo(21, 50)
      ..cubicTo(21, 38, 26, 33, 34, 33)
      ..lineTo(66, 33)
      ..cubicTo(74, 33, 79, 38, 79, 50)
      ..cubicTo(76, 43, 70, 41, 62, 42)
      ..lineTo(38, 42)
      ..cubicTo(30, 41, 24, 43, 21, 50)
      ..close();
    _ink(c, hair, face.hair);
    final Color cap = face.trim ?? AvatarPigments.clothDenim;
    final Path dome = Path()
      ..moveTo(20, 39)
      ..cubicTo(20, 17, 34, 9, 50, 9)
      ..cubicTo(66, 9, 80, 17, 80, 39)
      ..close();
    _ink(c, dome, cap);
    final Path brim = Path()
      ..moveTo(48, 36)
      ..cubicTo(26, 35, 9, 39, 8, 45)
      ..cubicTo(10, 49, 28, 45, 48, 43)
      ..close();
    _ink(c, brim, cap, 0.9);
    final Path button = Path()
      ..addOval(Rect.fromCircle(center: const Offset(50, 10), radius: 3.4));
    _ink(c, button, cap, 0.7);
    _dotEyes(c, y: 52);
    _blush(c, y: 60);
    _smile(c, y: 64);
  }

  void _topBun(Canvas c) {
    _bust(c);
    final Path bun = Path()
      ..addOval(Rect.fromCircle(center: const Offset(50, 12), radius: 10));
    _ink(c, bun, face.hair);
    _personHead(c);
    final Path hair = Path()
      ..moveTo(21, 45)
      ..cubicTo(20, 22, 34, 13, 50, 13)
      ..cubicTo(66, 13, 80, 22, 79, 45)
      ..cubicTo(75, 32, 64, 27, 50, 27)
      ..cubicTo(36, 27, 25, 32, 21, 45)
      ..close();
    _ink(c, hair, face.hair);
    _shine(c, const Offset(32, 30), const Offset(43, 21), bend: 3);
    _dotEyes(c, y: 50, dx: 12, r: 3.8);
    _blush(c, y: 60, dx: 21);
    _smile(c, y: 64);
    // Glasses last: they sit on top of the face, lenses included.
    _mirror(c, (Canvas m) {
      final Rect lens = Rect.fromCenter(
        center: const Offset(38, 50),
        width: 18,
        height: 17,
      );
      m.drawOval(lens, _fill(AvatarPigments.light.withValues(alpha: 0.28)));
      m.drawOval(lens, _pen(0.85));
      m.drawLine(const Offset(29, 48), const Offset(21, 49), _pen(0.8));
    });
    c.drawLine(const Offset(47, 49), const Offset(53, 49), _pen(0.8));
  }

  void _beard(Canvas c) {
    _bust(c);
    _personHead(c);
    final Path whiskers = Path()
      ..moveTo(23, 42)
      ..cubicTo(21, 66, 33, 84, 50, 84)
      ..cubicTo(67, 84, 79, 66, 77, 42)
      ..cubicTo(74, 56, 65, 62, 50, 62)
      ..cubicTo(35, 62, 26, 56, 23, 42)
      ..close();
    _ink(c, whiskers, face.hair);
    final Path hair = Path()
      ..moveTo(22, 44)
      ..cubicTo(21, 22, 35, 14, 50, 14)
      ..cubicTo(65, 14, 79, 22, 78, 44)
      ..cubicTo(74, 32, 63, 28, 50, 28)
      ..cubicTo(37, 28, 26, 32, 22, 44)
      ..close();
    _ink(c, hair, face.hair);
    _dotEyes(c, y: 47);
    final Path moustache = Path()
      ..moveTo(36, 57)
      ..cubicTo(42, 51, 47, 54, 50, 56)
      ..cubicTo(53, 54, 58, 51, 64, 57)
      ..cubicTo(57, 63, 43, 63, 36, 57)
      ..close();
    _ink(c, moustache, face.hair, 0.8);
  }

  // --------------------------------------------------------------- animals ---

  void _cat(Canvas c) {
    _bust(c, collar: false);
    _mirror(c, (Canvas m) {
      final Path ear = Path()
        ..moveTo(24, 40)
        ..lineTo(27, 8)
        ..lineTo(48, 27)
        ..close();
      _ink(m, ear, face.skin);
      final Path inner = Path()
        ..moveTo(30, 33)
        ..lineTo(32, 17)
        ..lineTo(42, 27)
        ..close();
      _ink(m, inner, face.hair, 0.6);
    });
    _beastHead(c);
    _dotEyes(c, y: 47, dx: 12);
    _mirror(c, (Canvas m) {
      for (final double y in <double>[53, 58, 63]) {
        m.drawLine(Offset(29, y), Offset(9, y - 5), _pen(0.7));
      }
    });
    _muzzle(c, y: 54);
    _blush(c, y: 56, dx: 22);
  }

  void _dog(Canvas c) {
    _bust(c, collar: false);
    _mirror(c, (Canvas m) {
      final Path ear = Path()
        ..moveTo(29, 27)
        ..cubicTo(13, 25, 7, 44, 11, 58)
        ..cubicTo(15, 70, 31, 68, 33, 53)
        ..close();
      _ink(m, ear, _deepen(face.skin));
    });
    _beastHead(c);
    final Path patch = Path()
      ..addOval(
        Rect.fromCenter(center: const Offset(50, 60), width: 34, height: 25),
      );
    _ink(c, patch, face.hair, 0.85);
    _dotEyes(c, y: 44, dx: 11);
    final Path tongue = Path()
      ..moveTo(45, 62)
      ..cubicTo(44, 73, 56, 73, 55, 62)
      ..close();
    _ink(c, tongue, AvatarPigments.petal, 0.7);
    final Path nose = Path()
      ..addOval(
        Rect.fromCenter(center: const Offset(50, 53), width: 14, height: 10),
      );
    _ink(c, nose, AvatarPigments.line, 0.6);
    final Path mouth = Path()
      ..moveTo(50, 58)
      ..lineTo(50, 61)
      ..moveTo(50, 61)
      ..quadraticBezierTo(44, 66, 40, 60)
      ..moveTo(50, 61)
      ..quadraticBezierTo(56, 66, 60, 60);
    c.drawPath(mouth, _pen(0.75));
  }

  void _bear(Canvas c) {
    _bust(c, collar: false);
    _mirror(c, (Canvas m) {
      final Path ear = Path()
        ..addOval(Rect.fromCircle(center: const Offset(26, 21), radius: 12));
      _ink(m, ear, face.skin);
      final Path inner = Path()
        ..addOval(Rect.fromCircle(center: const Offset(26, 22), radius: 6));
      _ink(m, inner, AvatarPigments.petal, 0.6);
    });
    _beastHead(c);
    final Path snout = Path()
      ..addOval(
        Rect.fromCenter(center: const Offset(50, 60), width: 31, height: 23),
      );
    _ink(c, snout, face.hair, 0.85);
    _dotEyes(c, y: 45, dx: 11);
    _muzzle(c, y: 52, nose: AvatarPigments.line, width: 13);
  }

  void _fox(Canvas c) {
    _bust(c, collar: false);
    _mirror(c, (Canvas m) {
      final Path ear = Path()
        ..moveTo(22, 41)
        ..lineTo(23, 6)
        ..lineTo(47, 26)
        ..close();
      _ink(m, ear, face.skin);
      final Path inner = Path()
        ..moveTo(28, 33)
        ..lineTo(29, 15)
        ..lineTo(41, 26)
        ..close();
      _ink(m, inner, AvatarPigments.furSoot, 0.6);
    });
    _beastHead(c);
    final Path mask = Path()
      ..moveTo(22, 47)
      ..cubicTo(30, 43, 41, 48, 50, 48)
      ..cubicTo(59, 48, 70, 43, 78, 47)
      ..cubicTo(76, 65, 64, 78, 50, 78)
      ..cubicTo(36, 78, 24, 65, 22, 47)
      ..close();
    _ink(c, mask, face.hair, 0.85);
    _dotEyes(c, y: 44, dx: 12);
    final Path nose = Path()
      ..moveTo(43, 58)
      ..lineTo(57, 58)
      ..lineTo(50, 66)
      ..close();
    _ink(c, nose, AvatarPigments.furSoot, 0.65);
    _smile(c, y: 69, width: 11, depth: 4);
  }

  void _panda(Canvas c) {
    _bust(c, collar: false);
    _mirror(c, (Canvas m) {
      final Path ear = Path()
        ..addOval(Rect.fromCircle(center: const Offset(25, 20), radius: 11.5));
      _ink(m, ear, face.hair);
    });
    _beastHead(c);
    _mirror(c, (Canvas m) {
      m.save();
      m.translate(36, 47);
      m.rotate(-0.3);
      final Path patch = Path()
        ..addOval(
          Rect.fromCenter(center: Offset.zero, width: 20, height: 24),
        );
      _ink(m, patch, face.hair, 0.6);
      m.restore();
      m.drawCircle(const Offset(36, 47), 5.4, _fill(AvatarPigments.light));
      m.drawCircle(const Offset(37, 47.5), 2.9, _fill(AvatarPigments.line));
    });
    _muzzle(c, y: 58, nose: AvatarPigments.furSoot, width: 11);
  }

  void _bunny(Canvas c) {
    _bust(c, collar: false);
    _mirror(c, (Canvas m) {
      m.save();
      m.translate(37, 26);
      m.rotate(-0.15);
      final Path ear = Path()
        ..addRRect(
          RRect.fromRectXY(
            Rect.fromCenter(center: Offset.zero, width: 15, height: 44),
            7.5,
            13,
          ),
        );
      _ink(m, ear, face.skin, 0.85);
      final Path inner = Path()
        ..addRRect(
          RRect.fromRectXY(
            Rect.fromCenter(center: const Offset(0, 2), width: 7, height: 32),
            3.5,
            9,
          ),
        );
      _ink(m, inner, face.hair, 0.55);
      m.restore();
    });
    _beastHead(c);
    _dotEyes(c, y: 48, dx: 12);
    final Path nose = Path()
      ..moveTo(45.5, 56)
      ..lineTo(54.5, 56)
      ..lineTo(50, 60.5)
      ..close();
    _ink(c, nose, face.hair, 0.6);
    final Path lip = Path()
      ..moveTo(50, 60.5)
      ..lineTo(50, 63)
      ..moveTo(50, 63)
      ..quadraticBezierTo(45, 67, 41, 61.5)
      ..moveTo(50, 63)
      ..quadraticBezierTo(55, 67, 59, 61.5);
    c.drawPath(lip, _pen(0.75));
    final Path teeth = Path()
      ..addRRect(
        RRect.fromRectXY(
          Rect.fromCenter(center: const Offset(50, 68), width: 12, height: 10),
          2.5,
          2.5,
        ),
      );
    _ink(c, teeth, AvatarPigments.light, 0.6);
    c.drawLine(const Offset(50, 63.5), const Offset(50, 72.5), _pen(0.6));
    _blush(c, y: 55, dx: 22);
  }

  // ----------------------------------------------------------------- anime ---

  void _animeLong(Canvas c) {
    _bust(c);
    final Path back = Path()
      ..moveTo(50, 8)
      ..cubicTo(26, 8, 14, 26, 15, 50)
      ..cubicTo(16, 70, 12, 86, 9, 104)
      ..lineTo(91, 104)
      ..cubicTo(88, 86, 84, 70, 85, 50)
      ..cubicTo(86, 26, 74, 8, 50, 8)
      ..close();
    _ink(c, back, face.hair);
    _animeHead(c);
    final Path fringe = Path()
      ..moveTo(23, 44)
      ..cubicTo(22, 21, 34, 10, 50, 10)
      ..cubicTo(66, 10, 78, 21, 77, 44)
      ..lineTo(72, 30)
      ..lineTo(64, 43)
      ..lineTo(57, 27)
      ..lineTo(47, 43)
      ..lineTo(41, 28)
      ..lineTo(31, 44)
      ..close();
    _ink(c, fringe, face.hair);
    _shine(c, const Offset(32, 26), const Offset(50, 19), bend: 4);
    _animeEyes(c, y: 53);
    _blush(c, y: 63, dx: 21);
    _smile(c, y: 67, width: 9, depth: 4);
  }

  void _animeSpiky(Canvas c) {
    _bust(c);
    _animeHead(c);
    final Path spikes = Path()
      ..moveTo(22, 46)
      ..lineTo(18, 26)
      ..lineTo(31, 32)
      ..lineTo(30, 10)
      ..lineTo(44, 26)
      ..lineTo(51, 6)
      ..lineTo(61, 25)
      ..lineTo(71, 12)
      ..lineTo(73, 31)
      ..lineTo(84, 25)
      ..lineTo(78, 46)
      ..cubicTo(74, 36, 62, 38, 50, 37)
      ..cubicTo(38, 38, 26, 36, 22, 46)
      ..close();
    _ink(c, spikes, face.hair);
    _brows(c, y: 46, dx: 12.5);
    _animeEyes(c, y: 54, height: 14);
    _smile(c, y: 67, width: 12, depth: 5);
  }

  void _animeTwinTails(Canvas c) {
    _bust(c);
    _mirror(c, (Canvas m) {
      final Path tail = Path()
        ..moveTo(29, 25)
        ..cubicTo(10, 24, 4, 46, 9, 64)
        ..cubicTo(13, 78, 26, 76, 26, 61)
        ..cubicTo(26, 47, 27, 34, 33, 29)
        ..close();
      _ink(m, tail, face.hair);
    });
    _animeHead(c);
    final Path hair = Path()
      ..moveTo(23, 45)
      ..cubicTo(22, 20, 34, 10, 50, 10)
      ..cubicTo(66, 10, 78, 20, 77, 45)
      ..cubicTo(72, 30, 62, 26, 50, 26)
      ..cubicTo(44, 26, 40, 31, 38, 39)
      ..cubicTo(34, 34, 27, 36, 23, 45)
      ..close();
    _ink(c, hair, face.hair);
    _mirror(c, (Canvas m) {
      final Path ribbon = Path()
        ..addOval(Rect.fromCircle(center: const Offset(28, 26), radius: 6.5));
      _ink(m, ribbon, face.trim ?? AvatarPigments.clothBerry, 0.7);
    });
    _shine(c, const Offset(38, 21), const Offset(56, 18), bend: 3);
    _animeEyes(c, y: 53);
    _blush(c, y: 63, dx: 21);
    _smile(c, y: 67, width: 9, depth: 4);
  }

  void _animeNinja(Canvas c) {
    _bust(c);
    _animeHead(c);
    final Path hair = Path()
      ..moveTo(22, 46)
      ..cubicTo(21, 20, 34, 10, 50, 10)
      ..cubicTo(66, 10, 79, 20, 78, 46)
      ..cubicTo(74, 36, 62, 32, 50, 32)
      ..cubicTo(38, 32, 26, 36, 22, 46)
      ..close();
    _ink(c, hair, face.hair);
    final Color band = face.trim ?? AvatarPigments.clothCoral;
    final Path ribbon = Path()
      ..moveTo(74, 30)
      ..cubicTo(84, 25, 88, 30, 92, 26)
      ..cubicTo(89, 38, 82, 40, 75, 39)
      ..close();
    _ink(c, ribbon, band, 0.8);
    final Path headband = Path()
      ..moveTo(21, 40)
      ..cubicTo(30, 32, 70, 32, 79, 40)
      ..lineTo(79, 30)
      ..cubicTo(70, 22, 30, 22, 21, 30)
      ..close();
    _ink(c, headband, band);
    _animeEyes(c, y: 55, height: 13);
    _smile(c, y: 68, width: 11, depth: 4);
  }

  void _animeCatGirl(Canvas c) {
    _bust(c);
    _mirror(c, (Canvas m) {
      final Path ear = Path()
        ..moveTo(28, 30)
        ..lineTo(30, 6)
        ..lineTo(49, 25)
        ..close();
      _ink(m, ear, face.hair);
      final Path inner = Path()
        ..moveTo(33, 26)
        ..lineTo(34, 14)
        ..lineTo(44, 24)
        ..close();
      _ink(m, inner, face.trim ?? AvatarPigments.petal, 0.55);
    });
    _animeHead(c);
    final Path bob = Path()
      ..moveTo(21, 60)
      ..cubicTo(19, 30, 32, 13, 50, 13)
      ..cubicTo(68, 13, 81, 30, 79, 60)
      ..cubicTo(76, 52, 74, 46, 73, 40)
      ..cubicTo(70, 45, 62, 45, 57, 40)
      ..cubicTo(53, 46, 44, 46, 40, 40)
      ..cubicTo(35, 45, 29, 45, 27, 40)
      ..cubicTo(26, 48, 24, 54, 21, 60)
      ..close();
    _ink(c, bob, face.hair);
    _shine(c, const Offset(34, 24), const Offset(52, 19), bend: 4);
    _animeEyes(c, y: 54);
    _blush(c, y: 64, dx: 21);
    _smile(c, y: 68, width: 9, depth: 4);
  }

  void _animeCool(Canvas c) {
    _bust(c);
    _animeHead(c);
    final Path sweep = Path()
      ..moveTo(21, 44)
      ..cubicTo(20, 20, 34, 10, 50, 10)
      ..cubicTo(68, 10, 80, 22, 78, 44)
      ..cubicTo(76, 34, 70, 28, 62, 26)
      ..cubicTo(52, 36, 38, 42, 24, 38)
      ..cubicTo(22, 40, 21, 42, 21, 44)
      ..close();
    _ink(c, sweep, face.hair);
    _shine(c, const Offset(34, 22), const Offset(52, 17), bend: 4);
    _happyEyes(c, y: 54);
    _openSmile(c, y: 63);
    _blush(c, y: 61, dx: 23);
  }
}
