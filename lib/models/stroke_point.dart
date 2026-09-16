import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// A single sampled point of a stroke, normalized to the `0..1` canvas box.
///
/// ## Pressure is optional, and deliberately so
///
/// Points are the highest-frequency payload in the game — a batch every 60ms
/// while a finger is down — so a third number on every one of them is a 50%
/// increase on the thing sent most often. Only [DrawTool.brush] varies its
/// width with pressure, so only brush strokes carry it; everything else
/// serialises the two-element form it always did.
///
/// That also keeps the change compatible in both directions: an older client
/// sends two elements and parses fine here, and this client's third element is
/// ignored by an older server.
class StrokePoint extends Equatable {
  /// Creates a normalized point.
  const StrokePoint({this.x = 0, this.y = 0, this.pressure});

  /// Builds a point from an object shaped `{'x': .., 'y': ..}`.
  factory StrokePoint.fromJson(Map<String, dynamic> json) => StrokePoint(
        x: asDouble(json['x']),
        y: asDouble(json['y']),
        pressure:
            json['pressure'] == null ? null : asDouble(json['pressure']),
      );

  /// Builds a point from the compact list wire format, `[x, y]` or
  /// `[x, y, pressure]`. Also accepts the object form so malformed payloads
  /// still parse.
  factory StrokePoint.fromJsonList(dynamic value) {
    if (value is Map) return StrokePoint.fromJson(asMap(value));
    final List<dynamic> parts = asList(value);
    return StrokePoint(
      x: parts.isNotEmpty ? asDouble(parts[0]) : 0,
      y: parts.length > 1 ? asDouble(parts[1]) : 0,
      pressure: parts.length > 2 ? asDouble(parts[2]) : null,
    );
  }

  /// The pressure a device with no sensor reports, and the value a renderer
  /// falls back to. Chosen so an unpressured brush stroke is its nominal width
  /// rather than a hairline or a slab.
  static const double neutralPressure = 0.5;

  /// Horizontal position, `0` at the left edge and `1` at the right edge.
  final double x;

  /// Vertical position, `0` at the top edge and `1` at the bottom edge.
  final double y;

  /// How hard the pointer was pressed, `0..1`, or null when unreported.
  final double? pressure;

  /// The pressure to draw with, falling back to [neutralPressure].
  double get effectivePressure => pressure ?? neutralPressure;

  /// Serializes this point to the compact wire format.
  ///
  /// Two elements unless a pressure was actually captured — see the note on
  /// the class for why the third is not always sent.
  List<double> toJsonList() =>
      pressure == null ? <double>[x, y] : <double>[x, y, pressure!];

  /// Serializes this point to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': x,
        'y': y,
        if (pressure != null) 'pressure': pressure,
      };

  /// Returns a copy with the given fields replaced.
  StrokePoint copyWith({double? x, double? y, double? pressure}) => StrokePoint(
        x: x ?? this.x,
        y: y ?? this.y,
        pressure: pressure ?? this.pressure,
      );

  @override
  List<Object?> get props => <Object?>[x, y, pressure];

  @override
  bool get stringify => true;
}
