/// An inclusive integer range used by the room-settings controls.
typedef IntRange = ({int min, int max});

/// Convenience checks on an [IntRange].
extension IntRangeX on IntRange {
  /// Whether [value] lies inside this range, bounds included.
  bool contains(int value) => value >= min && value <= max;

  /// Returns [value] pulled inside this range.
  int coerce(int value) => value < min ? min : (value > max ? max : value);

  /// Number of discrete steps between [min] and [max].
  int get span => max - min;
}

/// Default and allowed values of everything a host can tune.
///
/// `RoomSettings` mirrors these numbers, and the server validates against the
/// very same ranges, so both sides must agree.
abstract final class GameDefaults {
  // ---------------------------------------------------------------------------
  // Default room settings
  // ---------------------------------------------------------------------------

  /// Default number of seats in a room.
  static const int maxPlayers = 8;

  /// Default number of rounds in a match.
  static const int rounds = 3;

  /// Default seconds a drawer gets per turn.
  static const int drawTimeSeconds = 80;

  /// Default number of words a drawer chooses from.
  static const int wordChoiceCount = 3;

  /// Default number of letters revealed as hints per turn.
  static const int hintCount = 2;

  /// Default seconds a drawer gets to pick a word.
  static const int wordSelectSeconds = 15;

  /// Whether players may start a kick vote by default.
  static const bool allowVoteKick = true;

  /// Whether guessers may talk to each other. The drawer never can.
  static const bool voiceEnabled = true;

  /// Whether the text channel is open. Guessing is never affected.
  static const bool chatEnabled = true;

  /// Whether people may watch once every seat is taken.
  static const bool allowSpectators = true;

  /// Whether only the host's friends may join by code.
  static const bool friendsOnly = false;

  /// Whether a new room is hidden from public listings by default.
  static const bool isPrivate = false;

  /// Minimum number of custom words needed for custom word mode.
  static const int minCustomWords = 5;

  /// Longest accepted custom word, in characters.
  static const int maxCustomWordLength = 24;

  /// Shortest accepted custom word, in characters.
  static const int minCustomWordLength = 2;

  // ---------------------------------------------------------------------------
  // Allowed ranges
  // ---------------------------------------------------------------------------

  /// Allowed number of seats in a room.
  static const IntRange maxPlayersRange = (min: 2, max: 12);

  /// Allowed number of rounds in a match.
  static const IntRange roundsRange = (min: 1, max: 10);

  /// Allowed drawing time per turn, in seconds.
  static const IntRange drawTimeRange = (min: 30, max: 180);

  /// Allowed number of words offered to the drawer.
  static const IntRange wordChoiceRange = (min: 2, max: 5);

  /// Allowed number of hint letters per turn.
  static const IntRange hintRange = (min: 0, max: 5);

  /// Allowed word-pick time, in seconds.
  static const IntRange wordSelectRange = (min: 5, max: 30);

  /// Step size of the draw-time slider, in seconds.
  static const int drawTimeStepSeconds = 10;

  /// Step size of the word-pick-time slider, in seconds.
  static const int wordSelectStepSeconds = 5;

  /// Players needed before a match can start.
  static const int minPlayersToStart = 2;

  // ---------------------------------------------------------------------------
  // Round and turn timing
  // ---------------------------------------------------------------------------

  /// Seconds of countdown between the lobby and the first turn.
  static const int startCountdownSeconds = 3;

  /// Seconds the round result stays on screen before the next turn.
  static const int roundEndSeconds = 6;

  /// Seconds the final standings stay on screen before the lobby returns.
  static const int gameEndSeconds = 15;

  /// Milliseconds of slack added to the turn deadline for late packets.
  static const int turnGraceMs = 400;

  /// Milliseconds between local ticks of the countdown widget.
  static const int timerTickMs = 200;

  /// Fraction of the turn that elapses before the first hint is revealed.
  static const double firstHintAtFraction = 0.45;

  /// Fraction of the turn after which no further hint is revealed.
  static const double lastHintAtFraction = 0.85;

  /// Seconds the turn is cut short to once everybody has guessed.
  static const int allGuessedGraceSeconds = 3;

  // ---------------------------------------------------------------------------
  // Scoring
  // ---------------------------------------------------------------------------

  /// Points a guesser earns for being correct at all.
  static const int guessBasePoints = 100;

  /// Extra points a guesser earns for answering with the whole clock left.
  static const int guessMaxTimeBonus = 100;

  /// Extra points for the very first correct guess of a turn.
  static const int firstGuessBonus = 40;

  /// Points subtracted per place in the correct-guess order.
  static const int guessOrderPenalty = 8;

  /// Floor of the guesser reward, however late the guess arrives.
  static const int guessMinPoints = 20;

  /// Points the drawer earns per player who guessed the word.
  static const int drawerPointsPerGuesser = 30;

  /// Bonus for a drawer whose word was guessed by everybody.
  static const int drawerAllGuessedBonus = 25;

  /// Ceiling of the drawer reward for a single turn.
  static const int drawerMaxPoints = 150;

  /// Score multiplier applied to easy words.
  static const double easyMultiplier = 1.0;

  /// Score multiplier applied to medium words.
  static const double mediumMultiplier = 1.15;

  /// Score multiplier applied to hard words.
  static const double hardMultiplier = 1.3;

  /// Minimum letters a word needs before a one-letter typo counts as close.
  static const int closeGuessMinLength = 4;
}
