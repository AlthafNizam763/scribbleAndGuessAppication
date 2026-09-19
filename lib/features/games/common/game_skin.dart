import 'package:flutter/material.dart';
import 'package:scribble_guess/models/game_definition.dart';

/// The look of one game, as a small set of pigments and one gradient.
///
/// ## Why the games do not use [AppPalette]
///
/// The app's palette describes *the app* — one product, one set of surfaces,
/// consistent across every screen. That is exactly what a lobby wants and
/// exactly what a game does not. A hand of cards on green felt, a back-room
/// table under one hanging bulb and a lit corridor on a spaceship are three
/// different places, and a player should know which one they are in before
/// they have read a single word on the screen.
///
/// So a game screen owns its own pigments. Not arbitrary ones: every skin
/// below is the same six roles, so a widget written against a skin works in
/// all three games and picks up the right atmosphere by being handed a
/// different one. The shared HUD, chat panel and dialogs are written exactly
/// that way, which is why there is one of each rather than three.
///
/// The app shell keeps [AppPalette]. The boundary is the game screen.
@immutable
class GameSkin {
  const GameSkin({
    required this.gameId,
    required this.backdrop,
    required this.surface,
    required this.surfaceRaised,
    required this.edge,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.accentInk,
    required this.danger,
    required this.success,
    required this.glow,
    required this.display,
  });

  /// Which game this dresses.
  final GameId gameId;

  /// The furthest layer: the room the table is standing in.
  final List<Color> backdrop;

  /// Panels, cards and sheets that sit on the backdrop.
  final Color surface;

  /// The same, one step closer to the light. For anything raised or active.
  final Color surfaceRaised;

  /// Hairlines and rims. Always visible against both [surface] and [backdrop].
  final Color edge;

  /// Primary text on [surface].
  final Color ink;

  /// Secondary text. Never used for anything a player must read to act.
  final Color inkMuted;

  /// The one colour that means "this is the thing to press".
  final Color accent;

  /// Text and icons drawn *on* [accent].
  final Color accentInk;

  /// Refusals, penalties, eliminations.
  final Color danger;

  /// Completions, safe outcomes, wins.
  final Color success;

  /// What this game's light does: a bulb, a felt sheen, a reactor.
  ///
  /// Used for the radial wash behind the table and for the halo on whoever is
  /// on turn, which is why it is one colour and not a gradient — it is a
  /// light source, and a light source has a colour.
  final Color glow;

  /// The typeface for headings and numbers that need to feel like this game.
  ///
  /// A family name, resolved through the theme. Body text stays on the app's
  /// own family: three games with three reading faces would be unreadable as
  /// one product, and nobody needs a card table to have opinions about
  /// paragraph text.
  final String display;

  /// The skin for [gameId], or the Kazhutha one for a game with no table.
  static GameSkin of(GameId gameId) => switch (gameId) {
        GameId.kazhutha => kazhutha,
        GameId.bluffBar => bluffBar,
        GameId.spaceMystery => spaceMystery,
        GameId.ludo => ludo,
        GameId.scribbleGuess => kazhutha,
      };

  /// **Kazhutha** — a card room at night.
  ///
  /// Green baize under a low warm lamp, with the brass and oxblood of an old
  /// card table. Deliberately warm and deliberately *lit*: this is a game
  /// people play around a table with the overhead light on, and the atmosphere
  /// is companionable rather than tense. The donkey is the joke, not a threat.
  static const GameSkin kazhutha = GameSkin(
    gameId: GameId.kazhutha,
    backdrop: <Color>[Color(0xFF241A12), Color(0xFF120C08)],
    surface: Color(0xFF1C4433),
    surfaceRaised: Color(0xFF276046),
    edge: Color(0xFF7A5A32),
    ink: Color(0xFFF6ECD9),
    inkMuted: Color(0xFFB79E7C),
    accent: Color(0xFFD9A441),
    accentInk: Color(0xFF241A12),
    danger: Color(0xFFB5453A),
    success: Color(0xFF6FBF73),
    glow: Color(0xFFFFD891),
    display: 'PlusJakartaSans',
  );

  /// **Ludo** — a board on a kitchen table, in the afternoon.
  ///
  /// The one skin here that is *light*. Every other game in the product is a
  /// dark room, and Ludo is deliberately not: it is the game somebody's family
  /// plays after lunch, the board is printed card, and a dark Ludo would be a
  /// Ludo nobody recognised. The four counter colours are the four every set
  /// has been printed in for a century — see `ludoSeatColours`.
  static const GameSkin ludo = GameSkin(
    gameId: GameId.ludo,
    // A wooden table the board is lying on.
    backdrop: <Color>[Color(0xFF6A4B33), Color(0xFF3A281B)],
    // The board itself: aged card rather than white, which is what stops it
    // glaring on a phone at full brightness.
    surface: Color(0xFFF2E8D5),
    surfaceRaised: Color(0xFFFBF6EA),
    edge: Color(0xFF8A7355),
    // Ink on card, so the dark text here is correct rather than inverted.
    ink: Color(0xFF2A2119),
    inkMuted: Color(0xFF7A6A55),
    accent: Color(0xFF2E7D6B),
    accentInk: Color(0xFFFBF6EA),
    danger: Color(0xFFC0392B),
    success: Color(0xFF3FA34D),
    glow: Color(0xFFFFE9B8),
    display: 'PlusJakartaSans',
  );

  /// **Bluff Bar** — the back room, one bulb, everybody lying.
  ///
  /// Near-black with a single amber source and a cold ember red for when
  /// somebody is called. The green of the Kazhutha table is gone on purpose:
  /// this is not a card room, it is a bar where the cards happen to be, and
  /// the only warm thing in it is the light over the table.
  static const GameSkin bluffBar = GameSkin(
    gameId: GameId.bluffBar,
    backdrop: <Color>[Color(0xFF17100E), Color(0xFF070505)],
    surface: Color(0xFF241713),
    surfaceRaised: Color(0xFF34211A),
    edge: Color(0xFF5A3A2A),
    ink: Color(0xFFEDDFD2),
    inkMuted: Color(0xFF9A7E6C),
    accent: Color(0xFFE0922F),
    accentInk: Color(0xFF17100E),
    danger: Color(0xFFC6412F),
    success: Color(0xFF7FA86A),
    glow: Color(0xFFFFB454),
    display: 'SpaceGrotesk',
  );

  /// **Space Mystery** — a bright ship with dark corners.
  ///
  /// Cold blues and a cyan instrument glow, kept *colourful* rather than
  /// grim: the brief is a playful spaceship, and a social deduction game that
  /// looks like a horror game stops being funny about ten seconds in. The
  /// dread comes from the lights going out, which is why the backdrop is the
  /// only one here that is nearly black — everything drawn on it is not.
  static const GameSkin spaceMystery = GameSkin(
    gameId: GameId.spaceMystery,
    backdrop: <Color>[Color(0xFF111A2E), Color(0xFF05070F)],
    surface: Color(0xFF1B2743),
    surfaceRaised: Color(0xFF27375C),
    edge: Color(0xFF3F5686),
    ink: Color(0xFFE8F1FF),
    inkMuted: Color(0xFF8FA3C6),
    accent: Color(0xFF4CD9E8),
    accentInk: Color(0xFF05161B),
    danger: Color(0xFFE85C6B),
    success: Color(0xFF5BE0A4),
    glow: Color(0xFF6FE9F5),
    display: 'SpaceGrotesk',
  );
}

/// Reads the skin the enclosing game screen installed.
///
/// An inherited widget rather than a parameter threaded through every
/// constructor: a card knows which game it is in because of where it is, and
/// passing a skin down nine levels of layout is how a widget ends up taking a
/// skin it does not use in order to hand it to one that does.
class GameSkinScope extends InheritedWidget {
  const GameSkinScope({required this.skin, required super.child, super.key});

  final GameSkin skin;

  static GameSkin of(BuildContext context) {
    final GameSkinScope? scope =
        context.dependOnInheritedWidgetOfExactType<GameSkinScope>();
    // Falling back rather than asserting: a widget rendered in isolation — a
    // preview, a test, a dialog pushed above the game — should still draw.
    return scope?.skin ?? GameSkin.kazhutha;
  }

  @override
  bool updateShouldNotify(GameSkinScope oldWidget) => oldWidget.skin != skin;
}

/// Shorthand for reading the current skin.
extension GameSkinX on BuildContext {
  GameSkin get skin => GameSkinScope.of(this);
}
