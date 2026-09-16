import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:scribble_guess/core/rules/rules.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/models/words/fallback_words.dart';
import 'package:scribble_guess/models/words/word_bank.dart';

/// A solo practice turn, run entirely on this device.
///
/// ## Why this exists at all
///
/// Every rule it needs was already written and already tested: `WordSelector`,
/// `HintEngine`, `TurnTimer` and `GuessMatcher` live in `lib/core/rules` and
/// are pure. They were built so the client could *predict* what the server was
/// about to do; running them with no server at all is the same code with
/// nothing to predict.
///
/// ## What it deliberately cannot do
///
/// Nothing here touches the network, and nothing here is worth anything. A
/// practice score is local, is never sent, and never reaches the leaderboard,
/// XP, achievements or statistics — which is not a policy this class enforces
/// so much as a fact about it: there is no code path out of this file. That is
/// the honest way to satisfy "no XP abuse" and "no achievement abuse": not a
/// server-side check on a practice flag a client could lie about, but a mode
/// that never speaks to the server.
///
/// ## Why the timer is a plain elapsed count
///
/// A real turn runs on the server's clock because two devices must agree. A
/// solo turn has nobody to agree with, so it runs on this device's clock and
/// the whole clock-offset apparatus is simply not needed.
class PracticeSession extends Equatable {
  /// Creates a session state.
  const PracticeSession({
    required this.settings,
    this.phase = PracticePhase.choosing,
    this.choices = const <WordItem>[],
    this.word,
    this.hintIndices = const <int>[],
    this.turnStartMs = 0,
    this.turnEndMs = 0,
    this.score = 0,
    this.roundsPlayed = 0,
    this.lastVerdict,
    this.usedWords = const <String>{},
  });

  /// The rules this session runs under. Local, and never sent anywhere.
  final RoomSettings settings;

  /// Where the turn is.
  final PracticePhase phase;

  /// What the player may choose from, while choosing.
  final List<WordItem> choices;

  /// The word being drawn, once chosen.
  final WordItem? word;

  /// Letters revealed so far.
  final List<int> hintIndices;

  final int turnStartMs;
  final int turnEndMs;

  /// Points this session. Local only — see the note on the class.
  final int score;

  /// How many turns have been completed.
  final int roundsPlayed;

  /// The result of the last guess, for the input to react to.
  final GuessVerdict? lastVerdict;

  /// Words already drawn this session, so a short bank does not repeat.
  final Set<String> usedWords;

  /// The masked word as the player sees it.
  ///
  /// In practice the drawer *is* the guesser, so the mask is shown for the
  /// same reason a mirror is useful: it is what the word would look like to
  /// somebody guessing, which is what the player is practising drawing for.
  String get maskedWord =>
      word == null ? '' : HintEngine.maskWord(word!.text, hintIndices);

  /// Whether the turn is running.
  bool get isDrawing => phase == PracticePhase.drawing;

  /// Seconds left, against [nowMs].
  int secondsRemaining(int nowMs) =>
      TurnTimer.secondsRemaining(turnEndMs: turnEndMs, serverNowMs: nowMs);

  /// Returns a copy with the given fields replaced.
  PracticeSession copyWith({
    RoomSettings? settings,
    PracticePhase? phase,
    List<WordItem>? choices,
    WordItem? word,
    bool clearWord = false,
    List<int>? hintIndices,
    int? turnStartMs,
    int? turnEndMs,
    int? score,
    int? roundsPlayed,
    GuessVerdict? lastVerdict,
    bool clearVerdict = false,
    Set<String>? usedWords,
  }) =>
      PracticeSession(
        settings: settings ?? this.settings,
        phase: phase ?? this.phase,
        choices: choices ?? this.choices,
        word: clearWord ? null : (word ?? this.word),
        hintIndices: hintIndices ?? this.hintIndices,
        turnStartMs: turnStartMs ?? this.turnStartMs,
        turnEndMs: turnEndMs ?? this.turnEndMs,
        score: score ?? this.score,
        roundsPlayed: roundsPlayed ?? this.roundsPlayed,
        lastVerdict: clearVerdict ? null : (lastVerdict ?? this.lastVerdict),
        usedWords: usedWords ?? this.usedWords,
      );

  @override
  List<Object?> get props => <Object?>[
        phase,
        choices,
        word,
        hintIndices,
        turnStartMs,
        turnEndMs,
        score,
        roundsPlayed,
        lastVerdict,
      ];

  @override
  bool get stringify => true;
}

/// Where a practice turn is.
enum PracticePhase {
  /// Picking a word to draw.
  choosing,

  /// Drawing, with the clock running.
  drawing,

  /// The turn is over; the word is shown.
  finished,
}

/// Drives a [PracticeSession] through its phases.
///
/// Pure and synchronous: every method takes the current state and a clock
/// reading and returns the next state. That makes the whole of practice mode
/// testable without a widget, a ticker or a canvas — which matters, because
/// the turn logic is the only part of this feature that can be wrong.
class PracticeEngine {
  /// Creates an engine drawing words from [bank], using [random].
  PracticeEngine({required this.bank, Random? random})
      : _random = random ?? Random(),
        _selector = WordSelector(random ?? Random());

  /// The word bank to draw from.
  final WordBank bank;

  final WordSelector _selector;
  final Random _random;

  /// The scoring used for practice.
  ///
  /// The same weights the real game uses, so a practice score means roughly
  /// what a real one would — but there is no drawer bonus here, because in
  /// practice the drawer and the guesser are the same person and paying both
  /// would double every turn.
  static const ScoringService _scoring = ScoringService(ScoringConfig.standard);

  /// A fresh session, already offering its first choice of words.
  PracticeSession start(RoomSettings settings, int nowMs) {
    return _offerWords(
      PracticeSession(settings: settings),
      nowMs,
    );
  }

  /// Offers a new set of words to choose from.
  PracticeSession _offerWords(PracticeSession session, int nowMs) {
    final List<WordItem> choices = _selector.pickChoices(
      pool: bank.all(),
      settings: session.settings,
      usedWords: session.usedWords,
      count: session.settings.wordChoiceCount,
    );

    return session.copyWith(
      phase: PracticePhase.choosing,
      choices: choices,
      clearWord: true,
      hintIndices: const <int>[],
      clearVerdict: true,
    );
  }

  /// Starts the turn with [word].
  PracticeSession choose(PracticeSession session, WordItem word, int nowMs) {
    final int durationMs = session.settings.drawTimeSeconds * 1000;

    return session.copyWith(
      phase: PracticePhase.drawing,
      word: word,
      choices: const <WordItem>[],
      hintIndices: const <int>[],
      turnStartMs: nowMs,
      turnEndMs: nowMs + durationMs,
      usedWords: <String>{...session.usedWords, word.text},
      clearVerdict: true,
    );
  }

  /// Reveals the hints due by [nowMs].
  ///
  /// Driven by elapsed time rather than by a schedule of timers, so a session
  /// backgrounded mid-turn catches up on resume instead of silently skipping
  /// the hints it slept through.
  PracticeSession tick(PracticeSession session, int nowMs) {
    if (!session.isDrawing || session.word == null) return session;

    if (TurnTimer.isExpired(turnEndMs: session.turnEndMs, serverNowMs: nowMs)) {
      return finish(session, correct: false);
    }

    // Which hint is due, from elapsed time rather than from a timer.
    // A session backgrounded mid-turn catches up on resume instead of
    // silently skipping the hints it slept through.
    final int totalMs = session.turnEndMs - session.turnStartMs;
    final double elapsed =
        totalMs <= 0 ? 1 : (nowMs - session.turnStartMs) / totalMs;

    final int hintNumber = (
      elapsed * (session.settings.hintCount + 1)
    ).floor().clamp(0, session.settings.hintCount);

    if (hintNumber <= 0) return session;

    final List<int> next = HintEngine.nextHintIndices(
      word: session.word!.text,
      current: session.hintIndices,
      totalHints: session.settings.hintCount,
      hintNumber: hintNumber,
      random: _random,
    );

    if (next.length == session.hintIndices.length) return session;
    return session.copyWith(hintIndices: next);
  }

  /// Judges a guess against the current word.
  ///
  /// A correct guess ends the turn and scores it; anything else records the
  /// verdict so the input can react, and leaves the clock running.
  PracticeSession guess(PracticeSession session, String text, int nowMs) {
    if (!session.isDrawing || session.word == null) return session;

    final GuessVerdict verdict = GuessMatcher.evaluate(text, session.word!.text);

    if (verdict != GuessVerdict.correct) {
      return session.copyWith(lastVerdict: verdict);
    }

    final int points = _scoring.guesserPoints(
      msRemaining: TurnTimer.remaining(
        turnEndMs: session.turnEndMs,
        serverNowMs: nowMs,
      ).inMilliseconds,
      msTotal: session.turnEndMs - session.turnStartMs,
      guessOrder: 1,
      difficulty: session.word!.difficulty,
    );

    return finish(session.copyWith(score: session.score + points), correct: true);
  }

  /// Ends the turn, revealing the word.
  PracticeSession finish(PracticeSession session, {required bool correct}) {
    return session.copyWith(
      phase: PracticePhase.finished,
      roundsPlayed: session.roundsPlayed + 1,
      lastVerdict: correct ? GuessVerdict.correct : GuessVerdict.wrong,
    );
  }

  /// Moves on to the next turn.
  PracticeSession next(PracticeSession session, int nowMs) =>
      _offerWords(session, nowMs);

  /// A bank for [language], falling back to the bundled words.
  ///
  /// Practice must work with no network and no assets loaded, so the fallback
  /// is not an error path — it is the expected one on a first run.
  static WordBank bankFor(AppLanguage language) =>
      FallbackWords.bank(language);
}
