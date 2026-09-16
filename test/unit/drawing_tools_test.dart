import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';
import 'package:scribble_guess/providers/draw_tool_provider.dart';

/// The drawing tools: their wire names, their behaviour classes, and the
/// pressure format.
///
/// ## Why the wire names are pinned
///
/// `DrawTool.fromName` falls back to [DrawTool.pen] rather than throwing, which
/// is what keeps a stroke from a newer client renderable — but it also means a
/// name that drifts from the backend's `DRAW_TOOL` fails *silently*. Every
/// rectangle in the room would quietly become a scribble, and nothing would
/// report it. These tests are the thing that would notice.
void main() {
  group('DrawTool wire format', () {
    test('parses every value the backend sends', () {
      const Map<String, DrawTool> wire = <String, DrawTool>{
        'pen': DrawTool.pen,
        'pencil': DrawTool.pencil,
        'marker': DrawTool.marker,
        'brush': DrawTool.brush,
        'eraser': DrawTool.eraser,
        'fill': DrawTool.fill,
        'line': DrawTool.line,
        'rectangle': DrawTool.rectangle,
        'circle': DrawTool.circle,
      };

      wire.forEach((String name, DrawTool expected) {
        expect(DrawTool.fromName(name), expected, reason: name);
      });
    });

    test('round-trips through its own name', () {
      for (final DrawTool tool in DrawTool.values) {
        expect(DrawTool.fromName(tool.name), tool);
      }
    });

    test('falls back to the pen rather than throwing', () {
      expect(DrawTool.fromName(null), DrawTool.pen);
      expect(DrawTool.fromName('airbrush'), DrawTool.pen);
    });

    test('gives every tool a label', () {
      for (final DrawTool tool in DrawTool.values) {
        expect(tool.label, isNotEmpty);
      }
    });
  });

  group('tool behaviour classes', () {
    test('classifies shapes, instants and freehand without overlap', () {
      for (final DrawTool tool in DrawTool.values) {
        final int classes = <bool>[
          tool.isShape,
          tool.isInstant,
          tool.isFreehand,
        ].where((bool value) => value).length;

        // Exactly one, or the game screen's branching would either send a
        // stroke twice or never send it at all.
        expect(classes, 1, reason: tool.name);
      }
    });

    test('treats line, rectangle and circle as two-point shapes', () {
      expect(DrawTool.line.isShape, isTrue);
      expect(DrawTool.rectangle.isShape, isTrue);
      expect(DrawTool.circle.isShape, isTrue);
      expect(DrawTool.pen.isShape, isFalse);
    });

    test('treats only the fill as instant', () {
      expect(DrawTool.fill.isInstant, isTrue);
      for (final DrawTool tool in DrawTool.values) {
        if (tool != DrawTool.fill) expect(tool.isInstant, isFalse);
      }
    });

    /// Pressure costs a third number on the highest-frequency payload in the
    /// game, so exactly one tool pays for it.
    test('asks for pressure on the brush alone', () {
      expect(DrawTool.brush.usesPressure, isTrue);
      for (final DrawTool tool in DrawTool.values) {
        if (tool != DrawTool.brush) expect(tool.usesPressure, isFalse);
      }
    });

    test('excludes the eraser from the colour palette', () {
      expect(DrawTool.eraser.usesColor, isFalse);
      expect(DrawTool.pen.usesColor, isTrue);
    });

    test('excludes the fill from width', () {
      expect(DrawTool.fill.usesWidth, isFalse);
      expect(DrawTool.marker.usesWidth, isTrue);
    });
  });

  group('StrokePoint pressure', () {
    test('serialises two elements when no pressure was captured', () {
      expect(const StrokePoint(x: 0.25, y: 0.5).toJsonList(), <double>[0.25, 0.5]);
    });

    test('serialises three elements when it was', () {
      expect(
        const StrokePoint(x: 0.25, y: 0.5, pressure: 0.8).toJsonList(),
        <double>[0.25, 0.5, 0.8],
      );
    });

    test('parses both wire forms', () {
      final StrokePoint flat = StrokePoint.fromJsonList(const <double>[0.1, 0.2]);
      final StrokePoint pressured =
          StrokePoint.fromJsonList(const <double>[0.1, 0.2, 0.9]);

      expect(flat.pressure, isNull);
      expect(pressured.pressure, 0.9);
    });

    /// A renderer must never have to branch on null: an unpressured point
    /// draws at the nominal width, not at zero.
    test('reports a neutral pressure when none was recorded', () {
      expect(
        const StrokePoint(x: 0, y: 0).effectivePressure,
        StrokePoint.neutralPressure,
      );
      expect(
        const StrokePoint(x: 0, y: 0, pressure: 0.1).effectivePressure,
        0.1,
      );
    });

    test('survives a malformed point', () {
      final StrokePoint point = StrokePoint.fromJsonList('nonsense');
      expect(point.x, 0);
      expect(point.y, 0);
      expect(point.pressure, isNull);
    });
  });

  group('Stroke round trip', () {
    test('carries the tool and pressure through the wire format', () {
      const Stroke stroke = Stroke(
        id: 's-1',
        authorId: 'u-1',
        points: <StrokePoint>[
          StrokePoint(x: 0.1, y: 0.1, pressure: 0.3),
          StrokePoint(x: 0.2, y: 0.2, pressure: 0.7),
        ],
        colorValue: 0xFFD64545,
        width: 12,
        tool: DrawTool.brush,
        timestampMs: 1700000000000,
      );

      final Stroke parsed = Stroke.fromJson(stroke.toJson());

      expect(parsed.tool, DrawTool.brush);
      expect(parsed.points.first.pressure, 0.3);
      expect(parsed.points.last.pressure, 0.7);
      expect(parsed.colorValue, 0xFFD64545);
      expect(parsed.width, 12);
    });

    test('round-trips a shape as its two points', () {
      const Stroke stroke = Stroke(
        id: 's-2',
        authorId: 'u-1',
        points: <StrokePoint>[
          StrokePoint(x: 0.1, y: 0.1),
          StrokePoint(x: 0.9, y: 0.6),
        ],
        tool: DrawTool.rectangle,
      );

      final Stroke parsed = Stroke.fromJson(stroke.toJson());

      expect(parsed.tool, DrawTool.rectangle);
      expect(parsed.points, hasLength(2));
      // No pressure on a shape: it would be two wasted numbers per corner.
      expect(parsed.points.first.pressure, isNull);
    });
  });

  group('DrawToolNotifier', () {
    late ProviderContainer container;
    late DrawToolNotifier notifier;

    /// A real container, because a `Notifier` cannot be driven outside one —
    /// its `state` setter reaches for the element the container owns. Nothing
    /// is overridden: this provider has no dependencies, so the real thing is
    /// also the simplest thing.
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      notifier = container.read(drawToolProvider.notifier);
    });

    test('starts on a black medium pen', () {
      expect(notifier.state.tool, DrawTool.pen);
      expect(notifier.state.colorValue, DrawToolState.defaultInk);
      expect(notifier.state.width, DrawToolState.defaultWidth);
    });

    /// One remembered width would make every tool change a size change too:
    /// the eraser's sensible size is four times the pen's.
    test('remembers a width per tool', () {
      notifier.selectWidth(2);
      notifier.selectTool(DrawTool.eraser);

      expect(notifier.state.width, DrawToolState.defaultEraserWidth);

      notifier.selectWidth(30);
      notifier.selectTool(DrawTool.pen);

      expect(notifier.state.width, 2);

      notifier.selectTool(DrawTool.eraser);
      expect(notifier.state.width, 30);
    });

    test('gives the marker its own default the first time it is picked up', () {
      notifier.selectTool(DrawTool.marker);
      expect(notifier.state.width, DrawToolState.defaultMarkerWidth);
    });

    test('puts the eraser down when a colour is chosen', () {
      notifier.selectTool(DrawTool.eraser);
      notifier.selectColor(0xFFD64545);

      expect(notifier.state.tool, DrawTool.pen);
      expect(notifier.state.colorValue, 0xFFD64545);
    });

    /// Choosing red while the rectangle is selected should draw a red
    /// rectangle — not silently switch back to the pen.
    test('leaves a non-eraser tool alone when a colour is chosen', () {
      notifier.selectTool(DrawTool.rectangle);
      notifier.selectColor(0xFF3B7DD8);

      expect(notifier.state.tool, DrawTool.rectangle);
      expect(notifier.state.colorValue, 0xFF3B7DD8);
    });

    /// The clamp matches the server's own in `sanitizeStroke`, so the slider
    /// cannot ask for a width that would be altered on arrival.
    test('clamps a width to what the server will accept', () {
      notifier.selectWidth(5000);
      expect(notifier.state.width, DrawToolState.maxWidth);

      notifier.selectWidth(-20);
      expect(notifier.state.width, DrawToolState.minWidth);
    });

    test('resets to a black medium pen for a new turn', () {
      notifier.selectTool(DrawTool.marker);
      notifier.selectColor(0xFFD64545);
      notifier.selectWidth(40);

      notifier.reset();

      expect(notifier.state.tool, DrawTool.pen);
      expect(notifier.state.colorValue, DrawToolState.defaultInk);
      expect(notifier.state.width, DrawToolState.defaultWidth);
    });
  });
}
