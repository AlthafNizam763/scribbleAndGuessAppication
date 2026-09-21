import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The console panel: the job itself, done with a thumb.
///
/// ## What changed, and why it matters to the game
///
/// This panel used to be scenery. The server ran a timer, the bar filled, and
/// nothing the player did with the dials had any bearing on the outcome —
/// fiddling faster did not finish it faster, and skipping it entirely finished
/// it just the same. That made every console on the station the same
/// interaction: hold still and wait.
///
/// Now the server deals a **puzzle** when the console is opened and sends it
/// in this player's own projection. What is below is the real thing: line the
/// bearing up, bring four channels into their bands, route the nodes in order,
/// pick out the samples, join the strands. The job finishes when ACCEPT sends
/// an answer the server agrees with, and not before.
///
/// ## What this panel still cannot do
///
/// Finish a task. It sends an answer; the server decides. It re-checks that
/// the console is open, that it is this one, that the time floor has passed
/// and that the player is *still standing at it* — so an answer cannot be sent
/// from safety, and a client that skipped the panel has nothing to send.
///
/// ## Why the vulnerability is the point
///
/// A player doing a job is looking at this panel and not at the corridor. That
/// is the cost of every task in the game and the reason a saboteur waits for
/// one, so the panel deliberately fills the middle of the screen rather than
/// tucking into a corner where it could be watched alongside the door.
class SpaceTaskPanel extends StatefulWidget {
  const SpaceTaskPanel({
    required this.station,
    required this.work,
    required this.onSubmit,
    required this.onAbort,
    super.key,
  });

  final ShipStation station;

  /// The job, as the server dealt it. Refreshed ten times a second, which is
  /// how the countdown on ACCEPT moves.
  final SpaceWork work;

  /// Sends an answer. Whether it was right comes back as a frame, not a reply.
  final ValueChanged<List<num>> onSubmit;

  /// Leaves the console. The server frees it when the player walks away too.
  final VoidCallback onAbort;

  @override
  State<SpaceTaskPanel> createState() => _SpaceTaskPanelState();
}

class _SpaceTaskPanelState extends State<SpaceTaskPanel> {
  /// The bearing the player has turned the dial to, for an `align` job.
  double _angle = 0;

  /// Where each channel is set, for a `sliders` job.
  List<double> _levels = <double>[];

  /// Which nodes have been touched, in order, for a `sequence` job.
  final List<int> _order = <int>[];

  /// Which samples are picked out, for a `match` job.
  final Set<int> _picked = <int>{};

  /// Which right-hand terminal each left-hand strand is joined to, or -1.
  List<int> _joins = <int>[];

  /// The left-hand strand waiting for its other end, for a `rewire` job.
  int _pendingStrand = -1;

  /// Set when the server refused the last answer, cleared on the next change.
  ///
  /// The refusal arrives as a `task_failed` event rather than as a reply, so
  /// this is driven from [SpaceTaskPanel.work] changing rather than from the
  /// submit call — see [didUpdateWidget].
  bool _refused = false;

  /// The answer that was last sent, so a repeat of it is not sent twice.
  String _sent = '';

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(SpaceTaskPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A different console, or the same one dealt again. Either way the working
    // state below belongs to a job that no longer exists.
    if (oldWidget.work.stationId != widget.work.stationId ||
        !_sameSpec(oldWidget.work.spec, widget.work.spec)) {
      _seed();
    }
  }

  /// Starts the controls where the server said the job starts.
  void _seed() {
    final Map<String, dynamic> spec = widget.work.spec;

    _angle = asDouble(spec['start']);
    _levels = List<double>.filled(_targets.length, 50);
    _order.clear();
    _picked.clear();
    _joins = List<int>.filled(_left.length, -1);
    _pendingStrand = -1;
    _refused = false;
    _sent = '';
  }

  /// Whether two dealt puzzles are the same one.
  ///
  /// Compared by value rather than by identity because every frame brings a
  /// freshly decoded map: identity would say "new puzzle" ten times a second
  /// and reset the player's dial under their thumb.
  bool _sameSpec(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a.toString() == b.toString();

  // -- the dealt puzzle, read out of `spec` --------------------------------

  List<double> get _targets => <double>[
        for (final Object? value in asList(widget.work.spec['targets']))
          asDouble(value),
      ];

  double get _bearing => asDouble(widget.work.spec['target']);
  double get _tolerance => asDouble(widget.work.spec['tolerance'], 7);

  List<int> get _labels => <int>[
        for (final Object? value in asList(widget.work.spec['labels'])) asInt(value),
      ];

  List<int> get _symbols => <int>[
        for (final Object? value in asList(widget.work.spec['symbols'])) asInt(value),
      ];

  int get _wanted => asInt(widget.work.spec['target']);

  List<int> get _left => <int>[
        for (final Object? value in asList(widget.work.spec['left'])) asInt(value),
      ];

  List<int> get _right => <int>[
        for (final Object? value in asList(widget.work.spec['right'])) asInt(value),
      ];

  // -- the answer ----------------------------------------------------------

  /// What would be sent right now, in the shape the server checks.
  List<num> get _answer => switch (widget.station.kind) {
        SpaceTaskKind.align => <num>[_angle.roundToDouble()],
        SpaceTaskKind.sliders => <num>[..._levels.map((double v) => v.roundToDouble())],
        SpaceTaskKind.sequence => <num>[..._order],
        SpaceTaskKind.match => <num>[..._picked],
        SpaceTaskKind.rewire => <num>[..._joins],
      };

  /// Whether the controls are in a state worth sending at all.
  ///
  /// A shape check, never a correctness one. Deciding here whether the answer
  /// is *right* would put the judgement on the client, which is the one thing
  /// this panel must not do — so a wrong-but-complete answer is offered to the
  /// server and refused by it.
  bool get _complete => switch (widget.station.kind) {
        SpaceTaskKind.align => true,
        SpaceTaskKind.sliders => _levels.isNotEmpty,
        SpaceTaskKind.sequence => _order.length == _labels.length,
        SpaceTaskKind.match => _picked.isNotEmpty,
        SpaceTaskKind.rewire =>
          _joins.isNotEmpty && !_joins.contains(-1),
      };

  void _submit() {
    if (!widget.work.ready || !_complete) return;

    final List<num> answer = _answer;
    final String signature = answer.toString();
    if (signature == _sent) {
      // The same answer the server has already refused. Sending it again would
      // only produce the same refusal.
      setState(() => _refused = true);
      return;
    }

    _sent = signature;
    _refused = false;
    widget.onSubmit(answer);
  }

  /// Marks the controls as touched, which clears a previous refusal.
  void _touched(VoidCallback change) {
    setState(() {
      change();
      _refused = false;
      _sent = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    // Sized off the shortest side so a 20:9 phone and a tablet get the same
    // panel at two scales rather than two layouts.
    final double width = math.min(metrics.size.width * 0.72, 520 * metrics.scale);
    final double maxHeight = metrics.size.height * 0.86;

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: Container(
          margin: EdgeInsets.all(metrics.gutter),
          padding: EdgeInsets.all(metrics.gutter),
          decoration: BoxDecoration(
            color: skin.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: _refused ? skin.danger : skin.edge,
              width: AppSpacing.border,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: skin.glow.withValues(alpha: 0.18),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(
                station: widget.station,
                refused: _refused,
                onAbort: widget.onAbort,
              ),
              SizedBox(height: metrics.gutter * 0.8),

              Flexible(
                child: SingleChildScrollView(
                  child: _job(skin, metrics),
                ),
              ),

              SizedBox(height: metrics.gutter * 0.8),
              _Accept(
                ready: widget.work.ready,
                readyInMs: widget.work.readyInMs,
                complete: _complete,
                onPressed: _submit,
              ),

              if (_refused) ...<Widget>[
                SizedBox(height: metrics.gutter * 0.4),
                Text(
                  'Not accepted. Check the panel and try again.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: skin.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _job(GameSkin skin, GameMetrics metrics) {
    return switch (widget.station.kind) {
      SpaceTaskKind.align => _AlignJob(
          angle: _angle,
          bearing: _bearing,
          tolerance: _tolerance,
          scale: metrics.scale,
          onChanged: (double value) => _touched(() => _angle = value),
        ),
      SpaceTaskKind.sliders => _SlidersJob(
          levels: _levels,
          targets: _targets,
          tolerance: _tolerance,
          onChanged: (int index, double value) =>
              _touched(() => _levels[index] = value),
        ),
      SpaceTaskKind.sequence => _SequenceJob(
          labels: _labels,
          order: _order,
          scale: metrics.scale,
          onTap: (int index) => _touched(() {
            if (_order.contains(index)) {
              // Touching a node already in the route starts the route again,
              // which is kinder than refusing the tap and leaving the player
              // to work out why nothing happened.
              _order.clear();
              return;
            }
            _order.add(index);
          }),
        ),
      SpaceTaskKind.match => _MatchJob(
          symbols: _symbols,
          wanted: _wanted,
          picked: _picked,
          scale: metrics.scale,
          onTap: (int index) => _touched(() {
            if (!_picked.remove(index)) _picked.add(index);
          }),
        ),
      SpaceTaskKind.rewire => _RewireJob(
          left: _left,
          right: _right,
          joins: _joins,
          pending: _pendingStrand,
          scale: metrics.scale,
          onLeft: (int index) => _touched(() {
            _pendingStrand = _pendingStrand == index ? -1 : index;
          }),
          onRight: (int index) => _touched(() {
            if (_pendingStrand < 0) return;
            // One right-hand terminal takes one strand, so joining a terminal
            // that is already taken moves the join rather than doubling it.
            for (int i = 0; i < _joins.length; i++) {
              if (_joins[i] == index) _joins[i] = -1;
            }
            _joins[_pendingStrand] = index;
            _pendingStrand = -1;
          }),
        ),
    };
  }
}

/// The panel's title bar: what this console is, and the way out of it.
class _Header extends StatelessWidget {
  const _Header({
    required this.station,
    required this.refused,
    required this.onAbort,
  });

  final ShipStation station;
  final bool refused;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Icon(
          switch (station.kind) {
            SpaceTaskKind.align => Icons.explore_outlined,
            SpaceTaskKind.sliders => Icons.tune_rounded,
            SpaceTaskKind.sequence => Icons.account_tree_outlined,
            SpaceTaskKind.match => Icons.science_outlined,
            SpaceTaskKind.rewire => Icons.cable_rounded,
          },
          color: refused ? skin.danger : skin.accent,
          size: 20,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                station.name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelLarge?.copyWith(
                  color: skin.ink,
                  fontFamily: skin.display,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                switch (station.kind) {
                  SpaceTaskKind.align => 'Turn the marker onto the bearing.',
                  SpaceTaskKind.sliders => 'Bring every channel into its band.',
                  SpaceTaskKind.sequence => 'Touch the nodes in order, lowest first.',
                  SpaceTaskKind.match => 'Pick out every matching sample.',
                  SpaceTaskKind.rewire => 'Join each strand to its own colour.',
                },
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: skin.inkMuted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onAbort,
          tooltip: 'Leave the console',
          icon: Icon(Icons.close_rounded, color: skin.inkMuted),
        ),
      ],
    );
  }
}

/// The ACCEPT control, and the time floor it waits out.
class _Accept extends StatelessWidget {
  const _Accept({
    required this.ready,
    required this.readyInMs,
    required this.complete,
    required this.onPressed,
  });

  final bool ready;
  final int readyInMs;
  final bool complete;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;
    final bool enabled = ready && complete;

    final String label = !ready
        ? 'WORKING — ${(readyInMs / 1000).ceil()}s'
        : complete
            ? 'ACCEPT'
            : 'INCOMPLETE';

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? skin.accent : skin.surfaceRaised,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: enabled ? skin.accent : skin.edge),
          ),
          child: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: enabled ? skin.accentInk : skin.inkMuted,
              fontFamily: skin.display,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The five jobs
// ---------------------------------------------------------------------------

/// **Reactor Alignment, Navigation Sync, Satellite Calibration.**
///
/// Drag anywhere on the dial to swing the marker round to the bearing. Judged
/// by how close it lands rather than by an exact match, so the band is drawn:
/// a target a player cannot see is a target they can only find by luck.
class _AlignJob extends StatelessWidget {
  const _AlignJob({
    required this.angle,
    required this.bearing,
    required this.tolerance,
    required this.scale,
    required this.onChanged,
  });

  final double angle;
  final double bearing;
  final double tolerance;
  final double scale;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final double size = 190 * scale;

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: GestureDetector(
          onPanUpdate: (DragUpdateDetails details) => _aim(details.localPosition, size),
          onTapDown: (TapDownDetails details) => _aim(details.localPosition, size),
          child: CustomPaint(
            painter: _AlignPainter(
              angle: angle,
              bearing: bearing,
              tolerance: tolerance,
              skin: skin,
            ),
            size: Size.square(size),
          ),
        ),
      ),
    );
  }

  /// Turns a touch into a bearing, measured clockwise from straight up.
  void _aim(Offset point, double size) {
    final Offset centre = Offset(size / 2, size / 2);
    final Offset delta = point - centre;
    if (delta.distance < 8) return;

    final double radians = math.atan2(delta.dx, -delta.dy);
    final double degrees = (radians * 180 / math.pi + 360) % 360;
    onChanged(degrees);
  }
}

class _AlignPainter extends CustomPainter {
  const _AlignPainter({
    required this.angle,
    required this.bearing,
    required this.tolerance,
    required this.skin,
  });

  final double angle;
  final double bearing;
  final double tolerance;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 6;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = skin.edge,
    );

    // The band that counts as lined up, drawn so the job is a thing of skill
    // rather than of guessing.
    final double sweep = tolerance * 2 * math.pi / 180;
    final double start = (bearing - tolerance) * math.pi / 180 - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = skin.success.withValues(alpha: 0.55),
    );

    // Graduations, so the dial reads as an instrument.
    for (int tick = 0; tick < 36; tick++) {
      final double radians = tick * 10 * math.pi / 180 - math.pi / 2;
      final double inner = radius - (tick % 9 == 0 ? 12 : 6);
      canvas.drawLine(
        centre + Offset(math.cos(radians) * inner, math.sin(radians) * inner),
        centre + Offset(math.cos(radians) * radius, math.sin(radians) * radius),
        Paint()
          ..strokeWidth = tick % 9 == 0 ? 2 : 1
          ..color = skin.inkMuted.withValues(alpha: 0.5),
      );
    }

    // The marker the player is turning.
    final double radians = angle * math.pi / 180 - math.pi / 2;
    final Offset tip = centre + Offset(math.cos(radians) * (radius - 14), math.sin(radians) * (radius - 14));
    final bool onTarget = _gap(angle, bearing) <= tolerance;

    canvas.drawLine(
      centre,
      tip,
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = onTarget ? skin.success : skin.accent,
    );
    canvas.drawCircle(tip, 7, Paint()..color = onTarget ? skin.success : skin.accent);
    canvas.drawCircle(centre, 5, Paint()..color = skin.inkMuted);
  }

  /// The short way round, so 359 and 1 are two degrees apart.
  double _gap(double a, double b) {
    final double raw = ((a - b) % 360).abs();
    return math.min(raw, 360 - raw);
  }

  @override
  bool shouldRepaint(_AlignPainter old) =>
      old.angle != angle || old.bearing != bearing || old.tolerance != tolerance;
}

/// **Oxygen Calibration, Engine Cooling.**
///
/// Four channels, each with a band to land in. All four at once, so the job
/// cannot be done without reading the whole panel.
class _SlidersJob extends StatelessWidget {
  const _SlidersJob({
    required this.levels,
    required this.targets,
    required this.tolerance,
    required this.onChanged,
  });

  final List<double> levels;
  final List<double> targets;
  final double tolerance;
  final void Function(int, double) onChanged;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int index = 0; index < levels.length; index++)
          Builder(
            builder: (BuildContext context) {
              final double target = index < targets.length ? targets[index] : 50;
              final bool inBand = (levels[index] - target).abs() <= tolerance;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 26,
                      child: Text(
                        'C${index + 1}',
                        style: text.labelSmall?.copyWith(
                          color: inBand ? skin.success : skin.inkMuted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            // The band, behind the track, so the player can see
                            // where they are aiming.
                            LayoutBuilder(
                              builder: (BuildContext context, BoxConstraints box) {
                                final double span = box.maxWidth;
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: span * ((target - tolerance).clamp(0, 100)) / 100,
                                    ),
                                    child: Container(
                                      width: math.max(6, span * (tolerance * 2) / 100),
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: skin.success.withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: inBand ? skin.success : skin.accent,
                                inactiveTrackColor: skin.edge,
                                thumbColor: inBand ? skin.success : skin.accent,
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: levels[index].clamp(0, 100),
                                max: 100,
                                onChanged: (double value) => onChanged(index, value),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// **Power Routing, Auxiliary Power Routing.**
///
/// Six nodes scattered with their labels shuffled; touch them lowest first.
/// The scatter is what makes it a job rather than a row to swipe along.
class _SequenceJob extends StatelessWidget {
  const _SequenceJob({
    required this.labels,
    required this.order,
    required this.scale,
    required this.onTap,
  });

  final List<int> labels;
  final List<int> order;
  final double scale;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10 * scale,
      runSpacing: 10 * scale,
      children: <Widget>[
        for (int index = 0; index < labels.length; index++)
          Builder(
            builder: (BuildContext context) {
              final int position = order.indexOf(index);
              final bool routed = position >= 0;

              return Semantics(
                button: true,
                label: 'Node ${labels[index]}',
                selected: routed,
                child: GestureDetector(
                  onTap: () => onTap(index),
                  child: Container(
                    width: 54 * scale,
                    height: 54 * scale,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: routed ? skin.accent : skin.surfaceRaised,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: routed ? skin.accent : skin.edge,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${labels[index]}',
                          style: text.titleMedium?.copyWith(
                            color: routed ? skin.accentInk : skin.ink,
                            fontFamily: skin.display,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (routed)
                          Text(
                            '#${position + 1}',
                            style: text.labelSmall?.copyWith(
                              color: skin.accentInk.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// **Sample Analysis, Cargo Sorting, Medical Scanner.**
///
/// A tray of samples and a called type. Pick out every one of it — the count
/// is not given, so the whole tray has to be read rather than scanned until a
/// number is reached.
class _MatchJob extends StatelessWidget {
  const _MatchJob({
    required this.symbols,
    required this.wanted,
    required this.picked,
    required this.scale,
    required this.onTap,
  });

  final List<int> symbols;
  final int wanted;
  final Set<int> picked;
  final double scale;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'FIND',
              style: text.labelSmall?.copyWith(
                color: skin.inkMuted,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _Sample(symbol: wanted, size: 34 * scale, selected: false, dimmed: false),
          ],
        ),
        SizedBox(height: 10 * scale),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8 * scale,
          runSpacing: 8 * scale,
          children: <Widget>[
            for (int index = 0; index < symbols.length; index++)
              Semantics(
                button: true,
                selected: picked.contains(index),
                label: 'Sample ${index + 1}',
                child: GestureDetector(
                  onTap: () => onTap(index),
                  child: _Sample(
                    symbol: symbols[index],
                    size: 48 * scale,
                    selected: picked.contains(index),
                    dimmed: false,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One sample in the tray.
///
/// Shape *and* colour, never colour alone: a tray a colour-blind player cannot
/// read is a job they cannot do.
class _Sample extends StatelessWidget {
  const _Sample({
    required this.symbol,
    required this.size,
    required this.selected,
    required this.dimmed,
  });

  final int symbol;
  final double size;
  final bool selected;
  final bool dimmed;

  static const List<Color> _tones = <Color>[
    Color(0xFF6CD4FF),
    Color(0xFFFFC857),
    Color(0xFF9B8CFF),
    Color(0xFF63E6A4),
    Color(0xFFFF8FA3),
  ];

  static const List<IconData> _glyphs = <IconData>[
    Icons.hexagon_outlined,
    Icons.change_history_rounded,
    Icons.circle_outlined,
    Icons.square_rounded,
    Icons.star_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final Color tone = _tones[symbol % _tones.length];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: selected ? 0.32 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(
          color: selected ? tone : skin.edge,
          width: selected ? 2.5 : 1.2,
        ),
      ),
      child: Icon(
        _glyphs[symbol % _glyphs.length],
        color: dimmed ? skin.inkMuted : tone,
        size: size * 0.5,
      ),
    );
  }
}

/// **Signal Repair, Relay Repair.**
///
/// Two columns carrying the same colours in different orders. Touch a strand
/// on the left, then the terminal on the right that matches it.
class _RewireJob extends StatelessWidget {
  const _RewireJob({
    required this.left,
    required this.right,
    required this.joins,
    required this.pending,
    required this.scale,
    required this.onLeft,
    required this.onRight,
  });

  final List<int> left;
  final List<int> right;
  final List<int> joins;
  final int pending;
  final double scale;
  final ValueChanged<int> onLeft;
  final ValueChanged<int> onRight;

  static const List<Color> _tones = <Color>[
    Color(0xFF6CD4FF),
    Color(0xFFFFC857),
    Color(0xFF9B8CFF),
    Color(0xFF63E6A4),
    Color(0xFFFF8FA3),
  ];

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int index = 0; index < left.length; index++)
              _Terminal(
                tone: _tones[left[index] % _tones.length],
                scale: scale,
                active: pending == index,
                joined: joins.length > index && joins[index] >= 0,
                label: joins.length > index && joins[index] >= 0
                    ? '${joins[index] + 1}'
                    : null,
                onTap: () => onLeft(index),
              ),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                pending >= 0 ? 'PICK A TERMINAL' : 'PICK A STRAND',
                style: text.labelSmall?.copyWith(
                  color: pending >= 0 ? skin.accent : skin.inkMuted,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.swap_horiz_rounded, color: skin.inkMuted, size: 22 * scale),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int index = 0; index < right.length; index++)
              _Terminal(
                tone: _tones[right[index] % _tones.length],
                scale: scale,
                active: false,
                joined: joins.contains(index),
                label: '${index + 1}',
                onTap: () => onRight(index),
              ),
          ],
        ),
      ],
    );
  }
}

/// One end of a strand, on either side of the panel.
class _Terminal extends StatelessWidget {
  const _Terminal({
    required this.tone,
    required this.scale,
    required this.active,
    required this.joined,
    required this.label,
    required this.onTap,
  });

  final Color tone;
  final double scale;
  final bool active;
  final bool joined;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          // Kept above the 44-unit touch minimum even at the smallest scale.
          width: 62 * scale,
          height: 44 * scale,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: joined ? 0.3 : 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? skin.ink : (joined ? tone : skin.edge),
              width: active ? 2.5 : 1.4,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 14 * scale,
                height: 14 * scale,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
              if (label != null) ...<Widget>[
                const SizedBox(width: 4),
                Text(
                  label!,
                  style: text.labelSmall?.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
