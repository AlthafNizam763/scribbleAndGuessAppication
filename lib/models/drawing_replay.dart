import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/stroke.dart';

/// One finished turn's drawing, stored so it can be played back.
///
/// ## Read-only, and only ever for a turn that has ended
///
/// A replay carries the drawing *and* the word. The server builds one only
/// once `endedAt` is set, and refuses a live turn as if it did not exist — so
/// this model has no state in which it holds an unrevealed answer.
///
/// Every `fromJson` tolerates a malformed or missing field rather than
/// throwing, like the rest of `lib/models`: a replay that drops one bad stroke
/// still plays.

/// A replay without its strokes, as the list of a match's turns shows them.
class ReplaySummary extends Equatable {
  /// Creates a summary.
  const ReplaySummary({
    this.turnNumber = 0,
    this.roundNumber = 0,
    this.drawerId = '',
    this.drawerName = '',
    this.word = '',
    this.durationMs = 0,
    this.correctGuessers = 0,
    this.strokeCount = 0,
    this.compacted = false,
    this.endedAtMs = 0,
  });

  /// Builds a summary from a decoded JSON map. Never throws.
  factory ReplaySummary.fromJson(Map<String, dynamic> json) => ReplaySummary(
        turnNumber: asInt(json['turnNumber']),
        roundNumber: asInt(json['roundNumber']),
        drawerId: asString(json['drawerId']),
        drawerName: asString(json['drawerName']),
        word: asString(json['word']),
        durationMs: asInt(json['durationMs']),
        correctGuessers: asInt(json['correctGuessers']),
        strokeCount: asInt(json['strokeCount']),
        compacted: asBool(json['compacted']),
        endedAtMs: asInt(json['endedAtMs']),
      );

  /// Which turn of the match, 1-based and always increasing.
  final int turnNumber;

  /// Which pass around the table.
  final int roundNumber;

  /// Who drew it.
  final String drawerId;

  /// Their name, as it stood at the time.
  final String drawerName;

  /// The answer. Always present, because a replay only exists once revealed.
  final String word;

  /// How long the turn ran.
  final int durationMs;

  /// How many people got it.
  final int correctGuessers;

  /// How many strokes the replay will play.
  final int strokeCount;

  /// Whether the stored drawing was thinned to fit the server's budget.
  ///
  /// Surfaced rather than hidden: a replay visibly coarser than the original
  /// should be explainable rather than mysterious.
  final bool compacted;

  /// When the turn ended, in server milliseconds.
  final int endedAtMs;

  /// Whether this refers to a real turn.
  bool get isEmpty => turnNumber <= 0;

  /// Whether there is anything to play.
  bool get hasDrawing => strokeCount > 0;

  @override
  List<Object?> get props =>
      <Object?>[turnNumber, roundNumber, drawerId, word, strokeCount];

  @override
  bool get stringify => true;
}

/// A replay with everything needed to play it back.
class DrawingReplay extends Equatable {
  /// Creates a replay.
  const DrawingReplay({
    this.summary = const ReplaySummary(),
    this.strokes = const <Stroke>[],
  });

  /// Builds a replay from a decoded JSON map. Never throws.
  ///
  /// The summary fields sit alongside the strokes in one object on the wire,
  /// so both are parsed from the same map.
  factory DrawingReplay.fromJson(Map<String, dynamic> json) => DrawingReplay(
        summary: ReplaySummary.fromJson(json),
        strokes: <Stroke>[
          for (final dynamic raw in asList(json['strokes']))
            Stroke.fromJson(asMap(raw)),
        ]
            .where((Stroke stroke) => stroke.points.isNotEmpty)
            .toList(growable: false),
      );

  /// Who drew what, and when.
  final ReplaySummary summary;

  /// The strokes, in the order they were drawn.
  ///
  /// The same [Stroke] the live board uses, so the replay renderer and the
  /// live renderer are the same painter.
  final List<Stroke> strokes;

  /// Whether there is a drawing to play.
  ///
  /// False for a turn nobody drew in — which is a real outcome, not an error,
  /// and the screen shows its fallback rather than an empty canvas.
  bool get isEmpty => strokes.isEmpty;

  /// Total points across every stroke, which is what playback steps through.
  int get pointCount =>
      strokes.fold(0, (int sum, Stroke stroke) => sum + stroke.points.length);

  @override
  List<Object?> get props => <Object?>[summary, strokes];

  @override
  bool get stringify => true;
}
