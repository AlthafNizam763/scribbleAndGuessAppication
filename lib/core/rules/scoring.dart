import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';

/// Tunable numbers behind every point award of a turn.
///
/// Kept separate from [ScoringService] so tests and the practice bots can
/// score with their own balance without touching the maths.
class ScoringConfig extends Equatable {
  /// Creates a scoring configuration; every field has a balanced default.
  const ScoringConfig({
    this.maxGuessPoints = 100,
    this.minGuessPoints = 30,
    this.firstGuessBonus = 25,
    this.secondGuessBonus = 15,
    this.thirdGuessBonus = 8,
    this.drawerPointsPerGuess = 20,
    this.drawerAllGuessedBonus = 30,
    this.drawerMaxPoints = 120,
    this.difficultyMultiplier = defaultDifficultyMultiplier,
  });

  /// The balance the shipped game uses.
  static const ScoringConfig standard = ScoringConfig();

  /// Multipliers applied to a raw award, keyed by word difficulty.
  static const Map<WordDifficulty, double> defaultDifficultyMultiplier =
      <WordDifficulty, double>{
    WordDifficulty.easy: 1.0,
    WordDifficulty.medium: 1.15,
    WordDifficulty.hard: 1.35,
  };

  /// Award for a guesser who answers with the whole clock still left.
  final int maxGuessPoints;

  /// Award for a guesser who answers as the clock runs out.
  final int minGuessPoints;

  /// Extra points for the first correct guess of a turn.
  final int firstGuessBonus;

  /// Extra points for the second correct guess of a turn.
  final int secondGuessBonus;

  /// Extra points for the third correct guess of a turn.
  final int thirdGuessBonus;

  /// Points the drawer earns for every player who guessed the word.
  final int drawerPointsPerGuess;

  /// Extra points for a drawer whose word everybody guessed.
  final int drawerAllGuessedBonus;

  /// Ceiling on what a drawer can earn in a single turn.
  final int drawerMaxPoints;

  /// Multiplier applied last to every award, keyed by word difficulty.
  final Map<WordDifficulty, double> difficultyMultiplier;

  /// The multiplier for [difficulty], defaulting to `1.0` when unmapped.
  double multiplierFor(WordDifficulty difficulty) =>
      difficultyMultiplier[difficulty] ?? 1.0;

  @override
  List<Object?> get props => <Object?>[
        maxGuessPoints,
        minGuessPoints,
        firstGuessBonus,
        secondGuessBonus,
        thirdGuessBonus,
        drawerPointsPerGuess,
        drawerAllGuessedBonus,
        drawerMaxPoints,
        difficultyMultiplier,
      ];

  @override
  bool get stringify => true;
}

/// Turns the facts of a turn into points. Pure, deterministic and injectable.
class ScoringService {
  /// Creates a service scoring with [config].
  const ScoringService([this.config = ScoringConfig.standard]);

  /// The balance this service scores with.
  final ScoringConfig config;

  /// Points awarded to a player who guessed the word.
  ///
  /// The time component scales linearly from `minGuessPoints` (no time left)
  /// to `maxGuessPoints` (full clock), an order bonus is added for the first
  /// three correct guesses, and the difficulty multiplier is applied last.
  /// Nonsensical input is coerced rather than thrown on, and the result is
  /// never negative.
  int guesserPoints({
    required int msRemaining,
    required int msTotal,
    required int guessOrder,
    required WordDifficulty difficulty,
  }) {
    final double ratio = _timeRatio(msRemaining: msRemaining, msTotal: msTotal);
    final int span = config.maxGuessPoints - config.minGuessPoints;
    final double timeComponent = config.minGuessPoints + span * ratio;
    final int order = guessOrder < 1 ? 1 : guessOrder;
    final int orderBonus = switch (order) {
      1 => config.firstGuessBonus,
      2 => config.secondGuessBonus,
      3 => config.thirdGuessBonus,
      _ => 0,
    };
    final double total =
        (timeComponent + orderBonus) * config.multiplierFor(difficulty);
    return _atLeastZero(total.round());
  }

  /// Points awarded to the drawer of a turn.
  ///
  /// Every correct guesser is worth `drawerPointsPerGuess`, the whole reward
  /// is scaled by the difficulty multiplier, the all-guessed bonus lands on
  /// top when nobody was left behind, and the total is capped at
  /// `drawerMaxPoints`. A turn nobody guessed is worth nothing.
  int drawerPoints({
    required int correctGuessers,
    required int totalGuessers,
    required WordDifficulty difficulty,
  }) {
    if (totalGuessers <= 0 || correctGuessers <= 0) {
      return 0;
    }
    final int guessed =
        correctGuessers > totalGuessers ? totalGuessers : correctGuessers;
    final double earned = config.drawerPointsPerGuess *
        guessed *
        config.multiplierFor(difficulty);
    final double total = guessed >= totalGuessers
        ? earned + config.drawerAllGuessedBonus
        : earned;
    final int points = _atLeastZero(total.round());
    final int cap = _atLeastZero(config.drawerMaxPoints);
    return points > cap ? cap : points;
  }

  /// Fraction of the clock still left, clamped to `0..1`.
  static double _timeRatio({required int msRemaining, required int msTotal}) {
    if (msTotal <= 0 || msRemaining <= 0) {
      return 0;
    }
    return msRemaining >= msTotal ? 1 : msRemaining / msTotal;
  }

  /// [value] with negatives folded to zero.
  static int _atLeastZero(int value) => value < 0 ? 0 : value;
}
