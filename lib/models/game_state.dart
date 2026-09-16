import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/word_item.dart';

/// The authoritative state of the running game, mirrored from the server.
/// [word] is populated only for the drawer, or for everyone after round end.
class GameState extends Equatable {
  /// Creates a game state.
  const GameState({
    this.roomCode = '',
    this.phase = GamePhase.lobby,
    this.currentRound = 0,
    this.totalRounds = 0,
    this.turnIndex = 0,
    this.drawerId,
    this.word,
    this.maskedWord = '',
    this.wordLength = 0,
    this.hintIndices = const <int>[],
    this.turnStartMs = 0,
    this.turnEndMs = 0,
    this.correctGuesserIds = const <String>[],
    this.roundScores = const <String, int>{},
    this.wordChoices = const <WordItem>[],
  });

  /// Builds a game state from a decoded JSON map, tolerating malformed values.
  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
        roomCode: asString(json['roomCode']),
        phase: GamePhase.fromName(asString(json['phase'])),
        currentRound: asInt(json['currentRound']),
        totalRounds: asInt(json['totalRounds']),
        turnIndex: asInt(json['turnIndex']),
        drawerId: json['drawerId'] == null ? null : asString(json['drawerId']),
        word: json['word'] == null ? null : asString(json['word']),
        maskedWord: asString(json['maskedWord']),
        wordLength: asInt(json['wordLength']),
        hintIndices: <int>[
          for (final dynamic raw in asList(json['hintIndices'])) asInt(raw),
        ],
        turnStartMs: asInt(json['turnStartMs']),
        turnEndMs: asInt(json['turnEndMs']),
        correctGuesserIds: asStringList(json['correctGuesserIds']),
        roundScores: asIntMap(json['roundScores']),
        wordChoices: <WordItem>[
          for (final dynamic raw in asList(json['wordChoices']))
            WordItem.fromJson(asMap(raw)),
        ],
      );

  /// The state of a game that has not started yet.
  static const GameState initial = GameState();

  /// Join code of the room this game belongs to.
  final String roomCode;

  /// Current phase of the game loop.
  final GamePhase phase;

  /// One-based number of the round in progress.
  final int currentRound;

  /// How many rounds the game runs for.
  final int totalRounds;

  /// Index of the current turn inside the round, in seating order.
  final int turnIndex;

  /// Identifier of the player drawing this turn, `null` between turns.
  final String? drawerId;

  /// The secret word. Non-null only for the drawer or after the round ended.
  final String? word;

  /// The word with unrevealed letters replaced by blanks.
  final String maskedWord;

  /// Number of letters in the word, including spaces and hyphens.
  final int wordLength;

  /// Indices of the letters revealed as hints so far.
  final List<int> hintIndices;

  /// Turn start time in milliseconds since epoch, on the server clock.
  final int turnStartMs;

  /// Turn deadline in milliseconds since epoch, on the server clock.
  final int turnEndMs;

  /// Identifiers of the players who already guessed, fastest first.
  final List<String> correctGuesserIds;

  /// Points earned this round so far, keyed by player id.
  final Map<String, int> roundScores;

  /// Words offered to the drawer during [GamePhase.wordSelection].
  final List<WordItem> wordChoices;

  /// Whether [playerId] is the drawer of the current turn.
  bool isDrawer(String playerId) =>
      playerId.isNotEmpty && drawerId == playerId;

  /// Serializes this game state to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'roomCode': roomCode,
        'phase': phase.wire,
        'currentRound': currentRound,
        'totalRounds': totalRounds,
        'turnIndex': turnIndex,
        'drawerId': drawerId,
        'word': word,
        'maskedWord': maskedWord,
        'wordLength': wordLength,
        'hintIndices': <int>[...hintIndices],
        'turnStartMs': turnStartMs,
        'turnEndMs': turnEndMs,
        'correctGuesserIds': <String>[...correctGuesserIds],
        'roundScores': <String, int>{...roundScores},
        'wordChoices': <Map<String, dynamic>>[
          for (final WordItem item in wordChoices) item.toJson(),
        ],
      };

  /// Returns a copy with the given fields replaced. Pass `clearDrawerId` or
  /// `clearWord` to reset those nullable fields back to `null`.
  GameState copyWith({
    String? roomCode,
    GamePhase? phase,
    int? currentRound,
    int? totalRounds,
    int? turnIndex,
    String? drawerId,
    bool clearDrawerId = false,
    String? word,
    bool clearWord = false,
    String? maskedWord,
    int? wordLength,
    List<int>? hintIndices,
    int? turnStartMs,
    int? turnEndMs,
    List<String>? correctGuesserIds,
    Map<String, int>? roundScores,
    List<WordItem>? wordChoices,
  }) =>
      GameState(
        roomCode: roomCode ?? this.roomCode,
        phase: phase ?? this.phase,
        currentRound: currentRound ?? this.currentRound,
        totalRounds: totalRounds ?? this.totalRounds,
        turnIndex: turnIndex ?? this.turnIndex,
        drawerId: clearDrawerId ? null : drawerId ?? this.drawerId,
        word: clearWord ? null : word ?? this.word,
        maskedWord: maskedWord ?? this.maskedWord,
        wordLength: wordLength ?? this.wordLength,
        hintIndices: hintIndices ?? this.hintIndices,
        turnStartMs: turnStartMs ?? this.turnStartMs,
        turnEndMs: turnEndMs ?? this.turnEndMs,
        correctGuesserIds: correctGuesserIds ?? this.correctGuesserIds,
        roundScores: roundScores ?? this.roundScores,
        wordChoices: wordChoices ?? this.wordChoices,
      );

  @override
  List<Object?> get props => <Object?>[
        roomCode,
        phase,
        currentRound,
        totalRounds,
        turnIndex,
        drawerId,
        word,
        maskedWord,
        wordLength,
        hintIndices,
        turnStartMs,
        turnEndMs,
        correctGuesserIds,
        roundScores,
        wordChoices,
      ];

  @override
  bool get stringify => true;
}
