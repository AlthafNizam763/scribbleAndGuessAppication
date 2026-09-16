import 'package:scribble_guess/models/json_utils.dart';

/// Which rule set a match runs under.
///
/// ## The client renders these; it does not enforce them
///
/// Every rule a mode implies — the timer, the hint count, the word pool, who
/// may draw, what a stroke's colour is allowed to be — is applied by the
/// server. What this enum is for is telling the player which game they are in
/// and shaping the UI around it: hiding the colour palette in One Colour,
/// hiding the canvas from the drawer in Blind.
///
/// A mode this build does not recognise falls back to [classic] rather than
/// throwing, which is what lets the server ship a tenth mode before every
/// installed app knows about it.
enum GameMode {
  classic('classic', 'Classic', 'Draw and guess, the usual way.'),
  speed('speed', 'Speed', 'Half the time, one hint, same points.'),
  team('team', 'Team', 'Two sides. Your points go to your team.'),
  duo('duo', 'Duo', 'Just the two of you, taking turns.'),
  challenge('challenge', 'Challenge', 'Hard words only.'),
  noHint('no_hint', 'No Hint', 'No letters, no word length. Read the drawing.'),
  oneColor('one_color', 'One Colour', 'One colour for the whole turn.'),
  blind('blind', 'Blind Drawing', 'The drawer cannot see what they drew.'),
  relay('relay', 'Relay', 'Each drawer adds to the picture before them.');

  const GameMode(this.wire, this.label, this.description);

  /// The string the server sends. Mirrors its `GAME_MODE`.
  final String wire;

  /// Display name.
  final String label;

  /// One line explaining what changes.
  final String description;

  /// Parses [value], falling back to [classic].
  static GameMode parse(dynamic value) {
    final String raw = asString(value);
    for (final GameMode mode in GameMode.values) {
      if (mode.wire == raw) return mode;
    }
    return GameMode.classic;
  }

  /// Whether the drawer is denied sight of their own canvas.
  ///
  /// The authoritative answer arrives on the game state as `drawerSeesBoard`;
  /// this is here so a room-settings preview can describe the mode before a
  /// match exists to ask.
  bool get blindsDrawer => this == GameMode.blind;

  /// Whether the palette is pointless because the turn is locked to one colour.
  bool get locksColor => this == GameMode.oneColor;

  /// Whether players are split into sides.
  bool get hasTeams => this == GameMode.team;

  /// Whether the canvas carries over between turns.
  bool get keepsBoard => this == GameMode.relay;

  /// Whether results count towards the global leaderboard.
  ///
  /// Team and Duo do not: a team score belongs to a side, and Duo splits
  /// between two a pot four would share, so folding either into the world
  /// board would rank modes rather than players. Both still pay XP.
  bool get ranked => this != GameMode.team && this != GameMode.duo;
}

/// Which side a player is on. `none` outside a team mode.
enum Team {
  none('none', 'No team'),
  red('red', 'Red'),
  blue('blue', 'Blue');

  const Team(this.wire, this.label);

  final String wire;
  final String label;

  /// Parses [value], falling back to [none].
  static Team parse(dynamic value) {
    final String raw = asString(value);
    for (final Team team in Team.values) {
      if (team.wire == raw) return team;
    }
    return Team.none;
  }

  /// Whether this is a real side rather than the absence of one.
  bool get isAssigned => this != Team.none;
}
