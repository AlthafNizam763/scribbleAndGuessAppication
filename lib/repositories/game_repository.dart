import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/round_result.dart';
import 'package:scribble_guess/models/word_item.dart';

/// Match-side seam between the UI and whatever backend runs the game loop.
///
/// The server owns the entire match: the phase machine, the turn order, the
/// countdown, the secret word, correct-answer detection and every score. This
/// interface therefore exposes exactly three *requests* and four read-only
/// streams. An implementation must never advance a phase, award a point or
/// start a timer on its own — it renders what the server pushed.
///
/// Word secrecy is part of that contract: `GameState.word` is populated only
/// for the drawer, or for everybody once the round has ended. Non-drawers see
/// `GameState.maskedWord` plus `GameState.hintIndices`, and an implementation
/// must never reconstruct the answer from any other source.
///
/// Timing is server-authoritative too. `GameState.turnStartMs` and
/// `GameState.turnEndMs` are stamps on the *server* clock, so they must be
/// compared against `RealtimeGateway.serverTimeMs`, never `DateTime.now()`.
///
/// No method throws. Failures are returned as [Err] carrying a [Failure].
abstract interface class GameRepository {
  /// Server-authoritative snapshots of the current match.
  ///
  /// Emits on every phase change, turn change, hint reveal and score update.
  /// Replays the latest snapshot to new listeners, and starts from
  /// `GameState.initial` before the first push. Completes only on [dispose].
  Stream<GameState> get gameStream;

  /// The word choices offered to the drawer at the start of a turn.
  ///
  /// Emitted only on the drawing device; every other client never receives
  /// this list. The index of the chosen entry is what [selectWord] sends back.
  Stream<List<WordItem>> get wordChoicesStream;

  /// The scored summary pushed when a turn ends.
  ///
  /// Carries the revealed word, the per-player deltas and the running totals
  /// exactly as the server computed them; the client displays these numbers
  /// rather than recomputing them with `ScoringService`.
  Stream<RoundResult> get roundResultStream;

  /// The final standings pushed when the last round ends.
  ///
  /// Emits once per match, after which the room returns to a waiting state and
  /// the host may call [playAgain].
  Stream<GameResult> get gameResultStream;

  /// Asks the server to start the match. Host only.
  ///
  /// The server checks the host role and the readiness and player-count
  /// preconditions itself, so an [Ok] means the request was accepted, not that
  /// any particular phase is already active — watch [gameStream] for that.
  ///
  /// Fails with [AppErrorCode.notHost], [AppErrorCode.invalidAction] (too few
  /// players, or a match already running), or a transport code.
  Future<Result<void>> startGame();

  /// Picks the word at [index] of the latest [wordChoicesStream] list.
  /// Drawer only.
  ///
  /// Only the index travels, never the word text, so a tampered client cannot
  /// inject a word of its own. The server re-checks that the caller is the
  /// current drawer and that the phase is word selection; if the drawer never
  /// chooses, the server picks for them when the selection timer expires.
  ///
  /// Fails with [AppErrorCode.notDrawer], [AppErrorCode.invalidAction] for an
  /// out-of-range index or a stale phase, or a transport code.
  Future<Result<void>> selectWord(int index);

  /// Asks the server to run another match with the same players. Host only.
  ///
  /// Valid only after [gameResultStream] has emitted; the server resets scores
  /// and turn order. Fails with [AppErrorCode.notHost] or
  /// [AppErrorCode.invalidAction] while a match is still running.
  Future<Result<void>> playAgain();

  /// Releases subscriptions and closes all four streams.
  ///
  /// Safe to call more than once; the instance is unusable afterwards.
  void dispose();
}
