import 'package:scribble_guess/core/constants/game_defaults.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/room.dart';

/// The legal shape of the game loop.
///
/// The server owns phase changes; this mirror lets the client reject bogus
/// payloads and lets the practice backend drive the very same lifecycle:
/// `lobby -> starting -> wordSelection -> drawing -> roundEnd ->
/// (wordSelection | gameEnd) -> lobby`.
abstract final class RoomStateMachine {
  /// Whether moving from [from] to [to] is a legal phase change.
  ///
  /// Returning to [GamePhase.lobby] is always allowed — that is a room reset,
  /// which can happen at any point. Staying put is never a transition.
  static bool canTransition(GamePhase from, GamePhase to) {
    if (from == to) {
      return false;
    }
    if (to == GamePhase.lobby) {
      return true;
    }
    // A game can be put on hold from any live phase — the room can lose a
    // player at any moment — and it comes back through the same countdown a
    // fresh match starts with.
    if (to == GamePhase.paused) {
      return from != GamePhase.lobby && from != GamePhase.gameEnd;
    }
    if (from == GamePhase.paused) {
      return to == GamePhase.starting;
    }
    return switch (from) {
      GamePhase.lobby => to == GamePhase.starting,
      GamePhase.starting => to == GamePhase.wordSelection,
      GamePhase.wordSelection => to == GamePhase.drawing,
      GamePhase.drawing => to == GamePhase.roundEnd,
      GamePhase.roundEnd =>
        to == GamePhase.wordSelection || to == GamePhase.gameEnd,
      GamePhase.gameEnd => false,
      // Handled above; a paused game only ever resumes into the countdown.
      GamePhase.paused => false,
    };
  }

  /// The phase that follows [current] once its work is done.
  ///
  /// After a turn ends the game moves to the next drawer while [turnIndex]
  /// still has seats left in [playerCount], starts the next round while
  /// [currentRound] is below [totalRounds], and otherwise finishes.
  static GamePhase next({
    required GamePhase current,
    required int currentRound,
    required int totalRounds,
    required int turnIndex,
    required int playerCount,
  }) =>
      switch (current) {
        GamePhase.lobby => GamePhase.starting,
        GamePhase.starting => GamePhase.wordSelection,
        GamePhase.wordSelection => GamePhase.drawing,
        GamePhase.drawing => GamePhase.roundEnd,
        GamePhase.roundEnd => _afterRoundEnd(
            currentRound: currentRound,
            totalRounds: totalRounds,
            turnIndex: turnIndex,
            playerCount: playerCount,
          ),
        GamePhase.gameEnd => GamePhase.lobby,
        // Waiting on players, not on a clock: only an arrival moves this on,
        // and the server decides when.
        GamePhase.paused => GamePhase.paused,
      };

  /// Whether [room] may start a game right now.
  ///
  /// Needs at least [GameDefaults.minPlayersToStart] seated players, a room
  /// still waiting in the lobby, and every player but the host marked ready.
  static bool canStart(Room room) {
    if (room.status != RoomStatus.waiting) {
      return false;
    }
    if (room.players.length < GameDefaults.minPlayersToStart) {
      return false;
    }
    for (final Player player in room.players) {
      if (player.isHost || room.isHost(player.id)) {
        continue;
      }
      if (!player.isReady) {
        return false;
      }
    }
    return true;
  }

  /// Whether another turn or another round follows the turn that just ended.
  static GamePhase _afterRoundEnd({
    required int currentRound,
    required int totalRounds,
    required int turnIndex,
    required int playerCount,
  }) {
    final int seats = playerCount < 0 ? 0 : playerCount;
    if (turnIndex + 1 < seats) {
      return GamePhase.wordSelection;
    }
    return currentRound < totalRounds
        ? GamePhase.wordSelection
        : GamePhase.gameEnd;
  }
}
