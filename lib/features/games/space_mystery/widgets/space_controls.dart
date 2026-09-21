import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The thumbstick, bottom-left.
///
/// ## Why it floats
///
/// The stick appears where the thumb lands rather than at a fixed spot. A
/// fixed stick on a phone in landscape means looking down to find it, and a
/// player looking at their thumb is a player not watching the corridor. The
/// ring is drawn at the touch point and the knob moves within it, so the first
/// frame of a drag is already a direction.
///
/// ## What it sends
///
/// A unit vector, at most once per frame, and only when it has changed enough
/// to matter. It never sends a position — the server integrates the direction
/// against the floor plan on its own tick, which is what stops a modified
/// client walking through a bulkhead.
class SpaceJoystick extends StatefulWidget {
  const SpaceJoystick({
    required this.enabled,
    required this.onMove,
    required this.onRelease,
    super.key,
  });

  final bool enabled;

  /// A direction, already clamped to a unit vector or shorter.
  final void Function(double dx, double dy) onMove;

  final VoidCallback onRelease;

  @override
  State<SpaceJoystick> createState() => _SpaceJoystickState();
}

class _SpaceJoystickState extends State<SpaceJoystick> {
  Offset? _origin;
  Offset _knob = Offset.zero;

  /// The last direction actually sent, so an unchanged one is not resent.
  Offset _sent = Offset.zero;

  static const double _radius = 46;

  void _update(Offset local) {
    final Offset origin = _origin ??= local;
    Offset delta = local - origin;

    // Clamped to the ring: pushing further than the edge is still "full
    // speed that way" rather than a longer vector.
    if (delta.distance > _radius) {
      delta = delta / delta.distance * _radius;
    }
    setState(() => _knob = delta);

    final Offset direction = delta / _radius;
    // A dead zone, so resting a thumb is not a slow drift.
    final Offset next = direction.distance < 0.12 ? Offset.zero : direction;

    // Only when it has actually changed. At twenty frames a second an
    // unchanged direction is a packet that tells the server nothing.
    if ((next - _sent).distance < 0.04) return;
    _sent = next;
    widget.onMove(next.dx, next.dy);
  }

  void _release() {
    setState(() {
      _origin = null;
      _knob = Offset.zero;
    });
    if (_sent != Offset.zero) {
      _sent = Offset.zero;
      widget.onRelease();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: widget.enabled ? (DragStartDetails d) => _update(d.localPosition) : null,
      onPanUpdate: widget.enabled ? (DragUpdateDetails d) => _update(d.localPosition) : null,
      onPanEnd: widget.enabled ? (_) => _release() : null,
      onPanCancel: widget.enabled ? _release : null,
      child: SizedBox(
        width: _radius * 3.2,
        height: _radius * 3.2,
        child: _origin == null
            ? _Resting(skin: skin, radius: _radius)
            : CustomPaint(
                painter: _StickPainter(
                  origin: _origin!,
                  knob: _knob,
                  radius: _radius,
                  skin: skin,
                ),
              ),
      ),
    );
  }
}

/// The hint shown before a thumb lands, so the control is discoverable.
class _Resting extends StatelessWidget {
  const _Resting({required this.skin, required this.radius});

  final GameSkin skin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        width: radius * 1.6,
        height: radius * 1.6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: skin.surface.withValues(alpha: 0.3),
          border: Border.all(color: skin.edge.withValues(alpha: 0.6)),
        ),
        child: Icon(
          Icons.gamepad_outlined,
          color: skin.inkMuted.withValues(alpha: 0.7),
          size: radius * 0.7,
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  const _StickPainter({
    required this.origin,
    required this.knob,
    required this.radius,
    required this.skin,
  });

  final Offset origin;
  final Offset knob;
  final double radius;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      origin,
      radius,
      Paint()..color = skin.surface.withValues(alpha: 0.42),
    );
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = skin.edge,
    );
    canvas.drawCircle(
      origin + knob,
      radius * 0.42,
      Paint()..color = skin.accent.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_StickPainter oldDelegate) =>
      oldDelegate.knob != knob || oldDelegate.origin != origin;
}

/// What the player can do *right now*, bottom-right.
///
/// ## Only what is legal
///
/// Every button here is derived from the same projection the server validates
/// against, so a control that would be refused is not drawn. That is a
/// courtesy rather than a rule — the server checks all of it again — but it is
/// the difference between a game that feels responsive and one where half the
/// taps produce an error.
///
/// The elimination button is the exception: it is always *visible* to a
/// saboteur, greyed while on cooldown with the seconds on it, because knowing
/// how long is left is most of what a saboteur is planning around.
class SpaceActions extends StatelessWidget {
  const SpaceActions({
    required this.state,
    required this.map,
    required this.onUse,
    required this.onReport,
    required this.onEliminate,
    required this.onMeeting,
    required this.onSabotage,
    required this.onVent,
    super.key,
  });

  final SpaceMysteryState state;
  final ShipMap map;
  final ValueChanged<String> onUse;
  final VoidCallback onReport;
  final ValueChanged<String> onEliminate;
  final VoidCallback onMeeting;
  final VoidCallback onSabotage;
  final VoidCallback onVent;

  /// Matches the server's own interaction reach.
  static const double _interact = 3.5;
  static const double _strike = 3.2;

  @override
  Widget build(BuildContext context) {
    final SpaceSelf self = state.self;
    if (!self.alive) return const SizedBox.shrink();

    final GameMetrics metrics = context.metrics;

    final ShipStation? station = _stationInReach();
    final SpaceBody? body = state.bodyWithin(_interact);
    final SpaceCrewmate? target = self.isSaboteur ? state.targetWithin(_strike) : null;
    final bool atTable =
        (self.position - map.meetingTable).distance <= 9 && self.emergenciesLeft > 0;
    final ShipVent? vent = self.isSaboteur ? _ventInReach() : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (self.isSaboteur)
          _ActionButton(
            label: 'Eliminate',
            icon: Icons.bolt_rounded,
            tone: context.skin.danger,
            // Visible on cooldown, with the count, because the clock is the
            // thing a saboteur plans around.
            cooldownSeconds:
                self.killCooldownMs > 0 ? (self.killCooldownMs / 1000).ceil() : null,
            onPressed: target == null || !self.canEliminate
                ? null
                : () => onEliminate(target.playerId),
          ),

        if (self.isSaboteur && state.sabotage == null)
          _ActionButton(
            label: 'Sabotage',
            icon: Icons.warning_amber_rounded,
            tone: context.skin.danger,
            small: true,
            onPressed: self.killCooldownMs > 0 ? null : onSabotage,
          ),

        if (vent != null)
          _ActionButton(
            label: self.isVenting ? 'Climb out' : 'Vent',
            icon: Icons.air_rounded,
            tone: context.skin.danger,
            small: true,
            onPressed: onVent,
          ),

        if (body != null)
          _ActionButton(
            label: 'Report',
            icon: Icons.campaign_rounded,
            tone: context.skin.accent,
            onPressed: onReport,
          ),

        if (atTable)
          _ActionButton(
            label: 'Emergency',
            icon: Icons.notifications_active_rounded,
            tone: context.skin.accent,
            small: true,
            onPressed: onMeeting,
          ),

        if (station != null && !self.isWorking)
          _ActionButton(
            label: 'Use',
            icon: Icons.settings_input_component_rounded,
            tone: context.skin.success,
            onPressed: () => onUse(station.id),
          ),

        SizedBox(height: metrics.gutter * 0.3),
      ],
    );
  }

  /// The nearest console that is on this player's own list and not yet done.
  ///
  /// Saboteurs have a fake list and it works the same way, which is the point:
  /// a saboteur standing at a console looks exactly like a crewmate doing so,
  /// because they are doing the same thing.
  ShipStation? _stationInReach() {
    final Set<String> outstanding = <String>{
      for (final SpaceTask task in state.self.tasks)
        if (!task.done) task.stationId,
    };

    ShipStation? best;
    double bestSpan = _interact;
    for (final ShipStation station in map.stations) {
      if (!outstanding.contains(station.id)) continue;
      final double span = (station.position - state.self.position).distance;
      if (span <= bestSpan) {
        best = station;
        bestSpan = span;
      }
    }
    return best;
  }

  ShipVent? _ventInReach() {
    for (final ShipVent vent in map.vents) {
      if ((vent.position - state.self.position).distance <= _interact) return vent;
    }
    return null;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.tone,
    required this.onPressed,
    this.cooldownSeconds,
    this.small = false,
  });

  final String label;
  final IconData icon;
  final Color tone;
  final VoidCallback? onPressed;

  /// Shown instead of the label while the action is on a timer.
  final int? cooldownSeconds;

  final bool small;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final bool enabled = onPressed != null;
    final double side = (small ? 48 : 66) * metrics.scale;

    return Padding(
      padding: EdgeInsets.only(bottom: metrics.gutter * 0.5),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? tone.withValues(alpha: 0.22)
                  : skin.surface.withValues(alpha: 0.6),
              border: Border.all(
                color: enabled ? tone : skin.edge,
                width: enabled ? 2 : 1,
              ),
              boxShadow: enabled
                  ? <BoxShadow>[
                      BoxShadow(
                        color: tone.withValues(alpha: 0.35),
                        blurRadius: 12 * metrics.scale,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: side * 0.34,
                  color: enabled ? tone : skin.inkMuted,
                ),
                Text(
                  cooldownSeconds != null ? '${cooldownSeconds}s' : label,
                  style: TextStyle(
                    color: enabled ? tone : skin.inkMuted,
                    fontSize: side * 0.145,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The repair bar, top-left.
///
/// One number for the whole crew, which is all the server sends. It moves when
/// anybody finishes anything, and nobody can tell whose task it was — which is
/// what stops it being a way to work out who is really doing tasks.
class TaskProgressBar extends StatelessWidget {
  const TaskProgressBar({required this.state, super.key});

  final SpaceMysteryState state;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: 148 * metrics.scale,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gutter * 0.6,
        vertical: metrics.gutter * 0.4,
      ),
      decoration: BoxDecoration(
        color: skin.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: skin.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'REPAIRS',
            style: text.labelSmall?.copyWith(
              color: skin.inkMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          SizedBox(height: metrics.gutter * 0.3),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: LinearProgressIndicator(
              value: state.taskProgress.clamp(0, 1),
              minHeight: 6 * metrics.scale,
              backgroundColor: skin.backdrop.last,
              valueColor: AlwaysStoppedAnimation<Color>(skin.success),
            ),
          ),
          SizedBox(height: metrics.gutter * 0.25),
          Text(
            '${state.taskDone} of ${state.taskTotal}',
            style: text.labelSmall?.copyWith(color: skin.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// The alarm strip, when the ship is being sabotaged.
class SabotageBanner extends StatelessWidget {
  const SabotageBanner({required this.sabotage, super.key});

  final SpaceSabotage sabotage;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final int seconds = (sabotage.remainingMs / 1000).ceil();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gutter,
        vertical: metrics.gutter * 0.45,
      ),
      decoration: BoxDecoration(
        // A failure that can end the match and one that merely costs the crew
        // should not shout in the same voice.
        color: (sabotage.critical ? skin.danger : skin.accent)
            .withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            sabotage.critical
                ? Icons.warning_rounded
                : Icons.error_outline_rounded,
            color: skin.ink,
            size: 16 * metrics.scale,
          ),
          SizedBox(width: metrics.gutter * 0.4),
          Flexible(
            child: Text(
              sabotage.kind.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(
                color: skin.ink,
                fontFamily: skin.display,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),

          // The count only means something where there is something to hold.
          // A comms jam has no console, so it gets a clock and nothing else.
          if (sabotage.answerable) ...<Widget>[
            SizedBox(width: metrics.gutter * 0.5),
            Text(
              '${seconds}s · ${sabotage.heldCount}/${sabotage.stations.length} held',
              style: text.labelMedium?.copyWith(
                color: skin.ink.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else ...<Widget>[
            SizedBox(width: metrics.gutter * 0.5),
            Text(
              '${seconds}s',
              style: text.labelMedium?.copyWith(
                color: skin.ink.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small compass pointing at the nearest outstanding task.
///
/// The ship is a ring and the camera is tight, so "where is my next job" is a
/// genuinely hard question on a phone — and a player wandering the deck
/// looking for a console is a player not paying attention to anybody else,
/// which is the opposite of what this game wants.
class TaskCompass extends StatelessWidget {
  const TaskCompass({required this.state, required this.map, super.key});

  final SpaceMysteryState state;
  final ShipMap map;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;

    final Set<String> outstanding = <String>{
      for (final SpaceTask task in state.self.tasks)
        if (!task.done) task.stationId,
    };

    ShipStation? nearest;
    double bestSpan = double.infinity;
    for (final ShipStation station in map.stations) {
      if (!outstanding.contains(station.id)) continue;
      final double span = (station.position - state.self.position).distance;
      if (span < bestSpan) {
        nearest = station;
        bestSpan = span;
      }
    }

    if (nearest == null) return const SizedBox.shrink();

    final Offset delta = nearest.position - state.self.position;
    final double angle = math.atan2(delta.dy, delta.dx);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gutter * 0.6,
        vertical: metrics.gutter * 0.35,
      ),
      decoration: BoxDecoration(
        color: skin.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: skin.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Transform.rotate(
            angle: angle,
            child: Icon(
              Icons.navigation_rounded,
              color: skin.accent,
              size: 14 * metrics.scale,
            ),
          ),
          SizedBox(width: metrics.gutter * 0.35),
          Text(
            nearest.name,
            style: TextStyle(
              color: skin.ink,
              fontSize: 10 * metrics.scale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
