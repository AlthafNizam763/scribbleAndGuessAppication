import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// A player's full career record.
///
/// ## Why this is separate from [PlayerStats] in `social.dart`
///
/// That one is the *card* — five numbers on a leaderboard row, sent with every
/// row. This is the full record, read once when somebody opens their stats
/// screen. Folding them together would put twenty fields on every leaderboard
/// row to serve a screen nobody is looking at.
///
/// Every figure is derived by the server from counters the game engine writes.
/// Nothing here is stored as a total, so nothing can drift from the game that
/// produced it — and nothing here is writable by this app.
class PlayerCareerStats extends Equatable {
  /// Creates a career record.
  const PlayerCareerStats({
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.gamesLost = 0,
    this.winRate = 0,
    this.totalScore = 0,
    this.bestRoundScore = 0,
    this.averageScore = 0,
    this.correctGuesses = 0,
    this.firstGuesses = 0,
    this.fastGuesses = 0,
    this.drawingTurns = 0,
    this.perfectDrawings = 0,
    this.perfectDrawingRate = 0,
    this.currentWinStreak = 0,
    this.bestWinStreak = 0,
    this.xp = 0,
    this.level = 1,
    this.levelTitle = '',
    this.achievementsUnlocked = 0,
    this.achievementsTotal = 0,
    this.joinedAtMs = 0,
    this.lastSeenAtMs = 0,
  });

  /// Builds a record from a decoded JSON map. Never throws.
  factory PlayerCareerStats.fromJson(Map<String, dynamic> json) =>
      PlayerCareerStats(
        gamesPlayed: asInt(json['gamesPlayed']),
        gamesWon: asInt(json['gamesWon']),
        gamesLost: asInt(json['gamesLost']),
        winRate: asDouble(json['winRate']),
        totalScore: asInt(json['totalScore']),
        bestRoundScore: asInt(json['bestRoundScore']),
        averageScore: asInt(json['averageScore']),
        correctGuesses: asInt(json['correctGuesses']),
        firstGuesses: asInt(json['firstGuesses']),
        fastGuesses: asInt(json['fastGuesses']),
        drawingTurns: asInt(json['drawingTurns']),
        perfectDrawings: asInt(json['perfectDrawings']),
        perfectDrawingRate: asDouble(json['perfectDrawingRate']),
        currentWinStreak: asInt(json['currentWinStreak']),
        bestWinStreak: asInt(json['bestWinStreak']),
        xp: asInt(json['xp']),
        level: asInt(json['level'], 1),
        levelTitle: asString(json['levelTitle']),
        achievementsUnlocked: asInt(json['achievementsUnlocked']),
        achievementsTotal: asInt(json['achievementsTotal']),
        joinedAtMs: asInt(json['joinedAtMs']),
        lastSeenAtMs: asInt(json['lastSeenAtMs']),
      );

  final int gamesPlayed;
  final int gamesWon;

  /// Games finished without winning. Derived by the server.
  final int gamesLost;

  /// Wins as a percentage, to one decimal place.
  final double winRate;

  final int totalScore;

  /// The best single match score.
  final int bestRoundScore;

  /// Mean score per finished match.
  final int averageScore;

  final int correctGuesses;

  /// Correct guesses that were the first of their turn.
  final int firstGuesses;

  /// Correct guesses inside the opening fraction of a turn.
  final int fastGuesses;

  /// Turns taken as the drawer and finished.
  final int drawingTurns;

  /// Turns drawn where every eligible guesser got it.
  final int perfectDrawings;

  /// Perfect drawings as a percentage of turns drawn.
  final double perfectDrawingRate;

  final int currentWinStreak;
  final int bestWinStreak;

  final int xp;
  final int level;
  final String levelTitle;

  final int achievementsUnlocked;
  final int achievementsTotal;

  final int joinedAtMs;
  final int lastSeenAtMs;

  /// Whether this account has finished anything yet.
  ///
  /// What the stats screen keys its empty state off: every ratio below is zero
  /// for a fresh account, and a wall of zeroes reads as a broken screen rather
  /// than as a new player.
  bool get hasPlayed => gamesPlayed > 0;

  /// The win rate as it is printed, e.g. `40.0%`.
  String get winRateLabel =>
      gamesPlayed == 0 ? '—' : '${winRate.toStringAsFixed(1)}%';

  /// The perfect-drawing rate as it is printed.
  String get perfectDrawingRateLabel =>
      drawingTurns == 0 ? '—' : '${perfectDrawingRate.toStringAsFixed(1)}%';

  /// Trophies as a fraction, e.g. `3 / 12`.
  String get achievementsLabel => '$achievementsUnlocked / $achievementsTotal';

  @override
  List<Object?> get props => <Object?>[
        gamesPlayed,
        gamesWon,
        totalScore,
        correctGuesses,
        drawingTurns,
        xp,
        level,
        achievementsUnlocked,
      ];

  @override
  bool get stringify => true;
}
