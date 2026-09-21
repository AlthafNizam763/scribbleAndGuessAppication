import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';

/// **ORBITAL-7**, drawn.
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
/// The station, its modules, its layout and the crew are ours. A crew member
/// is a separate spherical helmet on a visible collar, a squared torso that
/// tapers to a waist, and two planted boots — head, shoulders, body, feet,
/// with real joins between them. See [_paintCrewmate] for what that shape is
/// deliberately *not*, and `spaceMystery/map.ts` for the station itself.
class ShipView extends StatefulWidget {
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
  State<ShipView> createState() => _ShipViewState();
}

class _ShipViewState extends State<ShipView>
    with SingleTickerProviderStateMixin {
  /// Where each body is being drawn, between the last two frames.
  ///
  /// ## Why the drawing does not simply use the server's numbers
  ///
  /// Because there are only ten of them a second. The simulation runs at
  /// twenty hertz and broadcasts every other tick, so a client that painted
  /// the coordinates as they arrived would move every character in a series of
  /// ten jumps a second while the display refreshes six times as often. That
  /// reads as stuttering, and on a body moving fourteen units a second the
  /// jumps are over a body-width each.
  ///
  /// So each frame is treated as a *destination*: the painter keeps drawing
  /// towards it until the next one arrives. The result is smooth at any
  /// refresh rate and, importantly, is still the server's position — this
  /// never predicts, never extrapolates past what it was told, and never lets
  /// a character arrive anywhere the server did not put it. A client that
  /// guessed ahead would show people walking through walls the moment a packet
  /// was late.
  final Map<String, _Glide> _glides = <String, _Glide>{};

  /// Created in [initState], never lazily.
  ///
  /// `createTicker` reads `TickerMode` from the element tree, so a `late final`
  /// that is first touched in [dispose] builds the ticker while the element is
  /// already deactivated — which is an ancestor lookup on a dead tree.
  Ticker? _ticker;

  /// The wire's own cadence: two 20 Hz ticks. Positions are blended over
  /// exactly one broadcast, so the drawing is always catching up to the last
  /// thing the server said rather than racing ahead of it.
  static const Duration _interval = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _absorb();
  }

  /// Advances the blend, and stops when there is nothing left to blend.
  ///
  /// Stopping matters for more than battery: a ticker that runs forever is a
  /// tree that never goes idle, and `pumpAndSettle` on any screen containing
  /// this one would spin until it timed out.
  void _onTick(Duration _) {
    if (!mounted) return;
    setState(() {});
    if (_glides.values.every((_Glide glide) => glide.settled)) _ticker?.stop();
  }

  @override
  void didUpdateWidget(ShipView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A meeting teleports everybody to the hub, and so does a match starting.
    // Blending across either would drag the whole crew over the floor plan, so
    // those land instantly.
    _absorb(snap: oldWidget.state.inMeeting != widget.state.inMeeting);
  }

  /// Takes the newest frame as the destination for everybody in it.
  void _absorb({bool snap = false}) {
    final Set<String> present = <String>{};

    for (final SpaceCrewmate mate in widget.state.visible) {
      present.add(mate.playerId);
      final _Glide? current = _glides[mate.playerId];

      _glides[mate.playerId] = _Glide(
        // From wherever it is being drawn right now, not from the previous
        // frame's raw value: a frame that arrives early must not snap the
        // character backwards to where the last blend started.
        from: snap || current == null ? mate.position : current.at(),
        to: mate.position,
        startedAt: DateTime.now(),
      );
    }

    // Somebody who walked out of sight. Dropped rather than left to glide to a
    // position that is no longer being sent.
    _glides.removeWhere((String id, _Glide _) => !present.contains(id));

    // Only run the clock while something is actually moving.
    final bool moving = _glides.values.any((_Glide glide) => !glide.settled);
    final Ticker? ticker = _ticker;
    if (ticker == null) return;
    if (moving && !ticker.isActive) {
      ticker.start();
    } else if (!moving && ticker.isActive) {
      ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ShipPainter(
        map: widget.map,
        state: widget.state,
        selfId: widget.selfId,
        skin: context.skin,
        positions: <String, Offset>{
          for (final MapEntry<String, _Glide> entry in _glides.entries)
            entry.key: entry.value.at(),
        },
      ),
      size: Size.infinite,
      isComplex: true,
    );
  }
}

/// One body's journey between two frames.
@immutable
class _Glide {
  const _Glide({required this.from, required this.to, required this.startedAt});

  final Offset from;
  final Offset to;
  final DateTime startedAt;

  /// Whether there is any blending left to do.
  ///
  /// True immediately for a jump, and for a body that has not moved at all —
  /// which is most bodies on most frames, and is what lets the ticker stop.
  bool get settled => _progress >= 1 || (to - from).distance > _jump;

  /// Where to draw it now.
  ///
  /// Clamped at 1, so a client that stops receiving frames settles on the last
  /// position the server actually sent rather than sliding past it.
  Offset at() {
    // A long gap — a dropped connection, a meeting, a match starting — is a
    // jump rather than a very slow walk across the deck.
    if ((to - from).distance > _jump) return to;
    return Offset.lerp(from, to, _progress) ?? to;
  }

  double get _progress {
    final int elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    return (elapsed / _ShipViewState._interval.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Further than anybody can walk in one broadcast, so it was not a walk.
  static const double _jump = 12;
}

class _ShipPainter extends CustomPainter {
  _ShipPainter({
    required this.map,
    required this.state,
    required this.selfId,
    required this.skin,
    required this.positions,
  });

  final ShipMap map;
  final SpaceMysteryState state;
  final String selfId;
  final GameSkin skin;

  /// Where to draw each visible body, blended between the last two frames.
  /// Falls back to the frame's own value for anybody not in here.
  final Map<String, Offset> positions;

  /// Where this body is on screen, which is not quite where the last packet
  /// said it was. See [_Glide].
  Offset _drawnAt(SpaceCrewmate mate) => positions[mate.playerId] ?? mate.position;

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

    // The camera follows the *blended* position too. Following the raw one
    // would move the whole world in ten steps a second while the character on
    // it moved smoothly, which is a worse judder than the one being fixed.
    final Offset focus = wideView
        ? Offset(map.world.width / 2, map.world.height / 2)
        : positions[selfId] ?? state.self.position;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);

    _paintDeck(canvas);
    _paintStations(canvas);
    if (state.self.isSaboteur) _paintVents(canvas);
    _paintRepairConsoles(canvas);
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

  /// Only ever called for a saboteur. A crewmate is never shown a vent.
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

  /// The consoles that answer whatever is currently going wrong.
  ///
  /// Driven off the sabotage's own station list rather than a fixed pair, so
  /// all five are drawn by one path: two rings for a critical failure, one for
  /// a nuisance, and none at all for a comms jam — which is exactly right,
  /// because there is nothing to run to.
  ///
  /// Held is green and unheld is red, recomputed from the server's own view of
  /// who is standing where. Never *who* is holding it: the alarm panel shows
  /// the station, not a roster.
  void _paintRepairConsoles(Canvas canvas) {
    final SpaceSabotage? sabotage = state.sabotage;
    if (sabotage == null || !sabotage.answerable) return;

    for (final ShipRepair station in sabotage.stations) {
      final bool isHeld = sabotage.holds[station.id] ?? false;
      final Color tone = isHeld ? skin.success : skin.danger;

      canvas.drawCircle(
        station.position,
        2.4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = tone,
      );
      canvas.drawCircle(
        station.position,
        1.4,
        Paint()..color = tone.withValues(alpha: 0.7),
      );

      // A held console reads as done at a glance, which matters when two
      // people at opposite ends of the station are trying to act together.
      if (isHeld) {
        canvas.drawCircle(
          station.position,
          3.2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.3
            ..color = skin.success.withValues(alpha: 0.5),
        );
      }
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
      _paintCrewmate(canvas, Offset.zero, suit,
          kind: state.crewKindOf(body.playerId), facing: 1, dimmed: true);
      canvas.restore();
    }
  }

  void _paintCrew(Canvas canvas) {
    for (final SpaceCrewmate mate in state.visible) {
      if (!mate.alive) continue;
      if (mate.venting && mate.playerId != selfId) continue;

      final Color suit = _suits[state.colourIndexOf(mate.playerId) % _suits.length];
      final bool isSelf = mate.playerId == selfId;

      // A fellow saboteur is rimmed, which is the one piece of information a
      // saboteur is entitled to and a crewmate never receives.
      final bool ally = state.self.isSaboteur &&
          state.self.allies.contains(mate.playerId);

      final Offset at = _drawnAt(mate);

      _paintCrewmate(
        canvas,
        at,
        suit,
        kind: state.crewKindOf(mate.playerId),
        facing: mate.facing,
        dimmed: mate.venting,
        ring: isSelf
            ? skin.ink
            : ally
                ? skin.danger
                : null,
      );

      if (mate.working) {
        // Busy at a console. Public, and the whole reason a saboteur bothers
        // to stand at one.
        canvas.drawCircle(
          at + const Offset(0, -3),
          0.55,
          Paint()..color = skin.accent,
        );
      }

      _label(canvas, mate.username, at + const Offset(0, 3.4), 1.4,
          isSelf ? skin.ink : skin.inkMuted);
    }
  }

  /// One of the Space Crew, drawn.
  ///
  /// ## The silhouette, and what it deliberately is not
  ///
  /// A **separate spherical helmet above a visible collar, a squared torso
  /// that tapers into a waist, and two boots planted below it.** Read the
  /// outline and you get head / shoulders / body / feet — four masses with real
  /// joins between them.
  ///
  /// That is a deliberate departure from the single unbroken capsule this
  /// used to draw. The old shape was a rounded bean with a wide wrap-around
  /// visor and a pack slung off the back, which is the silhouette of a
  /// well-known game and not ours to borrow. Everything that made it that
  /// shape is gone: there is no pack, the helmet is a circle that sits *on*
  /// the shoulders rather than a visor cut *into* the body, and the body has a
  /// waist and legs where the bean had a continuous curve.
  ///
  /// ## Why it still reads at this size
  ///
  /// This renders at roughly twenty pixels tall, where detail turns to mud, so
  /// the shapes are few and the contrast between them is high: the helmet
  /// glass is a light tone against the suit, the boots are a dark one. Facing
  /// is carried by the glass highlight and the shoulder lamp, both offset the
  /// way the character is walking — and facing is what lets a player tell at a
  /// glance whether somebody is coming towards them, which is worth a great
  /// deal in this game.
  void _paintCrewmate(
    Canvas canvas,
    Offset at,
    Color suit, {
    required SpaceCrewKind kind,
    required int facing,
    bool dimmed = false,
    Color? ring,
  }) {
    final double alpha = dimmed ? 0.4 : 1;
    final Paint suitPaint = Paint()..color = suit.withValues(alpha: alpha);

    // Boots, planted apart. Drawn first so the legs sit behind the torso.
    final Paint boots = Paint()
      ..color = Color.lerp(suit, const Color(0xFF10131C), 0.55)!
          .withValues(alpha: alpha);
    for (final double side in <double>[-0.62, 0.62]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: at + Offset(side, 1.55),
            width: 0.86,
            height: 0.92,
          ),
          const Radius.circular(0.3),
        ),
        boots,
      );
    }

    // The torso: square at the shoulders, drawn in to a waist. A trapezoid
    // rather than a capsule, which is most of what makes the outline read as a
    // person in a suit rather than as a pill.
    final Path torso = Path()
      ..moveTo(at.dx - 1.08, at.dy - 0.45)
      ..lineTo(at.dx + 1.08, at.dy - 0.45)
      ..lineTo(at.dx + 0.8, at.dy + 1.3)
      ..lineTo(at.dx - 0.8, at.dy + 1.3)
      ..close();
    canvas.drawPath(torso, suitPaint);

    // The collar, which is the join the old shape did not have.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: at + const Offset(0, -0.62), width: 1.25, height: 0.44),
        const Radius.circular(0.2),
      ),
      Paint()
        ..color = Color.lerp(suit, const Color(0xFF10131C), 0.35)!
            .withValues(alpha: alpha),
    );

    // A utility light on the shoulder, on the side they are facing. Small, and
    // the only ornament — it doubles as a second cue for which way they face.
    canvas.drawCircle(
      at + Offset(facing * 0.86, -0.28),
      0.26,
      Paint()..color = const Color(0xFFFFD79A).withValues(alpha: alpha * 0.9),
    );

    // The helmet: a sphere sitting on the collar, not a visor cut into a body.
    final Offset head = at + const Offset(0, -1.42);
    canvas.drawCircle(head, 0.98, suitPaint);
    canvas.drawCircle(
      head,
      0.98,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.16
        ..color = Color.lerp(suit, Colors.white, 0.4)!.withValues(alpha: alpha),
    );

    // The glass, inset and offset the way they are looking.
    canvas.drawCircle(
      head + Offset(facing * 0.2, 0.04),
      0.6,
      Paint()..color = const Color(0xFF1B2740).withValues(alpha: alpha),
    );
    canvas.drawCircle(
      head + Offset(facing * 0.34, -0.12),
      0.26,
      Paint()..color = const Color(0xFFBFE6FF).withValues(alpha: alpha * 0.95),
    );

    _paintKit(canvas, at, head, kind, facing, alpha);

    if (ring != null) {
      // An ally marker: a ring round the whole figure, clear of the helmet.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: at + const Offset(0, -0.2), width: 3.1, height: 4.5),
          const Radius.circular(1.2),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.3
          ..color = ring,
      );
    }
  }

  /// What tells the eight of them apart at a glance.
  ///
  /// One extra mark each, on the helmet or the shoulder. Deliberately small:
  /// the suit colour is still the primary identity and the thing a player says
  /// out loud, and eight silhouettes that differed wildly would stop reading
  /// as one crew. This is the second cue — the one that survives two players
  /// drawing adjacent colours, and the one that makes "the medic" a thing
  /// somebody can say and everybody can check.
  void _paintKit(
    Canvas canvas,
    Offset at,
    Offset head,
    SpaceCrewKind kind,
    int facing,
    double alpha,
  ) {
    final Paint trim = Paint()
      ..color = const Color(0xFFF2F6FF).withValues(alpha: alpha * 0.9);
    final Paint accent = Paint()
      ..color = const Color(0xFFFFD79A).withValues(alpha: alpha * 0.95);

    switch (kind) {
      case SpaceCrewKind.engineer:
        // A crest fin over the crown.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: head + const Offset(0, -0.9), width: 0.3, height: 0.7),
            const Radius.circular(0.15),
          ),
          trim,
        );
      case SpaceCrewKind.scientist:
        // A band across the brow.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: head + const Offset(0, -0.62), width: 1.7, height: 0.26),
            const Radius.circular(0.13),
          ),
          trim,
        );
      case SpaceCrewKind.navigator:
        // A lamp on a short stalk, on the side they are facing.
        canvas.drawLine(
          head + Offset(facing * 0.7, -0.6),
          head + Offset(facing * 1.15, -0.95),
          Paint()
            ..strokeWidth = 0.16
            ..color = trim.color,
        );
        canvas.drawCircle(head + Offset(facing * 1.15, -0.95), 0.24, accent);
      case SpaceCrewKind.mechanic:
        // A tool loop at the hip.
        canvas.drawCircle(
          at + Offset(-facing * 0.95, 0.75),
          0.28,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.16
            ..color = trim.color,
        );
      case SpaceCrewKind.medic:
        // A cross on the chest.
        for (final Rect bar in <Rect>[
          Rect.fromCenter(center: at + const Offset(0, 0.35), width: 0.8, height: 0.22),
          Rect.fromCenter(center: at + const Offset(0, 0.35), width: 0.22, height: 0.8),
        ]) {
          canvas.drawRect(bar, trim);
        }
      case SpaceCrewKind.security:
        // Pauldrons, squaring the shoulders off further.
        for (final double side in <double>[-1, 1]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: at + Offset(side * 1.05, -0.3),
                width: 0.42,
                height: 0.5,
              ),
              const Radius.circular(0.16),
            ),
            trim,
          );
        }
      case SpaceCrewKind.researcher:
        // A sample flask clipped to the chest.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at + Offset(facing * 0.35, 0.45), width: 0.34, height: 0.6),
            const Radius.circular(0.14),
          ),
          accent,
        );
      case SpaceCrewKind.technician:
        // Two aerial pins above the collar.
        for (final double side in <double>[-0.35, 0.35]) {
          canvas.drawLine(
            head + Offset(side, -0.88),
            head + Offset(side * 1.6, -1.35),
            Paint()
              ..strokeWidth = 0.14
              ..color = trim.color,
          );
        }
    }
  }

  /// The edge of what is known, drawn as darkness closing in.
  void _paintVignette(Canvas canvas, Size size) {
    final bool dark = state.sabotage?.kind == SabotageKind.power;

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

  // Deliberately always true: this painter is driven by a ticker whose whole
  // job is to advance the blend a frame at a time, so "has anything changed"
  // is "yes, the positions" on every single call.
}
