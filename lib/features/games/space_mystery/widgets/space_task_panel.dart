import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The console panel that opens while a task is being worked.
///
/// ## The client cannot finish a task
///
/// This is the whole design of it. The server started a timer when the player
/// pressed USE, it is counting down on the server, and it will mark the task
/// done when *it* decides the time has elapsed and the player is still
/// standing there. Everything below is a view of `you.working.remainingMs`.
///
/// So the mini-game is honest about what it is: something to do with your
/// hands while the console works, and a reason the player is looking at the
/// panel instead of the corridor — which is exactly the vulnerability that
/// makes doing tasks dangerous, and the reason a traitor waits for it.
/// Fiddling with it faster does not finish it faster, and a client that
/// skipped it entirely would still take the same time.
///
/// ## Why there are several
///
/// A single progress ring on eighteen consoles would make the whole ship feel
/// like one interaction. Each station picks a variant from its own id, so the
/// reactor always feels like the reactor, and a player learns the ship.
class SpaceTaskPanel extends StatefulWidget {
  const SpaceTaskPanel({
    required this.station,
    required this.remainingMs,
    required this.totalMs,
    super.key,
  });

  final ShipStation station;

  /// Counted by the server. This is the only clock that matters.
  final int remainingMs;
  final int totalMs;

  @override
  State<SpaceTaskPanel> createState() => _SpaceTaskPanelState();
}

class _SpaceTaskPanelState extends State<SpaceTaskPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  /// Which dials the player has fiddled with. Cosmetic, and deliberately so.
  final Set<int> _touched = <int>{};

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  /// Which mini-game this console runs, picked from its own id so it is the
  /// same one every time anybody uses it.
  _TaskKind get _kind =>
      _TaskKind.values[widget.station.id.hashCode.abs() % _TaskKind.values.length];

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final double progress = widget.totalMs <= 0
        ? 0
        : (1 - widget.remainingMs / widget.totalMs).clamp(0.0, 1.0);

    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 300 * metrics.scale,
        padding: EdgeInsets.all(metrics.gutter),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: skin.accent, width: AppSpacing.border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: skin.glow.withValues(alpha: 0.25),
              blurRadius: 26 * metrics.scale,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.settings_input_component_rounded,
                  color: skin.accent,
                  size: 16 * metrics.scale,
                ),
                SizedBox(width: metrics.gutter * 0.4),
                Expanded(
                  child: Text(
                    widget.station.name,
                    style: text.labelLarge?.copyWith(
                      color: skin.ink,
                      fontFamily: skin.display,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${(widget.remainingMs / 1000).ceil()}s',
                  style: text.labelLarge?.copyWith(
                    color: skin.accent,
                    fontFamily: skin.display,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            SizedBox(height: metrics.gutter * 0.8),

            SizedBox(
              height: 96 * metrics.scale,
              child: AnimatedBuilder(
                animation: _idle,
                builder: (BuildContext context, _) => _body(progress, skin, metrics),
              ),
            ),

            SizedBox(height: metrics.gutter * 0.7),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5 * metrics.scale,
                backgroundColor: skin.backdrop.last,
                valueColor: AlwaysStoppedAnimation<Color>(skin.success),
              ),
            ),
            SizedBox(height: metrics.gutter * 0.4),
            Text(
              'Stay at the console. Walking away cancels it.',
              style: text.labelSmall?.copyWith(color: skin.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(double progress, GameSkin skin, GameMetrics metrics) {
    return switch (_kind) {
      _TaskKind.calibrate => _Calibrate(
          progress: progress,
          phase: _idle.value,
          skin: skin,
          touched: _touched,
          onTouch: (int index) => setState(() => _touched.add(index)),
        ),
      _TaskKind.sequence => _Sequence(
          progress: progress,
          skin: skin,
          touched: _touched,
          onTouch: (int index) => setState(() => _touched.add(index)),
        ),
      _TaskKind.align => _Align(progress: progress, phase: _idle.value, skin: skin),
      _TaskKind.upload => _Upload(progress: progress, skin: skin),
    };
  }
}

/// The four consoles the ship runs. Each station keeps its own for the match.
enum _TaskKind { calibrate, sequence, align, upload }

/// Power calibration: sliders to nudge into a band.
class _Calibrate extends StatelessWidget {
  const _Calibrate({
    required this.progress,
    required this.phase,
    required this.skin,
    required this.touched,
    required this.onTouch,
  });

  final double progress;
  final double phase;
  final GameSkin skin;
  final Set<int> touched;
  final ValueChanged<int> onTouch;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        for (int index = 0; index < 4; index++)
          GestureDetector(
            onTap: () => onTouch(index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Container(
                  width: 18,
                  height: 68,
                  decoration: BoxDecoration(
                    color: skin.backdrop.last,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: skin.edge),
                  ),
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: touched.contains(index)
                        ? 0.85
                        : 0.25 + 0.2 * math.sin(phase * math.pi * 2 + index),
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: touched.contains(index) ? skin.success : skin.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  touched.contains(index)
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 12,
                  color: touched.contains(index) ? skin.success : skin.inkMuted,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Reactor sequence: press the lit cells.
class _Sequence extends StatelessWidget {
  const _Sequence({
    required this.progress,
    required this.skin,
    required this.touched,
    required this.onTouch,
  });

  final double progress;
  final GameSkin skin;
  final Set<int> touched;
  final ValueChanged<int> onTouch;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
      ),
      itemCount: 10,
      itemBuilder: (BuildContext context, int index) {
        final bool lit = index % 3 == 0;
        final bool done = touched.contains(index);

        return GestureDetector(
          onTap: lit ? () => onTouch(index) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: done
                  ? skin.success.withValues(alpha: 0.7)
                  : lit
                      ? skin.accent.withValues(alpha: 0.55)
                      : skin.backdrop.last,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: skin.edge),
            ),
          ),
        );
      },
    );
  }
}

/// Navigation: a drifting crosshair settling onto a mark.
class _Align extends StatelessWidget {
  const _Align({required this.progress, required this.phase, required this.skin});

  final double progress;
  final double phase;
  final GameSkin skin;

  @override
  Widget build(BuildContext context) {
    // Converges as the server's clock runs down, so the picture agrees with
    // the only progress that is real.
    final double drift = (1 - progress) * 26;

    return CustomPaint(
      size: Size.infinite,
      painter: _AlignPainter(drift: drift, phase: phase, skin: skin),
    );
  }
}

class _AlignPainter extends CustomPainter {
  const _AlignPainter({
    required this.drift,
    required this.phase,
    required this.skin,
  });

  final double drift;
  final double phase;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);

    canvas.drawCircle(
      centre,
      size.height * 0.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = skin.edge,
    );
    canvas.drawCircle(
      centre,
      size.height * 0.16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = skin.edge,
    );

    final Offset mark = centre +
        Offset(
          math.cos(phase * math.pi * 2) * drift,
          math.sin(phase * math.pi * 3) * drift * 0.6,
        );

    final Paint cross = Paint()
      ..strokeWidth = 1.6
      ..color = drift < 4 ? skin.success : skin.accent;
    canvas.drawLine(mark - const Offset(9, 0), mark + const Offset(9, 0), cross);
    canvas.drawLine(mark - const Offset(0, 9), mark + const Offset(0, 9), cross);
  }

  @override
  bool shouldRepaint(_AlignPainter oldDelegate) =>
      oldDelegate.drift != drift || oldDelegate.phase != phase;
}

/// Data upload: a bar and a scrolling manifest.
class _Upload extends StatelessWidget {
  const _Upload({required this.progress, required this.skin});

  final double progress;
  final GameSkin skin;

  @override
  Widget build(BuildContext context) {
    final int rows = (progress * 6).floor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int index = 0; index < 6; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: <Widget>[
                Icon(
                  index < rows
                      ? Icons.check_circle_rounded
                      : Icons.more_horiz_rounded,
                  size: 11,
                  color: index < rows ? skin.success : skin.inkMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: index < rows
                          ? skin.success.withValues(alpha: 0.6)
                          : skin.backdrop.last,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
