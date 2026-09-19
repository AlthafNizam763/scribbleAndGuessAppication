import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/providers/sound_provider.dart';
import 'package:scribble_guess/services/sound_service.dart';

/// One game's voice, as a named set of moments.
///
/// ## Why this exists rather than `SoundEffect` at each call site
///
/// The brief asks that audio not be duplicated inside every game, and the
/// literal reading — "call the shared service from each screen" — is what the
/// screens were already doing. The duplication it actually prevents is
/// *this*: three copies of the decision that a turn change is
/// `kazhuthaTurn` here and `ludoTurn` there, scattered through three widget
/// trees and wrong in one of them within a month.
///
/// So a screen asks for the moment — "somebody's turn started" — and this
/// answers with the sound for the game it belongs to. Adding a game means one
/// entry here rather than a search through its screens.
///
/// ## Why it is not an interface
///
/// Because there is no behaviour. It is a lookup table with a warm-up, and the
/// warm-up is the only reason it is a class at all.
class GameAudio {
  const GameAudio._(this.gameId, this._service);

  /// The voice for [gameId], bound to the shared service.
  factory GameAudio.of(WidgetRef ref, GameId gameId) =>
      GameAudio._(gameId, ref.read(soundServiceProvider));

  final GameId gameId;
  final SoundService _service;

  /// Unpacks this game's folder. Call once, when the screen opens.
  Future<void> warmUp() => _service.warmUpGame(_folder);

  String get _folder => switch (gameId) {
    GameId.kazhutha => 'kazhutha/audio',
    GameId.bluffBar => 'bluff_bar/audio',
    GameId.spaceMystery => 'space_mystery/audio',
    GameId.ludo => 'ludo/audio',
    // Scribble's sounds are the shared set; it has no folder of its own.
    GameId.scribbleGuess => 'sounds',
  };

  void play(SoundEffect effect) => _service.play(effect);

  // ---------------------------------------------------------- the moments --

  /// The turn passed to somebody. [mine] when it passed to this player.
  void turnChanged({required bool mine}) {
    final SoundEffect? effect = switch (gameId) {
      GameId.kazhutha => SoundEffect.kazhuthaTurn,
      GameId.ludo => SoundEffect.ludoTurn,
      // Bluff Bar's turn is announced by the deal and the claim, and a third
      // sound on top of those is noise.
      GameId.bluffBar => mine ? SoundEffect.bluffDeal : null,
      _ => mine ? SoundEffect.yourTurn : SoundEffect.turnStart,
    };
    if (effect != null) _service.play(effect);
  }

  /// This game's arrival sting — the sound of the room, played once.
  void arrive() {
    final SoundEffect? effect = switch (gameId) {
      GameId.bluffBar => SoundEffect.bluffAmbience,
      GameId.spaceMystery => SoundEffect.spaceAmbience,
      GameId.kazhutha => SoundEffect.kazhuthaShuffle,
      _ => null,
    };
    if (effect != null) _service.play(effect);
  }

  /// A card left somebody's hand.
  void cardDrawn() => _service.play(switch (gameId) {
    GameId.kazhutha => SoundEffect.kazhuthaDraw,
    _ => SoundEffect.tap,
  });

  /// A card left *your* hand — somebody picked it off you.
  ///
  /// Its own sound because it is the one thing at a Kazhutha table that
  /// happens *to* a player rather than being done by one, and a table where
  /// losing a card sounds exactly like taking one is a table you cannot follow
  /// without watching every fan.
  void cardTaken() => _service.play(switch (gameId) {
    GameId.kazhutha => SoundEffect.kazhuthaPlace,
    _ => SoundEffect.tap,
  });

  /// A pair went down, or a claim was laid.
  void cardPlayed() => _service.play(switch (gameId) {
    GameId.kazhutha => SoundEffect.kazhuthaPair,
    GameId.bluffBar => SoundEffect.bluffDeal,
    _ => SoundEffect.tap,
  });

  /// Somebody paid to see the truth.
  void revealed() => _service.play(switch (gameId) {
    GameId.bluffBar => SoundEffect.bluffReveal,
    GameId.kazhutha => SoundEffect.kazhuthaDonkey,
    _ => SoundEffect.roundEnd,
  });

  /// Somebody called a bluff.
  void challenged() => _service.play(SoundEffect.bluffCall);

  /// You have been called out, and the cards are about to turn.
  ///
  /// Only ever heard by the player whose claim is being challenged. Everybody
  /// else hears [challenged] — watching a call and being on the end of one are
  /// not the same moment, and in a bluffing game the difference is the game.
  void tension() => _service.play(SoundEffect.bluffTension);

  /// The reactor is about to go, and the ship is counting.
  ///
  /// Fires once per sabotage, in its last ten seconds. Not a tick per second:
  /// a countdown that chirps ten times drowns the alarm it is warning about.
  void countdown() => _service.play(SoundEffect.spaceCountdown);

  /// Somebody is out — a glass, an airlock, a capture.
  void eliminated() => _service.play(switch (gameId) {
    GameId.bluffBar => SoundEffect.bluffElimination,
    GameId.spaceMystery => SoundEffect.spaceElimination,
    GameId.ludo => SoundEffect.ludoCapture,
    _ => SoundEffect.playerLeft,
  });

  /// The die was thrown. The number on it came from the server.
  void diceRolled() => _service.play(SoundEffect.ludoDice);

  /// A counter stepped.
  void counterMoved() => _service.play(SoundEffect.ludoMove);

  /// A counter reached the middle.
  void counterHome() => _service.play(SoundEffect.ludoHome);

  /// A counter came to rest on a star, where nothing can take it.
  ///
  /// Its own sound rather than the ordinary step, because reaching a safe
  /// square is the one move in Ludo that changes nothing on the scoreboard and
  /// everything about the risk — and that is worth hearing.
  void counterSafe() => _service.play(SoundEffect.ludoSafe);

  /// A console finished.
  void taskDone() => _service.play(SoundEffect.spaceTaskDone);

  /// The alarm.
  void emergency() => _service.play(SoundEffect.spaceEmergency);

  /// Everybody to the table.
  void meeting() => _service.play(SoundEffect.spaceMeeting);

  /// A vote landed.
  void voted() => _service.play(SoundEffect.spaceVote);

  /// Something was pulled.
  void sabotage() => _service.play(SoundEffect.spaceSabotage);

  /// The match ended. [won] decides which way it lands.
  void finished({required bool won}) => _service.play(switch ((gameId, won)) {
    (GameId.kazhutha, true) => SoundEffect.kazhuthaWin,
    (GameId.kazhutha, false) => SoundEffect.kazhuthaLose,
    (GameId.bluffBar, true) => SoundEffect.bluffWin,
    (GameId.bluffBar, false) => SoundEffect.bluffLose,
    (GameId.spaceMystery, true) => SoundEffect.spaceSuccess,
    (GameId.spaceMystery, false) => SoundEffect.spaceFailure,
    (GameId.ludo, true) => SoundEffect.ludoVictory,
    _ => SoundEffect.gameEnd,
  });

  /// A button. Each game's is its own, which is most of why they feel
  /// different to be in.
  void click() => _service.play(switch (gameId) {
    GameId.kazhutha => SoundEffect.kazhuthaClick,
    GameId.bluffBar => SoundEffect.bluffClick,
    GameId.spaceMystery => SoundEffect.spaceClick,
    GameId.ludo => SoundEffect.ludoClick,
    _ => SoundEffect.tap,
  });
}

/// The voice for whichever game a screen belongs to.
///
/// A family rather than a single provider because two games can briefly be
/// alive at once — a result overlay under a lobby that has already moved on —
/// and each should keep its own.
final ProviderFamily<GameAudio, GameId> gameAudioProvider =
    Provider.family<GameAudio, GameId>(
      (Ref ref, GameId gameId) =>
          GameAudio._(gameId, ref.read(soundServiceProvider)),
    );
