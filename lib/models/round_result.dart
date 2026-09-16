import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// Scoreboard delta for one finished turn, sent on `s:game:roundEnd`.
class RoundResult extends Equatable {
  /// Creates a round result.
  const RoundResult({
    this.round = 0,
    this.word = '',
    this.drawerId = '',
    this.scoreDeltas = const <String, int>{},
    this.totals = const <String, int>{},
    this.correctOrder = const <String>[],
    this.gameId = '',
    this.turnNumber = 0,
  });

  /// Builds a result from a decoded JSON map, tolerating malformed values.
  factory RoundResult.fromJson(Map<String, dynamic> json) => RoundResult(
        round: asInt(json['round']),
        word: asString(json['word']),
        drawerId: asString(json['drawerId']),
        scoreDeltas: asIntMap(json['scoreDeltas']),
        totals: asIntMap(json['totals']),
        correctOrder: asStringList(json['correctOrder']),
        gameId: asString(json['gameId']),
        turnNumber: asInt(json['turnNumber']),
      );

  /// One-based round number the turn belonged to.
  final int round;

  /// The word that was being drawn, revealed once the turn ended.
  final String word;

  /// Identifier of the player who drew.
  final String drawerId;

  /// Points earned this turn, keyed by player id.
  final Map<String, int> scoreDeltas;

  /// Running game totals after this turn, keyed by player id.
  final Map<String, int> totals;

  /// Which match this turn belonged to, and which turn of it.
  ///
  /// Together they name this turn's replay — the drawing becomes readable at
  /// exactly the moment this result is sent, because the turn has ended. Empty
  /// for a turn played outside a persisted match, which is what the result
  /// screen checks before offering a replay.
  final String gameId;

  /// The turn's number within the whole match, 1-based.
  final int turnNumber;

  /// Identifiers of the players who guessed correctly, fastest first.
  final List<String> correctOrder;

  /// Serializes this result to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'round': round,
        'word': word,
        'drawerId': drawerId,
        'scoreDeltas': <String, int>{...scoreDeltas},
        'totals': <String, int>{...totals},
        'correctOrder': <String>[...correctOrder],
        'gameId': gameId,
        'turnNumber': turnNumber,
      };

  /// Returns a copy with the given fields replaced.
  RoundResult copyWith({
    int? round,
    String? word,
    String? drawerId,
    Map<String, int>? scoreDeltas,
    Map<String, int>? totals,
    List<String>? correctOrder,
    String? gameId,
    int? turnNumber,
  }) =>
      RoundResult(
        round: round ?? this.round,
        word: word ?? this.word,
        drawerId: drawerId ?? this.drawerId,
        scoreDeltas: scoreDeltas ?? this.scoreDeltas,
        totals: totals ?? this.totals,
        correctOrder: correctOrder ?? this.correctOrder,
        gameId: gameId ?? this.gameId,
        turnNumber: turnNumber ?? this.turnNumber,
      );

  @override
  List<Object?> get props => <Object?>[
        round,
        word,
        drawerId,
        scoreDeltas,
        totals,
        correctOrder,
        gameId,
        turnNumber,
      ];

  @override
  bool get stringify => true;
}
