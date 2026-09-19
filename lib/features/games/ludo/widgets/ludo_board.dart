import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/models/games/ludo_state.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The four seat colours, in turn order.
///
/// Red, green, yellow, blue — the four every Ludo set has been printed in for
/// a century. Recognisable matters more than novel here: somebody who has
/// played the board game should know which counters are theirs before they
/// have read anything.
const List<Color> ludoSeatColours = <Color>[
  Color(0xFFE0483C), // red, top-left
  Color(0xFF3FA34D), // green, top-right
  Color(0xFFE8B62C), // yellow, bottom-right
  Color(0xFF3B7DD8), // blue, bottom-left
];

/// The board itself: yards, track, lanes, stars and the middle.
///
/// Painted rather than assembled from widgets because it is two hundred and
/// twenty-odd cells that never change between frames — a widget each would be
/// a rebuild of the whole board every time a counter moved. The counters
/// themselves *are* widgets, laid over the top, so they can animate and be
/// tapped.
class LudoBoardPainter extends CustomPainter {
  const LudoBoardPainter({required this.skin, required this.highlightCells});

  final GameSkin skin;

  /// Board cells to mark as reachable this turn. Empty when it is not this
  /// player's go.
  final Set<int> highlightCells;

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.width / LudoGeometry.gridSize;

    Rect at(Offset grid) => Rect.fromLTWH(
          grid.dx * cell,
          grid.dy * cell,
          cell,
          cell,
        );

    // The board is one square of light wood with a dark rim, which is what a
    // folding Ludo board actually looks like.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.5)),
      Paint()..color = skin.surface,
    );

    _paintYards(canvas, cell, at);
    _paintTrack(canvas, cell, at);
    _paintLanes(canvas, cell, at);
    _paintCentre(canvas, cell);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.5))
          .deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = skin.edge,
    );
  }

  /// The four corners, each a slab of its seat's colour with four wells in it.
  void _paintYards(Canvas canvas, double cell, Rect Function(Offset) at) {
    for (int seat = 0; seat < 4; seat++) {
      final Offset corner = switch (seat) {
        0 => const Offset(0, 0),
        1 => const Offset(9, 0),
        2 => const Offset(9, 9),
        _ => const Offset(0, 9),
      };
      final Color tint = ludoSeatColours[seat];

      final Rect yard = Rect.fromLTWH(
        corner.dx * cell,
        corner.dy * cell,
        cell * 6,
        cell * 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(yard, Radius.circular(cell * 0.4)),
        Paint()..color = tint.withValues(alpha: 0.85),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(yard.deflate(cell * 0.75), Radius.circular(cell * 0.3)),
        Paint()..color = skin.surface,
      );

      // The wells the counters sit in while they wait.
      for (final Offset slot in LudoGeometry.yardSlots(seat)) {
        canvas.drawCircle(
          Offset((slot.dx + 0.5) * cell, (slot.dy + 0.5) * cell),
          cell * 0.42,
          Paint()..color = tint.withValues(alpha: 0.3),
        );
        canvas.drawCircle(
          Offset((slot.dx + 0.5) * cell, (slot.dy + 0.5) * cell),
          cell * 0.42,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = tint,
        );
      }
    }
  }

  /// The fifty-two squares of the shared track.
  void _paintTrack(Canvas canvas, double cell, Rect Function(Offset) at) {
    for (int index = 0; index < LudoGeometry.ring.length; index++) {
      final Rect square = at(LudoGeometry.ring[index]);
      final bool isStart = index % 13 == 0;
      final bool isSafe = LudoGeometry.isSafeCell(index);
      final bool lit = highlightCells.contains(index);

      // A start square wears its owner's colour; the rest are plain.
      final Color fill = isStart
          ? ludoSeatColours[index ~/ 13].withValues(alpha: 0.55)
          : skin.surfaceRaised;

      canvas.drawRRect(
        RRect.fromRectAndRadius(square.deflate(0.6), Radius.circular(cell * 0.14)),
        Paint()..color = lit ? skin.accent.withValues(alpha: 0.45) : fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(square.deflate(0.6), Radius.circular(cell * 0.14)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lit ? 1.8 : 0.8
          ..color = lit ? skin.accent : skin.edge.withValues(alpha: 0.6),
      );

      // A star on every square a counter cannot be taken on. Eight of them,
      // and they are the same eight for every seat — see `LudoGeometry`.
      if (isSafe && !isStart) _paintStar(canvas, square.center, cell * 0.26, skin.inkMuted);
      if (isStart) _paintStar(canvas, square.center, cell * 0.26, skin.ink.withValues(alpha: 0.7));
    }
  }

  /// The four runs to the middle.
  void _paintLanes(Canvas canvas, double cell, Rect Function(Offset) at) {
    for (int seat = 0; seat < 4; seat++) {
      final Color tint = ludoSeatColours[seat];
      for (final Offset lane in LudoGeometry.homeLane(seat)) {
        final Rect square = at(lane);
        canvas.drawRRect(
          RRect.fromRectAndRadius(square.deflate(0.6), Radius.circular(cell * 0.14)),
          Paint()..color = tint.withValues(alpha: 0.6),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(square.deflate(0.6), Radius.circular(cell * 0.14)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = tint,
        );
      }
    }
  }

  /// The middle: four triangles meeting at a point, one per seat.
  void _paintCentre(Canvas canvas, double cell) {
    final Rect middle = Rect.fromLTWH(cell * 6, cell * 6, cell * 3, cell * 3);
    final Offset heart = middle.center;

    // Each triangle points inward from the side its seat comes in on, so a
    // player's own colour is the one nearest their own lane.
    final List<List<Offset>> wedges = <List<Offset>>[
      <Offset>[middle.topLeft, middle.bottomLeft, heart], // seat 0, from the left
      <Offset>[middle.topLeft, middle.topRight, heart], // seat 1, from the top
      <Offset>[middle.topRight, middle.bottomRight, heart], // seat 2, from the right
      <Offset>[middle.bottomLeft, middle.bottomRight, heart], // seat 3, from below
    ];

    for (int seat = 0; seat < 4; seat++) {
      final Path wedge = Path()
        ..moveTo(wedges[seat][0].dx, wedges[seat][0].dy)
        ..lineTo(wedges[seat][1].dx, wedges[seat][1].dy)
        ..lineTo(wedges[seat][2].dx, wedges[seat][2].dy)
        ..close();
      canvas.drawPath(wedge, Paint()..color = ludoSeatColours[seat].withValues(alpha: 0.8));
    }

    canvas.drawRect(
      middle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = skin.edge,
    );
  }

  void _paintStar(Canvas canvas, Offset centre, double radius, Color ink) {
    final Path star = Path();
    for (int point = 0; point < 10; point++) {
      // Alternating outer and inner radius is what makes it a star rather
      // than a decagon.
      final double r = point.isEven ? radius : radius * 0.45;
      final double angle = -math.pi / 2 + point * math.pi / 5;
      final Offset at = centre + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (point == 0) {
        star.moveTo(at.dx, at.dy);
      } else {
        star.lineTo(at.dx, at.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(LudoBoardPainter oldDelegate) =>
      oldDelegate.skin != skin ||
      !setEquals(oldDelegate.highlightCells, highlightCells);
}

/// Whether two sets hold the same members. `package:collection` is not a
/// dependency of this file's layer, and this is four lines.
bool setEquals(Set<int> a, Set<int> b) {
  if (a.length != b.length) return false;
  for (final int value in a) {
    if (!b.contains(value)) return false;
  }
  return true;
}

/// One counter, drawn over the board.
///
/// A widget rather than part of the painter so it can be tapped and so
/// [AnimatedPositioned] can walk it from one square to the next — which is
/// where the movement animation comes from, without a single frame of it
/// being written by hand.
class LudoCounter extends StatelessWidget {
  const LudoCounter({
    required this.seat,
    required this.size,
    required this.movable,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int seat;
  final double size;

  /// The current roll could move this one. Lit, and tappable.
  final bool movable;

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final Color tint = ludoSeatColours[seat % 4];

    return GestureDetector(
      onTap: movable ? onTap : null,
      // Opaque, so the whole counter takes the tap rather than only its
      // painted pixels — on a phone a counter is about thirty points across
      // and the difference matters.
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: selected ? 1.18 : 1,
        duration: AppMotion.fast,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _CounterPainter(tint: tint, movable: movable, skin: skin),
          ),
        ),
      ),
    );
  }
}

class _CounterPainter extends CustomPainter {
  const _CounterPainter({
    required this.tint,
    required this.movable,
    required this.skin,
  });

  final Color tint;
  final bool movable;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double radius = size.width * 0.42;

    // A shadow under it, so a counter reads as sitting *on* the board rather
    // than being printed into it.
    canvas.drawCircle(
      centre + Offset(0, radius * 0.18),
      radius,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // The body, with a lighter dome on top: two circles is enough to read as
    // a moulded plastic counter at this size.
    canvas.drawCircle(centre, radius, Paint()..color = tint);
    canvas.drawCircle(
      centre - Offset(0, radius * 0.18),
      radius * 0.62,
      Paint()..color = Color.lerp(tint, Colors.white, 0.35)!,
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x66000000),
    );

    if (!movable) return;

    // A ring round anything the roll can actually move. The single most
    // useful thing on the board: it turns "which of these four can I move"
    // from arithmetic into looking.
    canvas.drawCircle(
      centre,
      radius * 1.35,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = skin.accent,
    );
  }

  @override
  bool shouldRepaint(_CounterPainter oldDelegate) =>
      oldDelegate.tint != tint || oldDelegate.movable != movable;
}

/// The die, which rolls and then settles on whatever the server said.
///
/// ## The animation is a lie, and deliberately so
///
/// The faces that flicker past while it rolls are random and mean nothing.
/// The value it stops on is the one the server sent, and it was decided before
/// this animation started. A client that "rolled" and then reported the result
/// would be a client that could roll sixes all afternoon.
///
/// The tumble exists because a number that simply appears does not feel like a
/// dice roll, and this is a game about dice.
class LudoDie extends StatefulWidget {
  const LudoDie({
    required this.value,
    required this.size,
    required this.enabled,
    required this.onRoll,
    super.key,
  });

  /// The settled value, or null when there is nothing on the table.
  final int? value;

  final double size;

  /// Whether this player may roll right now.
  final bool enabled;

  final VoidCallback onRoll;

  @override
  State<LudoDie> createState() => _LudoDieState();
}

class _LudoDieState extends State<LudoDie> with SingleTickerProviderStateMixin {
  late final AnimationController _tumble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  final math.Random _random = math.Random();
  int _face = 1;

  @override
  void initState() {
    super.initState();
    _tumble.addListener(_flicker);
    if (widget.value != null) _face = widget.value!;
  }

  @override
  void didUpdateWidget(LudoDie old) {
    super.didUpdateWidget(old);

    // A *new* value is a new roll. Null-to-value is the interesting case: a
    // value that has not changed is the same roll still sitting there, and
    // re-tumbling it on every rebuild would make the die twitch whenever
    // anything else on the screen moved.
    if (widget.value != null && widget.value != old.value) {
      _tumble.forward(from: 0);
    } else if (widget.value != null && !_tumble.isAnimating) {
      _face = widget.value!;
    }
  }

  void _flicker() {
    if (!mounted) return;
    if (_tumble.isCompleted) {
      setState(() => _face = widget.value ?? _face);
      return;
    }
    // Faster at the start, slowing as it settles.
    final int every = _tumble.value < 0.6 ? 1 : 3;
    if (_tumble.lastElapsedDuration!.inMilliseconds ~/ 40 % every == 0) {
      setState(() => _face = _random.nextInt(6) + 1);
    }
  }

  @override
  void dispose() {
    _tumble
      ..removeListener(_flicker)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final bool rolling = _tumble.isAnimating;

    return Semantics(
      button: widget.enabled,
      label: widget.enabled
          ? 'Roll the die'
          : widget.value == null
              ? 'Waiting for the roll'
              : 'Rolled ${widget.value}',
      child: GestureDetector(
        onTap: widget.enabled && !rolling ? widget.onRoll : null,
        child: AnimatedContainer(
          duration: AppMotion.normal,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: const Color(0xFFF7F3E8),
            borderRadius: BorderRadius.circular(widget.size * 0.2),
            border: Border.all(
              color: widget.enabled ? skin.accent : skin.edge,
              width: widget.enabled ? 2.5 : 1.5,
            ),
            boxShadow: widget.enabled
                ? <BoxShadow>[
                    BoxShadow(
                      color: skin.accent.withValues(alpha: 0.4),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: AnimatedBuilder(
            animation: _tumble,
            builder: (BuildContext context, Widget? child) => Transform.rotate(
              // A quarter turn back and forth while it tumbles, settling
              // square. Enough to read as movement without becoming a spinner.
              angle: rolling ? math.sin(_tumble.value * math.pi * 4) * 0.22 : 0,
              child: CustomPaint(
                painter: _DiePainter(
                  face: widget.value == null && !rolling ? 0 : _face,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiePainter extends CustomPainter {
  const _DiePainter({required this.face});

  /// 1 to 6, or 0 for a blank die — nothing has been rolled yet.
  final int face;

  /// Pip positions in unit coordinates, per face. The standard arrangement:
  /// odd faces carry a centre pip, even faces do not.
  static const Map<int, List<Offset>> _pips = <int, List<Offset>>{
    1: <Offset>[Offset(0.5, 0.5)],
    2: <Offset>[Offset(0.28, 0.28), Offset(0.72, 0.72)],
    3: <Offset>[Offset(0.26, 0.26), Offset(0.5, 0.5), Offset(0.74, 0.74)],
    4: <Offset>[
      Offset(0.28, 0.28), Offset(0.72, 0.28),
      Offset(0.28, 0.72), Offset(0.72, 0.72),
    ],
    5: <Offset>[
      Offset(0.26, 0.26), Offset(0.74, 0.26), Offset(0.5, 0.5),
      Offset(0.26, 0.74), Offset(0.74, 0.74),
    ],
    6: <Offset>[
      Offset(0.28, 0.22), Offset(0.72, 0.22),
      Offset(0.28, 0.5), Offset(0.72, 0.5),
      Offset(0.28, 0.78), Offset(0.72, 0.78),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final List<Offset>? pips = _pips[face];
    if (pips == null) return;

    final Paint ink = Paint()..color = const Color(0xFF1B1B1F);
    for (final Offset pip in pips) {
      canvas.drawCircle(
        Offset(pip.dx * size.width, pip.dy * size.height),
        size.width * 0.085,
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(_DiePainter oldDelegate) => oldDelegate.face != face;
}
