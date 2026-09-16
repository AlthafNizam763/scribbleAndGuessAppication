import 'package:scribble_guess/core/constants/firebase_constants.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/services/functions_client.dart';

/// What the drawer is offered at the start of their turn (§19).
class WordChoices {
  const WordChoices({
    required this.turnIndex,
    required this.choices,
    required this.endsAtMs,
  });

  /// The turn these choices belong to, so a late response can be discarded.
  final int turnIndex;

  /// The words on offer, in the order they should be shown.
  final List<WordItem> choices;

  /// When the choice expires on the server clock, or 0.
  final int endsAtMs;
}

/// The outcome of a guess, as told to the guesser alone (§25).
class GuessOutcome {
  const GuessOutcome({
    required this.verdict,
    required this.points,
    required this.roundOver,
  });

  /// Whether the guess was right, nearly right, or wrong.
  final GuessVerdict verdict;

  /// Points awarded. Always server-calculated; zero unless [verdict] is
  /// [GuessVerdict.correct].
  final int points;

  /// Whether this guess was the one that finished the round.
  final bool roundOver;
}

/// How a guess compared to the answer.
enum GuessVerdict {
  /// The guess matched the word or one of its aliases.
  correct,

  /// One character away from the word. Worth no points, but worth saying.
  close,

  /// Not the word.
  wrong;

  /// Parses [v], falling back to [GuessVerdict.wrong].
  static GuessVerdict fromName(String? v) =>
      asEnum(GuessVerdict.values, v) ?? GuessVerdict.wrong;
}

/// The game loop, as calls to Cloud Functions (§15, §19, §25, §37-40).
///
/// Note what is *absent*: there is no method to set a score, end a round early,
/// choose the drawer, or read the answer. Those are not omissions — they are
/// the anti-cheat model. The client can only ever state an intention, and the
/// server decides what follows (§50).
class GameService {
  GameService(this._client);

  final FunctionsClient _client;

  /// Starts the match. Host only (§15).
  Future<void> startGame(String roomId) {
    return _client.call(
      FirebaseCallables.startGame,
      <String, dynamic>{'roomId': roomId},
    );
  }

  /// Fetches the words this player may choose between.
  ///
  /// Only ever succeeds for the current drawer: for anybody else the server
  /// refuses, which is the whole reason the choices are fetched rather than
  /// read from the room document (§18).
  Future<WordChoices> getWordChoices(String roomId) async {
    final Map<String, dynamic> result = await _client.call(
      'getWordChoices',
      <String, dynamic>{'roomId': roomId},
    );
    return WordChoices(
      turnIndex: asInt(result['turnIndex']),
      choices: <WordItem>[
        for (final dynamic raw in asList(result['choices']))
          _wordFrom(asMap(raw)),
      ],
      endsAtMs: asInt(result['endsAtMs']),
    );
  }

  /// Commits the drawer's choice and opens the drawing phase (§19).
  ///
  /// Returns the chosen word, which is the one place in the whole client where
  /// an answer is held — in the drawer's own memory, for the drawer's own
  /// display.
  Future<String> selectWord(String roomId, int choiceIndex) async {
    final Map<String, dynamic> result = await _client.call(
      FirebaseCallables.selectWord,
      <String, dynamic>{'roomId': roomId, 'choiceIndex': choiceIndex},
    );
    return asString(result['word']);
  }

  /// Submits a guess (§25).
  Future<GuessOutcome> submitGuess(String roomId, String guess) async {
    final Map<String, dynamic> result = await _client.call(
      FirebaseCallables.submitGuess,
      <String, dynamic>{'roomId': roomId, 'guess': guess},
    );
    return GuessOutcome(
      verdict: GuessVerdict.fromName(asString(result['verdict'])),
      points: asInt(result['points']),
      roundOver: asBool(result['roundOver']),
    );
  }

  /// Nudges the server to close a round whose clock has run out (§37).
  ///
  /// Safe to call from any client and safe to call repeatedly: the server
  /// checks its own clock and ignores the request if the deadline has not
  /// actually passed, so an early or fast client cannot cut a round short.
  Future<void> endRound(String roomId) {
    return _client.call(
      FirebaseCallables.endRound,
      <String, dynamic>{'roomId': roomId},
    );
  }

  /// Nudges the server to begin the next round once the interval elapses.
  Future<void> nextRound(String roomId) {
    return _client.call(
      FirebaseCallables.nextRound,
      <String, dynamic>{'roomId': roomId},
    );
  }

  /// Plays the same room again with the same people (§40).
  Future<void> restartGame(String roomId) {
    return _client.call(
      FirebaseCallables.restartGame,
      <String, dynamic>{'roomId': roomId},
    );
  }

  /// The server's current clock, for offset correction (§29).
  Future<int> serverTimeMs() async {
    final Map<String, dynamic> result = await _client.call('getServerTime');
    return asInt(result['serverTimeMs']);
  }

  WordItem _wordFrom(Map<String, dynamic> data) {
    return WordItem(
      text: asString(data['word']),
      category: WordCategory.fromName(asString(data['category'])),
      difficulty: WordDifficulty.fromName(asString(data['difficulty'])),
    );
  }
}
