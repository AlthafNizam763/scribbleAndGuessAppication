import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_mode.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// Host-configurable rules of a room. Immutable and safe to share.
class RoomSettings extends Equatable {
  /// Creates room settings. Every field defaults to the recommended value.
  const RoomSettings({
    this.maxPlayers = 8,
    this.rounds = 3,
    this.drawTimeSeconds = 80,
    this.wordChoiceCount = 3,
    this.hintCount = 2,
    this.wordSelectSeconds = 15,
    this.wordMode = WordMode.normal,
    this.language = AppLanguage.en,
    this.categories = const <WordCategory>{WordCategory.random},
    this.customWords = const <String>[],
    this.allowVoteKick = true,
    this.voiceEnabled = true,
    this.chatEnabled = true,
    this.gameMode = GameMode.classic,
    this.allowSpectators = true,
    this.friendsOnly = false,
    this.wordDifficulty,
    this.isPrivate = false,
  });

  /// Builds settings from a decoded JSON map, tolerating malformed values.
  factory RoomSettings.fromJson(Map<String, dynamic> json) => RoomSettings(
        maxPlayers: asInt(json['maxPlayers'], defaults.maxPlayers),
        rounds: asInt(json['rounds'], defaults.rounds),
        drawTimeSeconds:
            asInt(json['drawTimeSeconds'], defaults.drawTimeSeconds),
        wordChoiceCount:
            asInt(json['wordChoiceCount'], defaults.wordChoiceCount),
        hintCount: asInt(json['hintCount'], defaults.hintCount),
        wordSelectSeconds:
            asInt(json['wordSelectSeconds'], defaults.wordSelectSeconds),
        wordMode: WordMode.fromName(asString(json['wordMode'])),
        language: AppLanguage.fromName(asString(json['language'])),
        categories: json['categories'] == null
            ? defaults.categories
            : <WordCategory>{
                for (final String name in asStringList(json['categories']))
                  WordCategory.fromName(name),
              },
        customWords: asStringList(json['customWords']),
        allowVoteKick: asBool(json['allowVoteKick'], defaults.allowVoteKick),
        voiceEnabled: asBool(json['voiceEnabled'], defaults.voiceEnabled),
        chatEnabled: asBool(json['chatEnabled'], defaults.chatEnabled),
        gameMode: GameMode.parse(json['gameMode']),
        allowSpectators:
            asBool(json['allowSpectators'], defaults.allowSpectators),
        friendsOnly: asBool(json['friendsOnly'], defaults.friendsOnly),
        wordDifficulty: json['wordDifficulty'] == null
            ? null
            : asString(json['wordDifficulty']),
        isPrivate: asBool(json['isPrivate'], defaults.isPrivate),
      );

  /// The recommended settings used for a brand new room.
  static const RoomSettings defaults = RoomSettings();

  /// Maximum number of seats in the room, 2..12.
  final int maxPlayers;

  /// Number of rounds, where every player draws once per round, 1..10.
  final int rounds;

  /// Seconds the drawer gets per turn, 30..180.
  final int drawTimeSeconds;

  /// How many words the drawer chooses from, 2..5.
  final int wordChoiceCount;

  /// How many letters get revealed as hints during a turn, 0..5.
  final int hintCount;

  /// Seconds the drawer gets to pick a word, 5..30.
  final int wordSelectSeconds;

  /// How the word of a turn is decided.
  final WordMode wordMode;

  /// Language of the word bank.
  final AppLanguage language;

  /// Categories the word bank draws from; never empty for a valid room.
  final Set<WordCategory> categories;

  /// Words supplied by the host, used when [wordMode] is [WordMode.custom].
  final List<String> customWords;

  /// Whether players may start a vote to kick someone.
  final bool allowVoteKick;

  /// Whether guessers may talk to each other. The drawer never can.
  ///
  /// A room setting rather than a device preference: it is something a host
  /// decides for everybody, and the server enforces it in
  /// `voiceService.assertMayUseVoice` — turning it off hangs up calls that are
  /// already open rather than only hiding a button.
  final bool voiceEnabled;

  /// Whether the text channel is open.
  ///
  /// Never affects guessing: a room with chat off still accepts guesses,
  /// because guessing is how the game is played. Wrong guesses simply are not
  /// relayed to the room.
  final bool chatEnabled;

  /// Which rule set the match runs under.
  ///
  /// The client renders the mode; the server enforces it. See [GameMode].
  final GameMode gameMode;

  /// Whether people may watch once every seat is taken.
  final bool allowSpectators;

  /// Whether only the host's friends may join by code.
  final bool friendsOnly;

  /// Narrows the word pool, or null to let the mode or room decide.
  final String? wordDifficulty;

  /// Whether the room is hidden from public listings.
  final bool isPrivate;

  /// Returns human-readable problems with these settings.
  /// An empty list means the settings are valid.
  List<String> validate() {
    final List<String> problems = <String>[];
    if (maxPlayers < 2 || maxPlayers > 12) {
      problems.add('Players must be between 2 and 12.');
    }
    if (rounds < 1 || rounds > 10) {
      problems.add('Rounds must be between 1 and 10.');
    }
    if (drawTimeSeconds < 30 || drawTimeSeconds > 180) {
      problems.add('Draw time must be between 30 and 180 seconds.');
    }
    if (wordChoiceCount < 2 || wordChoiceCount > 5) {
      problems.add('Word choices must be between 2 and 5.');
    }
    if (hintCount < 0 || hintCount > 5) {
      problems.add('Hints must be between 0 and 5.');
    }
    if (wordSelectSeconds < 5 || wordSelectSeconds > 30) {
      problems.add('Word pick time must be between 5 and 30 seconds.');
    }
    if (categories.isEmpty) {
      problems.add('Pick at least one word category.');
    }
    // A custom list is optional, but a half-filled one makes for a poor game:
    // either supply enough words to sustain a round, or none at all.
    if (customWords.isNotEmpty && customWords.length < 5) {
      problems.add('A custom word list needs at least 5 words.');
    }
    return problems;
  }

  /// Serializes these settings to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'maxPlayers': maxPlayers,
        'rounds': rounds,
        'drawTimeSeconds': drawTimeSeconds,
        'wordChoiceCount': wordChoiceCount,
        'hintCount': hintCount,
        'wordSelectSeconds': wordSelectSeconds,
        'wordMode': wordMode.name,
        'language': language.name,
        'categories': <String>[
          for (final WordCategory category in categories) category.name,
        ],
        'customWords': <String>[...customWords],
        'allowVoteKick': allowVoteKick,
        'voiceEnabled': voiceEnabled,
        'chatEnabled': chatEnabled,
        'gameMode': gameMode.wire,
        'allowSpectators': allowSpectators,
        'friendsOnly': friendsOnly,
        'wordDifficulty': wordDifficulty,
        'isPrivate': isPrivate,
      };

  /// Returns a copy with the given fields replaced.
  RoomSettings copyWith({
    int? maxPlayers,
    int? rounds,
    int? drawTimeSeconds,
    int? wordChoiceCount,
    int? hintCount,
    int? wordSelectSeconds,
    WordMode? wordMode,
    AppLanguage? language,
    Set<WordCategory>? categories,
    List<String>? customWords,
    bool? allowVoteKick,
    bool? voiceEnabled,
    bool? chatEnabled,
    GameMode? gameMode,
    bool? allowSpectators,
    bool? friendsOnly,
    String? wordDifficulty,
    bool? isPrivate,
  }) =>
      RoomSettings(
        maxPlayers: maxPlayers ?? this.maxPlayers,
        rounds: rounds ?? this.rounds,
        drawTimeSeconds: drawTimeSeconds ?? this.drawTimeSeconds,
        wordChoiceCount: wordChoiceCount ?? this.wordChoiceCount,
        hintCount: hintCount ?? this.hintCount,
        wordSelectSeconds: wordSelectSeconds ?? this.wordSelectSeconds,
        wordMode: wordMode ?? this.wordMode,
        language: language ?? this.language,
        categories: categories ?? this.categories,
        customWords: customWords ?? this.customWords,
        allowVoteKick: allowVoteKick ?? this.allowVoteKick,
        voiceEnabled: voiceEnabled ?? this.voiceEnabled,
        chatEnabled: chatEnabled ?? this.chatEnabled,
        gameMode: gameMode ?? this.gameMode,
        allowSpectators: allowSpectators ?? this.allowSpectators,
        friendsOnly: friendsOnly ?? this.friendsOnly,
        wordDifficulty: wordDifficulty ?? this.wordDifficulty,
        isPrivate: isPrivate ?? this.isPrivate,
      );

  @override
  List<Object?> get props => <Object?>[
        maxPlayers,
        rounds,
        drawTimeSeconds,
        wordChoiceCount,
        hintCount,
        wordSelectSeconds,
        wordMode,
        language,
        categories,
        customWords,
        allowVoteKick,
        voiceEnabled,
        chatEnabled,
        gameMode,
        allowSpectators,
        friendsOnly,
        wordDifficulty,
        isPrivate,
      ];

  @override
  bool get stringify => true;
}
