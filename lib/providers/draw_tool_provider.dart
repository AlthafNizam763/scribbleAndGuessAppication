import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/models/enums.dart';

/// The drawer's local pen settings.
///
/// Purely a client concern: the server only ever receives the resulting
/// strokes, so nothing here needs to round-trip. What the server *does* decide
/// is whether this device may draw at all — see `drawingService.assertCanDraw`
/// — so none of these settings is a permission.
class DrawToolState extends Equatable {
  const DrawToolState({
    this.tool = DrawTool.pen,
    this.colorValue = defaultInk,
    this.width = defaultWidth,
  });

  /// The default nib colour, matching the first swatch in [penPalette].
  static const int defaultInk = 0xFF1A1A1A;

  /// Ink colours offered to the drawer.
  ///
  /// Stored as ARGB ints rather than theme colours so a stroke drawn in light
  /// mode arrives the same colour on a device in dark mode.
  static const List<int> penPalette = <int>[
    defaultInk, // ink
    0xFF6B7280, // graphite
    0xFFD64545, // red
    0xFFE8873A, // orange
    0xFFE3B92F, // yellow
    0xFF3F9A50, // green
    0xFF3B7DD8, // blue
    0xFF7C5BD9, // purple
    0xFFD4529E, // pink
    0xFF8B5A2B, // brown
    0xFFFFFFFF, // white, which is also how you fill back to paper
  ];

  /// Nib sizes, as a stroke width in canvas units.
  static const List<double> widths = <double>[2, 4, 8, 16, 28];

  static const double defaultWidth = 4;

  /// The narrowest and widest a custom size may be.
  ///
  /// Matches the server's own clamp in `sanitizeStroke`, so the slider cannot
  /// ask for a width that would be silently altered on arrival.
  static const double minWidth = 1;
  static const double maxWidth = 60;

  /// The eraser is wider than the pen by default; a hairline eraser is
  /// frustrating to use under a fingertip.
  static const double defaultEraserWidth = 16;

  /// The marker is wider still — a thin marker is just a pen.
  static const double defaultMarkerWidth = 20;

  final DrawTool tool;
  final int colorValue;
  final double width;

  bool get isErasing => tool == DrawTool.eraser;

  /// Whether the palette applies to the current tool.
  bool get colorApplies => tool.usesColor;

  DrawToolState copyWith({
    DrawTool? tool,
    int? colorValue,
    double? width,
  }) =>
      DrawToolState(
        tool: tool ?? this.tool,
        colorValue: colorValue ?? this.colorValue,
        width: width ?? this.width,
      );

  @override
  List<Object?> get props => <Object?>[tool, colorValue, width];
}

class DrawToolNotifier extends Notifier<DrawToolState> {
  /// The width to restore per tool family.
  ///
  /// Kept separately because the sensible size for each is different by an
  /// order of magnitude: switching to the eraser and back should not leave the
  /// pen 16 units wide, and switching to the marker and back should not leave
  /// it 20. One remembered width would make every tool change a size change
  /// too.
  final Map<DrawTool, double> _rememberedWidths = <DrawTool, double>{};

  @override
  DrawToolState build() => const DrawToolState();

  /// The width this tool should start at when it is first picked up.
  static double _defaultWidthFor(DrawTool tool) => switch (tool) {
        DrawTool.eraser => DrawToolState.defaultEraserWidth,
        DrawTool.marker => DrawToolState.defaultMarkerWidth,
        _ => DrawToolState.defaultWidth,
      };

  void selectTool(DrawTool tool) {
    if (tool == state.tool) {
      return;
    }

    // Remember where the outgoing tool was left, so coming back to it feels
    // like picking up the same pen rather than a new one.
    if (state.tool.usesWidth) {
      _rememberedWidths[state.tool] = state.width;
    }

    state = state.copyWith(
      tool: tool,
      width: _rememberedWidths[tool] ?? _defaultWidthFor(tool),
    );
  }

  /// Picking a colour puts the eraser down, which is what a drawer reaching
  /// for a colour almost always means.
  ///
  /// It does *not* disturb any other tool: choosing red while the rectangle is
  /// selected should draw a red rectangle, not switch back to the pen.
  void selectColor(int colorValue) {
    if (state.tool == DrawTool.eraser) {
      selectTool(DrawTool.pen);
    }
    state = state.copyWith(colorValue: colorValue);
  }

  void selectWidth(double width) {
    final double clamped =
        width.clamp(DrawToolState.minWidth, DrawToolState.maxWidth).toDouble();

    if (state.tool.usesWidth) {
      _rememberedWidths[state.tool] = clamped;
    }
    state = state.copyWith(width: clamped);
  }

  /// Back to a black medium pen, for the start of a turn.
  void reset() {
    _rememberedWidths.clear();
    state = const DrawToolState();
  }
}

final NotifierProvider<DrawToolNotifier, DrawToolState> drawToolProvider =
    NotifierProvider<DrawToolNotifier, DrawToolState>(DrawToolNotifier.new);
