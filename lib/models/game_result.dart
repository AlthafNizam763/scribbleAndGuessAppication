import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/game_mode.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player_score.dart';

/// Final standings of a finished game, sent on `s:game:end`.
class GameResult extends Equatable {
  /// Creates a game result.
  const GameResult({
    this.roomCode = '',
    this.standings = const <PlayerScore>[],
    this.totalRounds = 0,
    this.gameMode = GameMode.classic,
    this.awards = const MatchAwards(),
  });

  /// Builds a result from a decoded JSON map, tolerating malformed values.
  factory GameResult.fromJson(Map<String, dynamic> json) => GameResult(
        roomCode: asString(json['roomCode']),
        standings: <PlayerScore>[
          for (final dynamic raw in asList(json['standings']))
            PlayerScore.fromJson(asMap(raw)),
        ],
        totalRounds: asInt(json['totalRounds']),
        gameMode: GameMode.parse(json['gameMode']),
        awards: MatchAwards.fromJson(asMap(json['awards'])),
      );

  /// Join code of the room the game was played in.
  final String roomCode;

  /// Final standings, best rank first.
  final List<PlayerScore> standings;

  /// How many rounds were played.
  final int totalRounds;

  /// Which rule set this match ran under.
  final GameMode gameMode;

  /// Who did what, for the result card.
  final MatchAwards awards;

  /// The winning row, or `null` when nobody played.
  PlayerScore? get winner => standings.isEmpty ? null : standings.first;

  /// Serializes this result to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'roomCode': roomCode,
        'standings': <Map<String, dynamic>>[
          for (final PlayerScore score in standings) score.toJson(),
        ],
        'totalRounds': totalRounds,
        'gameMode': gameMode.wire,
        'awards': awards.toJson(),
      };

  /// Returns a copy with the given fields replaced.
  GameResult copyWith({
    String? roomCode,
    List<PlayerScore>? standings,
    int? totalRounds,
    GameMode? gameMode,
    MatchAwards? awards,
  }) =>
      GameResult(
        roomCode: roomCode ?? this.roomCode,
        standings: standings ?? this.standings,
        totalRounds: totalRounds ?? this.totalRounds,
        gameMode: gameMode ?? this.gameMode,
        awards: awards ?? this.awards,
      );

  @override
  List<Object?> get props =>
      <Object?>[roomCode, standings, totalRounds, gameMode, awards];

  @override
  bool get stringify => true;
}

/// Who did what in a finished match, for the shareable result card.
///
/// ## Ids, never names or scores
///
/// The card that renders these already has the standings, so repeating a name
/// here would be a second copy able to disagree with the first. Every field is
/// a player id or null — null when nobody qualified, which is the honest
/// answer for a match where nobody drew or nobody guessed.
class MatchAwards extends Equatable {
  /// Creates a set of awards.
  const MatchAwards({
    this.topScorerId,
    this.bestDrawerId,
    this.bestGuesserId,
    this.fastestGuesserId,
  });

  /// Builds awards from a decoded JSON map. Never throws.
  factory MatchAwards.fromJson(Map<String, dynamic> json) => MatchAwards(
        topScorerId: _idOrNull(json['topScorerId']),
        bestDrawerId: _idOrNull(json['bestDrawerId']),
        bestGuesserId: _idOrNull(json['bestGuesserId']),
        fastestGuesserId: _idOrNull(json['fastestGuesserId']),
      );

  static String? _idOrNull(dynamic value) {
    final String id = asString(value);
    return id.isEmpty ? null : id;
  }

  /// Highest final score.
  final String? topScorerId;

  /// Most perfect turns drawn, tie-broken on turns drawn.
  final String? bestDrawerId;

  /// Most correct guesses.
  final String? bestGuesserId;

  /// Most first-place guesses.
  final String? fastestGuesserId;

  /// Whether there is anything to show.
  ///
  /// False for a match nobody drew or guessed in — the card then omits the
  /// awards section rather than printing four dashes.
  bool get isEmpty =>
      topScorerId == null &&
      bestDrawerId == null &&
      bestGuesserId == null &&
      fastestGuesserId == null;

  /// Serializes to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'topScorerId': topScorerId,
        'bestDrawerId': bestDrawerId,
        'bestGuesserId': bestGuesserId,
        'fastestGuesserId': fastestGuesserId,
      };

  @override
  List<Object?> get props =>
      <Object?>[topScorerId, bestDrawerId, bestGuesserId, fastestGuesserId];

  @override
  bool get stringify => true;
}
