import 'package:flutter/material.dart';

/// Stable IDs shared with the backend. Never use a display label as an ID.
enum GameId {
  scribbleGuess('SCRIBBLE_GUESS'),
  kazhutha('KAZHUTHA'),
  bluffBar('BLUFF_BAR'),
  spaceMystery('SPACE_MYSTERY'),
  ludo('LUDO');

  const GameId(this.wire);
  final String wire;

  static GameId? fromWire(String value) {
    for (final GameId gameId in values) {
      if (gameId.wire == value) return gameId;
    }
    return null;
  }
}

enum GameStatus { live, comingSoon }

@immutable
class GameDefinition {
  const GameDefinition({
    required this.gameId,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.banner,
    required this.minPlayers,
    required this.maxPlayers,
    required this.supportsBots,
    required this.supportsVoice,
    required this.supportsTextChat,
    required this.route,
    required this.status,
    required this.version,
    required this.rules,
    required this.color,
  });

  final GameId gameId;
  final String displayName;
  final String description;
  /// A semantic asset location for future bitmap artwork.
  final String icon;
  final String banner;
  final int minPlayers;
  final int maxPlayers;
  final bool supportsBots;
  final bool supportsVoice;
  final bool supportsTextChat;
  final String route;
  final GameStatus status;
  final int version;
  final List<String> rules;
  final Color color;
}

/// The client fallback catalogue. `/api/games` mirrors this list exactly.
///
/// [GameDefinition.supportsBots] means **PLAY WITH STUPID works today**, not
/// that it is planned: the home card and the lobby render that button straight
/// from the flag, so a game that claims bots it cannot play ships a button that
/// does nothing.
///
/// All five now qualify. Bluff Bar and Space Mystery were held back on the
/// grounds that a bluffing bot has no read on the table and that social
/// deduction *is* the conversation — both fair, and both now answered on the
/// server: the bluffing bot counts the shoe, which is public, and the ship's
/// bots walk about, do tasks, notice who was standing over the body and vote on
/// it, each from its own line of sight and nothing else.
abstract final class GameCatalog {
  static const List<GameDefinition> all = <GameDefinition>[
    GameDefinition(
      gameId: GameId.scribbleGuess, displayName: 'Scribble & Guess',
      description: 'Draw the secret word. Guess it first.', icon: 'assets/games/scribble_guess_icon.png', banner: 'assets/games/scribble_guess_banner.png',
      minPlayers: 2, maxPlayers: 12, supportsBots: true, supportsVoice: true, supportsTextChat: true,
      route: '/games/SCRIBBLE_GUESS', status: GameStatus.live, version: 1,
      rules: <String>['Draw your word', 'Guess quickly', 'Top score wins'], color: Color(0xFFFF4D7D),
    ),
    GameDefinition(
      gameId: GameId.kazhutha, displayName: 'Kazhutha',
      description: 'Lay down your pairs. Do not be left with the queen.', icon: 'assets/games/kazhutha_icon.png', banner: 'assets/games/kazhutha_banner.png',
      minPlayers: 2, maxPlayers: 6, supportsBots: true, supportsVoice: true, supportsTextChat: true,
      route: '/games/KAZHUTHA', status: GameStatus.live, version: 1,
      rules: <String>['Draw from another hand', 'Lay down every pair', 'Avoid the queen of spades'], color: Color(0xFFFFB020),
    ),
    GameDefinition(
      gameId: GameId.bluffBar, displayName: 'Bluff Bar',
      description: 'Make a claim—or call the bluff.', icon: 'assets/games/bluff_bar_icon.png', banner: 'assets/games/bluff_bar_banner.png',
      minPlayers: 2, maxPlayers: 6, supportsBots: true, supportsVoice: true, supportsTextChat: true,
      route: '/games/BLUFF_BAR', status: GameStatus.live, version: 1,
      rules: <String>['Claim the called rank', 'Call a liar to turn the cards over', 'Whoever is wrong drinks'], color: Color(0xFF9B5CFF),
    ),
    GameDefinition(
      gameId: GameId.spaceMystery, displayName: 'Space Mystery',
      description: 'Repair the station. Find the saboteur.', icon: 'assets/games/space_mystery_icon.png', banner: 'assets/games/space_mystery_banner.png',
      minPlayers: 4, maxPlayers: 10, supportsBots: true, supportsVoice: true, supportsTextChat: true,
      route: '/games/SPACE_MYSTERY', status: GameStatus.live, version: 1,
      rules: <String>['Finish the repairs', 'Report a body to call a meeting', 'Your role is yours alone'], color: Color(0xFF4D8BFF),
    ),
    GameDefinition(
      gameId: GameId.ludo, displayName: 'Ludo',
      description: 'Roll, race home, and capture tokens.', icon: 'assets/games/ludo_icon.png', banner: 'assets/games/ludo_banner.png',
      minPlayers: 2, maxPlayers: 4, supportsBots: true, supportsVoice: true, supportsTextChat: true,
      route: '/games/LUDO', status: GameStatus.live, version: 1,
      rules: <String>['Server rolls dice', 'Capture safely', 'Bring four tokens home'], color: Color(0xFF2FD07B),
    ),
  ];

  static GameDefinition byId(GameId gameId) =>
      all.firstWhere((GameDefinition game) => game.gameId == gameId);
}
