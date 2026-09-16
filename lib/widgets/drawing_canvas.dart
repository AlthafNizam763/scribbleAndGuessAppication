import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:scribble_guess/core/utils/geometry.dart';
import 'package:scribble_guess/models/drawing_board.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The shared drawing surface.
///
/// Coordinates travel over the wire normalised to 0..1 (see [Geometry]), so a
/// stroke drawn on a phone lands in the same place on a tablet. This widget is
/// the only place that converts between that space and pixels.
///
/// ## How pressure is captured without disturbing the gestures
///
/// [DragUpdateDetails] carries no pressure, so the raw value has to come from
/// a [Listener]. It is layered *above* the [GestureDetector] rather than
/// replacing it: a `Listener` only observes — it does not enter the gesture
/// arena — so every existing pan behaviour is untouched and the pointer's
/// pressure is simply recorded as it passes. Replacing the detector outright
/// would have meant re-deriving drag semantics by hand and competing with any
/// scrollable ancestor for the same events.
class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    required this.board,
    this.pending,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.interactive = false,
    super.key,
  });

  /// Everything committed so far.
  final DrawingBoard board;

  /// The stroke currently under the finger, drawn on top of [board].
  ///
  /// Held separately so the drawer sees their own line with zero latency
  /// rather than waiting for it to round-trip through the server. For a shape
  /// this is also the *only* place it exists until the drag is released.
  final Stroke? pending;

  final ValueChanged<StrokePoint>? onPanStart;
  final ValueChanged<StrokePoint>? onPanUpdate;
  final VoidCallback? onPanEnd;

  /// Whether this device may draw. Guessers get the same canvas, inert.
  final bool interactive;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  /// Settled strokes, rasterised once and reused every frame.
  ///
  /// Held by the state rather than by the painter because a painter is a
  /// throwaway — Flutter builds a new one on every rebuild — and a cache that
  /// is rebuilt with its owner caches nothing.
  final _BoardCache _cache = _BoardCache();

  /// The most recent pressure the pointer reported, or null on a device that
  /// does not report one.
  ///
  /// Read by the pan callbacks a beat later. That ordering is safe because a
  /// `Listener`'s pointer callbacks fire before the gesture recogniser's for
  /// the same event.
  double? _pressure;

  /// Records pressure, when the device actually measures it.
  ///
  /// `pressureMin == pressureMax` is how Flutter reports "this device has no
  /// sensor" — every event then carries the same value, which would be a
  /// constant masquerading as data. Null is the honest answer there, and it is
  /// also what keeps the point two elements wide on the wire.
  void _recordPressure(PointerEvent event) {
    if (event.pressureMax <= event.pressureMin) {
      _pressure = null;
      return;
    }

    final double span = event.pressureMax - event.pressureMin;
    _pressure = ((event.pressure - event.pressureMin) / span).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    // A `ui.Picture` holds native memory the garbage collector does not
    // account for, so leaving one behind when the game screen closes is a leak
    // Dart's own tooling would not show.
    _cache.dispose();
    super.dispose();
  }

  StrokePoint _pointFrom(Offset local, Size size, {required bool withPressure}) {
    final StrokePoint normalized = Geometry.normalize(local, size);
    if (!withPressure || _pressure == null) return normalized;
    return normalized.copyWith(pressure: _pressure);
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);

        Widget surface = ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: CustomPaint(
            size: size,
            isComplex: true,
            willChange: widget.interactive,
            painter: _BoardPainter(
              strokes: widget.board.strokes,
              pending: widget.pending,
              background: colors.canvasWhite,
              cache: _cache,
            ),
            child: const SizedBox.expand(),
          ),
        );

        if (widget.interactive) {
          // Whether the point being captured should carry pressure at all is
          // decided by the tool, which the caller knows and this widget does
          // not — so it is inferred from the pending stroke, the one thing
          // here that names the tool in use.
          bool wantsPressure() =>
              widget.pending?.tool.usesPressure ?? true;

          surface = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (DragStartDetails details) => widget.onPanStart?.call(
              // On the first point the pending stroke does not exist yet, so
              // pressure is always captured and the caller drops it if the
              // tool has no use for it.
              _pointFrom(details.localPosition, size, withPressure: true),
            ),
            onPanUpdate: (DragUpdateDetails details) => widget.onPanUpdate?.call(
              _pointFrom(
                details.localPosition,
                size,
                withPressure: wantsPressure(),
              ),
            ),
            onPanEnd: (DragEndDetails details) => widget.onPanEnd?.call(),
            child: surface,
          );

          surface = Listener(
            onPointerDown: _recordPressure,
            onPointerMove: _recordPressure,
            child: surface,
          );
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: colors.ink, width: AppSpacing.border),
          ),
          child: surface,
        );
      },
    );
  }
}

/// Settled strokes, kept as a recorded [ui.Picture] between frames.
///
/// ## The problem this solves
///
/// The painter used to walk every committed stroke on every paint, rebuilding
/// each one's [Path] from scratch — denormalising every point — sixty times a
/// second. That is fine at twenty strokes and hopeless at a thousand, which is
/// squarely inside what a real turn produces. Worse, [DrawingBoard] is
/// immutable, so every inbound `s:draw:append` hands the widget a brand new
/// `List`; `identical` was therefore always false and a full repaint happened
/// on every batch, about seventeen times a second, whether or not the visible
/// result had changed.
///
/// ## How the cache stays correct
///
/// Only *settled* strokes are baked. The last stroke is always drawn live,
/// because it is the one an inbound batch is still growing — baking it would
/// freeze it at whatever length it had when the picture was recorded, and the
/// rest of the line would never appear.
///
/// The bake is incremental: a new picture is recorded by replaying the old one
/// and drawing only the strokes added since. Re-recording everything on each
/// new stroke would be O(n) per stroke and O(n²) across a turn, which merely
/// moves the stall from every frame to every stroke.
///
/// Anything that could invalidate the prefix — a resize, a theme change, an
/// undo, a clear, a redo that reorders — is detected and forces a full
/// rebuild. Detection is O(1): the stroke count going backwards, or the last
/// baked stroke no longer being the object at that index. The board is an
/// append-only log in the ordinary case, so the cheap check is also the
/// accurate one, and the expensive path is correct whenever it is not.
class _BoardCache {
  ui.Picture? _picture;
  int _bakedCount = 0;
  Stroke? _lastBaked;
  Size _size = Size.zero;
  Color _background = const Color(0x00000000);

  /// Brings the cache up to date and returns the picture to draw, if any.
  ///
  /// [settled] is how many of [strokes] may be baked — always all but the
  /// last, so the growing stroke stays live.
  ui.Picture? update({
    required List<Stroke> strokes,
    required int settled,
    required Size size,
    required Color background,
    required void Function(Canvas canvas, Size size, Stroke stroke) paintStroke,
  }) {
    final bool geometryChanged = size != _size || background != _background;

    // The prefix is trustworthy only when it has not shrunk and the stroke the
    // bake ended on is still the same object at the same index.
    final bool prefixIntact = _bakedCount == 0 ||
        (settled >= _bakedCount &&
            _bakedCount <= strokes.length &&
            identical(strokes[_bakedCount - 1], _lastBaked));

    final int from = (geometryChanged || !prefixIntact) ? 0 : _bakedCount;

    if (from == 0 && settled == 0) {
      _release();
      _size = size;
      _background = background;
      return null;
    }

    if (from == settled && !geometryChanged && prefixIntact) {
      // Nothing new has settled since the last bake.
      return _picture;
    }

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final ui.Picture? previous = _picture;
    if (from > 0 && previous != null) {
      canvas.drawPicture(previous);
    }

    for (int i = from; i < settled; i++) {
      paintStroke(canvas, size, strokes[i]);
    }

    final ui.Picture next = recorder.endRecording();

    // The old picture is only safe to release once the new one — which was
    // recorded *from* it — has been captured.
    previous?.dispose();

    _picture = next;
    _bakedCount = settled;
    _lastBaked = settled > 0 ? strokes[settled - 1] : null;
    _size = size;
    _background = background;

    return next;
  }

  void _release() {
    _picture?.dispose();
    _picture = null;
    _bakedCount = 0;
    _lastBaked = null;
  }

  /// Frees the recorded picture. Called when the widget goes away.
  void dispose() => _release();
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.strokes,
    required this.pending,
    required this.background,
    required this.cache,
  });

  final List<Stroke> strokes;
  final Stroke? pending;
  final Color background;
  final _BoardCache cache;

  /// The nominal board width the stored stroke widths are expressed against.
  static const double _referenceEdge = 400;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    // Everything but the last stroke can be replayed from the cache. The last
    // one is drawn live because it is the one an inbound batch may still be
    // extending — see [_BoardCache].
    final int settled = strokes.isEmpty ? 0 : strokes.length - 1;

    final ui.Picture? baked = cache.update(
      strokes: strokes,
      settled: settled,
      size: size,
      background: background,
      paintStroke: _paintStroke,
    );

    if (baked != null) canvas.drawPicture(baked);

    for (int i = settled; i < strokes.length; i++) {
      _paintStroke(canvas, size, strokes[i]);
    }

    if (pending != null) {
      _paintStroke(canvas, size, pending!);
    }
  }

  /// The colour a stroke actually lays down.
  ///
  /// The eraser is a stroke in the page colour rather than a real cut-out:
  /// strokes are an append-only log, so painting over is what keeps every
  /// client's replay of that log identical.
  ///
  /// The translucent tools get their alpha here rather than in the stored
  /// colour, so the same swatch means the same colour whichever tool picked it
  /// up — and so a marker stroke replayed by an older client still renders as
  /// a solid line of the right hue rather than as nothing.
  Color _colorFor(Stroke stroke) {
    if (stroke.tool == DrawTool.eraser) return background;

    final Color base = Color(stroke.colorValue);
    return switch (stroke.tool) {
      DrawTool.marker => base.withValues(alpha: 0.45),
      DrawTool.pencil => base.withValues(alpha: 0.75),
      _ => base,
    };
  }

  void _paintStroke(Canvas canvas, Size size, Stroke stroke) {
    if (stroke.points.isEmpty) {
      return;
    }

    final Color color = _colorFor(stroke);

    // A fill covers everything, so it needs neither points nor width.
    if (stroke.tool == DrawTool.fill) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
      return;
    }

    // Width is stored in canvas units against a nominal board, so a line keeps
    // its relative weight at any screen size.
    final double scale = size.shortestSide / _referenceEdge;
    final double strokeWidth = stroke.width * scale;

    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      // A marker is flat-nibbed; everything else is round.
      ..strokeCap =
          stroke.tool == DrawTool.marker ? StrokeCap.square : StrokeCap.round
      ..strokeJoin =
          stroke.tool == DrawTool.marker ? StrokeJoin.miter : StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (stroke.tool.isShape) {
      _paintShape(canvas, size, stroke, paint);
      return;
    }

    if (stroke.points.length == 1) {
      // A tap with no drag still deserves a dot.
      canvas.drawCircle(
        Geometry.denormalize(stroke.points.first, size),
        strokeWidth / 2,
        Paint()..color = color,
      );
      return;
    }

    if (stroke.tool == DrawTool.brush) {
      _paintPressureStroke(canvas, size, stroke, color, strokeWidth);
      return;
    }

    canvas.drawPath(_smoothPath(stroke.points, size), paint);
  }

  /// A line, rectangle or ellipse from the drag's two corners.
  ///
  /// A shape mid-drag can legitimately have one point — the drag has started
  /// but not moved — in which case there is nothing to draw yet.
  void _paintShape(Canvas canvas, Size size, Stroke stroke, Paint paint) {
    if (stroke.points.length < 2) return;

    final Offset start = Geometry.denormalize(stroke.points.first, size);
    final Offset end = Geometry.denormalize(stroke.points[1], size);

    switch (stroke.tool) {
      case DrawTool.line:
        canvas.drawLine(start, end, paint);
      case DrawTool.rectangle:
        canvas.drawRect(Rect.fromPoints(start, end), paint);
      case DrawTool.circle:
        canvas.drawOval(Rect.fromPoints(start, end), paint);
      // Not reachable: `isShape` gates this method.
      default:
        break;
    }
  }

  /// A brush stroke, whose width follows the pressure recorded per point.
  ///
  /// Drawn as one short segment per pair rather than as a single path, because
  /// a path carries one width for its whole length. That is more draw calls —
  /// which is why it is confined to the one tool that needs it, and why every
  /// other tool still takes the single-path route above.
  void _paintPressureStroke(
    Canvas canvas,
    Size size,
    Stroke stroke,
    Color color,
    double nominalWidth,
  ) {
    final Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    for (int i = 1; i < stroke.points.length; i++) {
      final StrokePoint from = stroke.points[i - 1];
      final StrokePoint to = stroke.points[i];

      // Averaged across the segment so the width steps smoothly rather than
      // jumping at every sample.
      final double pressure =
          (from.effectivePressure + to.effectivePressure) / 2;

      // Mapped to 0.4x..1.6x of the nominal width. A brush that could taper to
      // nothing would let a shaky hand erase its own line.
      paint.strokeWidth = nominalWidth * (0.4 + pressure * 1.2);

      canvas.drawLine(
        Geometry.denormalize(from, size),
        Geometry.denormalize(to, size),
        paint,
      );
    }
  }

  /// Quadratic segments through the midpoints, which is what makes a dragged
  /// finger look like ink rather than a chain of straight hops.
  Path _smoothPath(List<StrokePoint> points, Size size) {
    final Offset first = Geometry.denormalize(points.first, size);
    final Path path = Path()..moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final Offset current = Geometry.denormalize(points[i], size);
      final Offset previous = Geometry.denormalize(points[i - 1], size);
      final Offset midpoint = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, midpoint.dx, midpoint.dy);
    }

    final Offset last = Geometry.denormalize(points.last, size);
    path.lineTo(last.dx, last.dy);

    return path;
  }

  /// Whether anything visible actually moved.
  ///
  /// The `identical` check is still here and still almost always true — the
  /// board is immutable, so a new list arrives with every batch. What has
  /// changed is the cost of being wrong: a repaint now replays one cached
  /// picture and draws a single live stroke, instead of rebuilding every
  /// [Path] on the board. Tightening this further would mean comparing stroke
  /// contents, which is the O(n) work the cache exists to avoid.
  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.pending != pending ||
      !identical(oldDelegate.strokes, strokes) ||
      oldDelegate.strokes.length != strokes.length;
}
