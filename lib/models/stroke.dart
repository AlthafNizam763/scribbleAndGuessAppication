import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/stroke_point.dart';

/// One continuous mark on the drawing board. Serialized with compact keys
/// because strokes are the highest volume payload on the wire.
class Stroke extends Equatable {
  /// Creates a stroke.
  const Stroke({
    this.id = '',
    this.authorId = '',
    this.points = const <StrokePoint>[],
    this.colorValue = 0xFF1A1A1A,
    this.width = 4,
    this.tool = DrawTool.pen,
    this.timestampMs = 0,
  });

  /// Builds a stroke from the compact wire format.
  factory Stroke.fromJson(Map<String, dynamic> json) => Stroke(
        id: asString(json['id']),
        authorId: asString(json['a']),
        points: <StrokePoint>[
          for (final dynamic raw in asList(json['p']))
            StrokePoint.fromJsonList(raw),
        ],
        colorValue: asInt(json['c'], 0xFF1A1A1A),
        width: asDouble(json['w'], 4),
        tool: DrawTool.fromName(asString(json['t'])),
        timestampMs: asInt(json['ts']),
      );

  /// Client-generated identifier, unique per stroke.
  final String id;

  /// Identifier of the player who drew it.
  final String authorId;

  /// Normalized points in draw order.
  final List<StrokePoint> points;

  /// ARGB colour value of the ink.
  final int colorValue;

  /// Stroke width in logical pixels at the reference canvas size.
  final double width;

  /// Whether the stroke lays down or removes ink.
  final DrawTool tool;

  /// Creation time in milliseconds since epoch, on the server clock.
  final int timestampMs;

  /// Returns a copy of this stroke carrying [newPoints] instead.
  Stroke copyWithPoints(List<StrokePoint> newPoints) =>
      copyWith(points: newPoints);

  /// Serializes this stroke to the compact wire format.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'a': authorId,
        'p': <List<double>>[
          for (final StrokePoint point in points) point.toJsonList(),
        ],
        'c': colorValue,
        'w': width,
        't': tool.name,
        'ts': timestampMs,
      };

  /// Returns a copy with the given fields replaced.
  Stroke copyWith({
    String? id,
    String? authorId,
    List<StrokePoint>? points,
    int? colorValue,
    double? width,
    DrawTool? tool,
    int? timestampMs,
  }) =>
      Stroke(
        id: id ?? this.id,
        authorId: authorId ?? this.authorId,
        points: points ?? this.points,
        colorValue: colorValue ?? this.colorValue,
        width: width ?? this.width,
        tool: tool ?? this.tool,
        timestampMs: timestampMs ?? this.timestampMs,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        authorId,
        points,
        colorValue,
        width,
        tool,
        timestampMs,
      ];

  @override
  bool get stringify => true;
}
