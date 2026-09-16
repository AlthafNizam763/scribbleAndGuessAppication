import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';

const String _kBegin = 'begin';
const String _kAppend = 'append';
const String _kEnd = 'end';
const String _kUndo = 'undo';
const String _kRedo = 'redo';
const String _kClear = 'clear';
const String _kSnapshot = 'snapshot';

List<StrokePoint> _pointsOf(dynamic value) => <StrokePoint>[
      for (final dynamic raw in asList(value)) StrokePoint.fromJsonList(raw),
    ];

List<List<double>> _pointsJson(List<StrokePoint> points) => <List<double>>[
      for (final StrokePoint point in points) point.toJsonList(),
    ];

/// Something that happened on the drawing board. Every variant round-trips
/// through JSON so it can cross the socket unchanged.
sealed class DrawingEvent extends Equatable {
  /// Creates an event.
  const DrawingEvent();

  /// Parses any drawing event, returning `null` for an unrecognised payload.
  static DrawingEvent? fromJson(Map<String, dynamic> json) {
    switch (asString(json['type'])) {
      case _kBegin:
        return StrokeBegan.fromJson(json);
      case _kAppend:
        return StrokeAppended.fromJson(json);
      case _kEnd:
        return StrokeEnded.fromJson(json);
      case _kUndo:
        return StrokeUndone.fromJson(json);
      case _kRedo:
        return StrokeRedone.fromJson(json);
      case _kClear:
        return BoardCleared.fromJson(json);
      case _kSnapshot:
        return BoardSnapshot.fromJson(json);
      default:
        return null;
    }
  }

  /// Serializes this event to a JSON-safe map carrying a `type` discriminator.
  Map<String, dynamic> toJson();

  @override
  bool get stringify => true;
}

/// A new stroke started.
final class StrokeBegan extends DrawingEvent {
  /// Creates the event.
  const StrokeBegan(this.stroke);

  /// Builds the event from a decoded JSON map.
  factory StrokeBegan.fromJson(Map<String, dynamic> json) =>
      StrokeBegan(Stroke.fromJson(asMap(json['stroke'])));

  /// The stroke as it looked when it started.
  final Stroke stroke;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': _kBegin,
        'stroke': stroke.toJson(),
      };

  @override
  List<Object?> get props => <Object?>[stroke];
}

/// More points arrived for a stroke that is still being drawn.
final class StrokeAppended extends DrawingEvent {
  /// Creates the event.
  const StrokeAppended(this.strokeId, this.points);

  /// Builds the event from a decoded JSON map.
  factory StrokeAppended.fromJson(Map<String, dynamic> json) => StrokeAppended(
        asString(json['strokeId']),
        _pointsOf(json['points']),
      );

  /// Identifier of the stroke being extended.
  final String strokeId;

  /// The new normalized points, in draw order.
  final List<StrokePoint> points;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': _kAppend,
        'strokeId': strokeId,
        'points': _pointsJson(points),
      };

  @override
  List<Object?> get props => <Object?>[strokeId, points];
}

/// A stroke was finished by its author.
final class StrokeEnded extends DrawingEvent {
  /// Creates the event.
  const StrokeEnded(this.strokeId);

  /// Builds the event from a decoded JSON map.
  factory StrokeEnded.fromJson(Map<String, dynamic> json) =>
      StrokeEnded(asString(json['strokeId']));

  /// Identifier of the finished stroke.
  final String strokeId;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': _kEnd,
        'strokeId': strokeId,
      };

  @override
  List<Object?> get props => <Object?>[strokeId];
}

/// A stroke was undone.
final class StrokeUndone extends DrawingEvent {
  /// Creates the event.
  const StrokeUndone(this.strokeId);

  /// Builds the event from a decoded JSON map.
  factory StrokeUndone.fromJson(Map<String, dynamic> json) =>
      StrokeUndone(asString(json['strokeId']));

  /// Identifier of the undone stroke.
  final String strokeId;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': _kUndo,
        'strokeId': strokeId,
      };

  @override
  List<Object?> get props => <Object?>[strokeId];
}

/// A previously undone stroke was put back.
final class StrokeRedone extends DrawingEvent {
  /// Creates the event.
  const StrokeRedone(this.stroke);

  /// Builds the event from a decoded JSON map.
  factory StrokeRedone.fromJson(Map<String, dynamic> json) =>
      StrokeRedone(Stroke.fromJson(asMap(json['stroke'])));

  /// The restored stroke.
  final Stroke stroke;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': _kRedo,
        'stroke': stroke.toJson(),
      };

  @override
  List<Object?> get props => <Object?>[stroke];
}

/// The whole board was wiped.
final class BoardCleared extends DrawingEvent {
  /// Creates the event.
  const BoardCleared();

  /// Builds the event from a decoded JSON map. The payload carries no data.
  factory BoardCleared.fromJson(Map<String, dynamic> _) =>
      const BoardCleared();

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{'type': _kClear};

  @override
  List<Object?> get props => const <Object?>[];
}

/// The full board state, sent to players who joined mid-turn.
final class BoardSnapshot extends DrawingEvent {
  /// Creates the event.
  const BoardSnapshot(this.strokes);

  /// Builds the event from a decoded JSON map.
  factory BoardSnapshot.fromJson(Map<String, dynamic> json) => BoardSnapshot(
        <Stroke>[
          for (final dynamic raw in asList(json['strokes']))
            Stroke.fromJson(asMap(raw)),
        ],
      );

  /// Every committed stroke, in paint order.
  final List<Stroke> strokes;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': _kSnapshot,
        'strokes': <Map<String, dynamic>>[
          for (final Stroke stroke in strokes) stroke.toJson(),
        ],
      };

  @override
  List<Object?> get props => <Object?>[strokes];
}
