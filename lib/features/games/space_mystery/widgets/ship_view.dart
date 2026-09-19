import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';

/// The *Meridian*, drawn.
///
/// ## The camera
///
/// Follows the player, scaled so roughly the sight radius fits on screen. That
/// is not a stylistic choice: the server only *sends* what this player can
/// see, so a camera showing more than that would show empty rooms where
/// crewmates are standing, and the player would learn that a room looks empty
/// when it is not. Framing the view to what is known keeps the drawing honest.
///
/// A dead player is an exception and is given the whole deck, because they are
/// sent everything anyway and have nothing left to do with it.
///
/// ## Original, and not by accident
///
/// The ship, its rooms, its layout and the crewmates are ours. The crewmates
/// are a rounded capsule with a visor and a pack — a shape that reads as a
/// person in a suit at sixteen pixels, which is the only real constraint — and
/// the palette, proportions and room plan share nothing with any existing
/// game. See `spaceMystery/map.ts` for the deck itself.
class ShipView extends StatelessWidget {
  const ShipView({
    required this.map,
    required this.state,
    required this.selfId,
    super.key,
  });

  final ShipMap map;
  final SpaceMysteryState state;
  final String selfId;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ShipPainter(
        map: map,
        state: state,
        selfId: selfId,
        skin: context.skin,
      ),
      size: Size.infinite,
      isComplex: true,
    );
  }
}

class _ShipPainter extends CustomPainter {
  _ShipPainter({
    required this.map,
    required this.state,
    required this.selfId,
    required this.skin,
  });

  final ShipMap map;
  final SpaceMysteryState state;
  final String selfId;
  final GameSkin skin;

  /// How many world units of the deck to fit across the screen's short side.
  ///
  /// Matches the server's sight radius closely enough that the edge of the
  /// screen is roughly the edge of what is known.
  static const double _viewSpan = 46;

  /// The seat colours. Eight, distinguishable at sixteen pixels and in the
  /// dark — which rules out most of a normal palette.
  static const List<Color> _suits = <Color>[
    Color(0xFFE8574C), Color(0xFF4C9FE8), Color(0xFF5BD98A), Color(0xFFE8C34C),
    Color(0xFFB97CE8), Color(0xFFE88B4C), Color(0xFF4CE8D2), Color(0xFFE87CB6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (map.isEmpty) return;

    final bool wideView = !state.self.alive || state.inMeeting;
    final double span = wideView ? map.world.width : _viewSpan;
    final double scale = size.shortestSide / span * (wideView ? 0.62 : 1);

    final Offset focus = wideView
        ? Offset(map.world.width / 2, map.world.height / 2)
        : state.self.position;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);

    _paintDeck(canvas);
    _paintStations(canvas);
    if (state.self.isTraitor) _paintVents(canvas);
    _paintBreachSwitches(canvas);
    _paintBodies(canvas);
    _paintCrew(canvas);

    canvas.restore();

    // The dark, drawn over everything in screen space rather than world space
    // so it does not scale with the camera.
    if (!wideView) _paintVignette(canvas, size);
  }

  /// Floors and walls.
  void _paintDeck(Canvas canvas) {
    final Paint floor = Paint()..color = skin.surface;
    final Paint corridor = Paint()..color = skin.surface.withValues(alpha: 0.82);
    final Paint wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55
      ..color = skin.edge;

    for (final Rect hall in map.corridors) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hall, const Radius.circular(0.8)),
        corridor,
      );
    }

    for (final ShipRoom room in map.rooms) {
      final RRect body = RRect.fromRectAndRadius(
        room.bounds,
        const Radius.circular(1.6),
      );
      canvas.drawRRect(body, floor);

      // A panel light on the ceiling of each room. Cheap, and it is what makes
      // the deck read as lit rather than as a floor plan.
      canvas.drawRRect(
        body,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              skin.surfaceRaised.withValues(alpha: 0.9),
              skin.surface.withValues(alpha: 0),
            ],
          ).createShader(room.bounds),
      );
      canvas.drawRRect(body, wall);

      _label(canvas, room.name.toUpperCase(), room.bounds.center, 1.5,
          skin.inkMuted.withValues(alpha: 0.5));
    }
  }

  void _paintStations(Canvas canvas) {
    final Set<String> mine = <String>{
      for (final SpaceTask task in state.self.tasks)
        if (!task.done) task.stationId,
    };
    final Set<String> done = <String>{
      for (final SpaceTask task in state.self.tasks)
        if (task.done) task.stationId,
    };

    for (final ShipStation station in map.stations) {
      final bool outstanding = mine.contains(station.id);
      final bool finished = done.contains(station.id);

      // Only this player's own tasks are marked. Everybody else's are
      // furniture, because a client that could see whose task was where could
      // work out who was lying about where they had been.
      final Color tint = outstanding
          ? skin.accent
          : finished
              ? skin.success
              : skin.edge;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: station.position, width: 2.2, height: 1.6),
          const Radius.circular(0.4),
        ),
        Paint()..color = tint.withValues(alpha: outstanding ? 0.9 : 0.45),
      );

      if (outstanding) {
        // A pulse ring, so an outstanding task is findable across a room.
        canvas.drawCircle(
          station.position,
          2.6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.35
            ..color = skin.accent.withValues(alpha: 0.55),
        );
      }
    }
  }

  /// Only ever called for a traitor. A crewmate is never shown a vent.
  void _paintVents(Canvas canvas) {
    for (final ShipVent vent in map.vents) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: vent.position, width: 2, height: 2),
          const Radius.circular(0.3),
        ),
        Paint()..color = skin.danger.withValues(alpha: 0.65),
      );
      for (int line = 0; line < 3; line++) {
        canvas.drawLine(
          Offset(vent.position.dx - 0.7, vent.position.dy - 0.5 + line * 0.5),
          Offset(vent.position.dx + 0.7, vent.position.dy - 0.5 + line * 0.5),
          Paint()
            ..strokeWidth = 0.18
            ..color = skin.backdrop.last,
        );
      }
    }
  }

  void _paintBreachSwitches(Canvas canvas) {
    final SpaceSabotage? sabotage = state.sabotage;
    if (sabotage == null || sabotage.kind != SabotageKind.breach) return;

    final List<bool> held = <bool>[
      for (final MapEntry<String, bool> entry in sabotage.holds.entries) entry.value,
    ];

    for (int index = 0; index < map.breachStations.length; index++) {
      final bool isHeld = index < held.length && held[index];
      canvas.drawCircle(
        map.breachStations[index],
        2.4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = isHeld ? skin.success : skin.danger,
      );
      canvas.drawCircle(
        map.breachStations[index],
        1.4,
        Paint()..color = (isHeld ? skin.success : skin.danger).withValues(alpha: 0.7),
      );
    }
  }

  void _paintBodies(Canvas canvas) {
    for (final SpaceBody body in state.bodies) {
      final Color suit = _suits[state.colourIndexOf(body.playerId) % _suits.length];

      // A body is the same shape lying down, plus a spreading stain — legible
      // at a glance from across a room, which is what makes finding one an
      // event rather than something a player walks past.
      canvas.drawOval(
        Rect.fromCenter(center: body.position, width: 4.4, height: 2.6),
        Paint()..color = skin.danger.withValues(alpha: 0.25),
      );
      canvas.save();
      canvas.translate(body.position.dx, body.position.dy);
      canvas.rotate(math.pi / 2);
      _paintCrewmate(canvas, Offset.zero, suit, facing: 1, dimmed: true);
      canvas.restore();
    }
  }

  void _paintCrew(Canvas canvas) {
    for (final SpaceCrewmate mate in state.visible) {
      if (!mate.alive) continue;
      if (mate.venting && mate.playerId != selfId) continue;

      final Color suit = _suits[state.colourIndexOf(mate.playerId) % _suits.length];
      final bool isSelf = mate.playerId == selfId;

      // A fellow traitor is rimmed, which is the one piece of information a
      // traitor is entitled to and a crewmate never receives.
      final bool ally = state.self.isTraitor &&
          state.self.allies.contains(mate.playerId);

      _paintCrewmate(
        canvas,
        mate.position,
        suit,
        facing: mate.facing,
        dimmed: mate.venting,
        ring: isSelf
            ? skin.ink
            : ally
                ? skin.danger
                : null,
      );

      if (mate.working) {
        // Busy at a console. Public, and the whole reason a traitor bothers
        // to stand at one.
        canvas.drawCircle(
          mate.position + const Offset(0, -3),
          0.55,
          Paint()..color = skin.accent,
        );
      }

      _label(canvas, mate.username, mate.position + const Offset(0, 3.4), 1.4,
          isSelf ? skin.ink : skin.inkMuted);
    }
  }

  /// One crewmate: a capsule body, a visor, a pack.
  ///
  /// Three shapes, because at the size this renders — twenty pixels or so —
  /// anything more detailed is mud. The visor is what makes it read as facing
  /// a direction, and the direction is what makes a player able to tell at a
  /// glance whether somebody is walking towards them.
  void _paintCrewmate(
    Canvas canvas,
    Offset at,
    Color suit, {
    required int facing,
    bool dimmed = false,
    Color? ring,
  }) {
    final double alpha = dimmed ? 0.4 : 1;

    // The pack on the back, on the opposite side from the visor.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: at + Offset(-facing * 1.25, 0.2),
          width: 1.1,
          height: 2.2,
        ),
        const Radius.circular(0.45),
      ),
      Paint()..color = suit.withValues(alpha: alpha * 0.65),
    );

    // The body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: at, width: 2.4, height: 3.2),
        const Radius.circular(1.15),
      ),
      Paint()..color = suit.withValues(alpha: alpha),
    );

    // The visor, offset the way they are facing.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: at + Offset(facing * 0.42, -0.55),
          width: 1.35,
          height: 0.85,
        ),
        const Radius.circular(0.42),
      ),
      Paint()..color = const Color(0xFFBFE6FF).withValues(alpha: alpha),
    );

    if (ring != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: at, width: 3.2, height: 4),
          const Radius.circular(1.5),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.3
          ..color = ring,
      );
    }
  }

  /// The edge of what is known, drawn as darkness closing in.
  void _paintVignette(Canvas canvas, Size size) {
    final bool dark = state.sabotage?.kind == SabotageKind.lights;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          // Tighter with the lights out, which is the whole effect of that
          // sabotage and the reason it is frightening.
          radius: dark ? 0.32 : 0.62,
          colors: <Color>[
            const Color(0x00000000),
            skin.backdrop.last.withValues(alpha: dark ? 0.97 : 0.88),
          ],
          stops: const <double>[0.55, 1],
        ).createShader(Offset.zero & size),
    );
  }

  void _label(Canvas canvas, String value, Offset centre, double size, Color ink) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: ink,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, centre - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_ShipPainter oldDelegate) => true;
}
