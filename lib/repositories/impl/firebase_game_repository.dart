import 'dart:async';

import 'package:scribble_guess/core/errors/app_exception.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/player_score.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/round_result.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/repositories/game_repository.dart';
import 'package:scribble_guess/repositories/room_repository.dart';
import 'package:scribble_guess/services/firestore_service.dart';
import 'package:scribble_guess/services/game_service.dart';

/// [GameRepository] backed by Firestore and callable Cloud Functions.
///
/// The match state arrives as Firestore snapshots of `rooms/{id}.game`, which
/// the server is the only writer of. This class adds exactly two behaviours on
/// top of relaying them:
///
///  * it fetches the drawer's word choices when the phase turns to word
///    selection, because those deliberately are *not* in any document a client
///    can read (§18); and
///  * it nudges the server when a deadline passes, so a round still ends
///    promptly if the scheduled task were ever lost. The nudge cannot end a
///    round early — the server checks its own clock (§29).
class FirebaseGameRepository implements GameRepository {
  FirebaseGameRepository({
    required GameService service,
    required FirestoreService firestore,
    required RoomRepository rooms,
    required String userId,
  })  : _service = service,
        _firestore = firestore,
        _rooms = rooms,
        _userId = userId {
    _roomSubscription = _rooms.roomStream.listen(_onRoom);
  }

  final GameService _service;
  final FirestoreService _firestore;
  final RoomRepository _rooms;
  final String _userId;

  final StreamController<GameState> _states =
      StreamController<GameState>.broadcast();
  final StreamController<List<WordItem>> _choices =
      StreamController<List<WordItem>>.broadcast();
  final StreamController<RoundResult> _roundResults =
      StreamController<RoundResult>.broadcast();
  final StreamController<GameResult> _gameResults =
      StreamController<GameResult>.broadcast();

  StreamSubscription<Room>? _roomSubscription;
  StreamSubscription<GameState>? _gameSubscription;
  StreamSubscription<RoundResult?>? _roundSubscription;
  Timer? _deadlineTimer;

  String? _roomId;
  GameState _latest = GameState.initial;
  List<Player> _players = const <Player>[];
  int _choicesForTurn = -1;
  int _resultForTurn = -1;
  bool _finalEmitted = false;
  bool _disposed = false;

  @override
  Stream<GameState> get gameStream => _states.stream;

  @override
  Stream<List<WordItem>> get wordChoicesStream => _choices.stream;

  @override
  Stream<RoundResult> get roundResultStream => _roundResults.stream;

  @override
  Stream<GameResult> get gameResultStream => _gameResults.stream;

  @override
  Future<Result<void>> startGame() =>
      _withRoom(_service.startGame);

  @override
  Future<Result<void>> selectWord(int index) =>
      _withRoom((String id) => _service.selectWord(id, index));

  @override
  Future<Result<void>> playAgain() =>
      _withRoom(_service.restartGame);

  /// Re-targets every subscription when the joined room changes.
  void _onRoom(Room room) {
    _players = room.players;

    if (room.id == _roomId) return;
    _roomId = room.id;

    unawaited(_gameSubscription?.cancel());
    unawaited(_roundSubscription?.cancel());
    _choicesForTurn = -1;
    _resultForTurn = -1;
    _finalEmitted = false;

    _gameSubscription = _firestore.watchGameState(room.id).listen(
      _onGameState,
      onError: _logStreamFailure,
    );

    _roundSubscription = _firestore.watchLatestRound(room.id).listen(
      (RoundResult? result) {
        if (result == null) return;
        if (result.round == _resultForTurn) return;
        _resultForTurn = result.round;
        if (!_roundResults.isClosed) _roundResults.add(result);
      },
      onError: _logStreamFailure,
    );
  }

  void _onGameState(GameState state) {
    _latest = state;
    if (!_states.isClosed) _states.add(state);

    if (state.phase == GamePhase.wordSelection) {
      _maybeFetchChoices(state);
    }
    if (state.phase == GamePhase.gameEnd) {
      _emitFinalResult();
    }
    _armDeadline(state);
  }

  /// Fetches the word list, but only for the drawer and only once per turn.
  ///
  /// Any other client calling this would simply be refused by the server; not
  /// calling it at all is better still, since it saves a round trip that was
  /// always going to fail.
  void _maybeFetchChoices(GameState state) {
    if (state.drawerId != _userId) return;
    if (state.turnIndex == _choicesForTurn) return;
    _choicesForTurn = state.turnIndex;

    unawaited(() async {
      final String? roomId = _roomId;
      if (roomId == null) return;
      try {
        final WordChoices choices = await _service.getWordChoices(roomId);
        // A slow response can arrive after the turn moved on; discard it
        // rather than offering words for a round that already started.
        if (choices.turnIndex != _latest.turnIndex) return;
        if (!_choices.isClosed) _choices.add(choices.choices);
      } on Object catch (error) {
        AppLogger.w('could not fetch word choices', error);
        _choicesForTurn = -1;
      }
    }());
  }

  /// Builds the final standings from the player documents.
  ///
  /// The scores are the server's own totals, read back rather than recomputed:
  /// this class never adds up a point of its own.
  void _emitFinalResult() {
    if (_finalEmitted || _players.isEmpty) return;
    _finalEmitted = true;

    final List<Player> ranked = <Player>[..._players]
      ..sort((Player a, Player b) => b.score.compareTo(a.score));

    final List<PlayerScore> standings = <PlayerScore>[
      for (int i = 0; i < ranked.length; i++)
        PlayerScore(
          playerId: ranked[i].id,
          name: ranked[i].name,
          avatarId: ranked[i].avatarId,
          avatarColorIndex: ranked[i].avatarColorIndex,
          score: ranked[i].score,
          // Equal scores share a rank, so a tie reads as a tie.
          rank: i > 0 && ranked[i].score == ranked[i - 1].score
              ? _rankOf(ranked, i)
              : i + 1,
        ),
    ];

    if (!_gameResults.isClosed) {
      _gameResults.add(
        GameResult(
          roomCode: _rooms.currentRoom?.code ?? '',
          standings: standings,
          totalRounds: _latest.totalRounds,
        ),
      );
    }
  }

  /// The shared rank for a run of equal scores.
  int _rankOf(List<Player> ranked, int index) {
    int first = index;
    while (first > 0 && ranked[first - 1].score == ranked[index].score) {
      first--;
    }
    return first + 1;
  }

  /// Schedules a nudge for just after the current phase's deadline.
  ///
  /// This is a fallback, not the clock. The server ends rounds on its own
  /// schedule; this only matters if that task were dropped, and it is written
  /// so that firing early or twice is harmless.
  void _armDeadline(GameState state) {
    _deadlineTimer?.cancel();
    if (state.turnEndMs <= 0) return;

    final bool endsRound = state.phase == GamePhase.drawing ||
        state.phase == GamePhase.wordSelection;
    final bool advances = state.phase == GamePhase.roundEnd;
    if (!endsRound && !advances) return;

    final int delay =
        state.turnEndMs - DateTime.now().millisecondsSinceEpoch + 1500;
    _deadlineTimer = Timer(
      Duration(milliseconds: delay.clamp(500, 300000)),
      () async {
        final String? roomId = _roomId;
        if (roomId == null) return;
        try {
          if (endsRound) {
            await _service.endRound(roomId);
          } else {
            await _service.nextRound(roomId);
          }
        } on Object catch (error) {
          AppLogger.d('deadline nudge ignored', error);
        }
      },
    );
  }

  /// A stream error here is not actionable by the player: the subscription
  /// retries on its own, and the last good snapshot stays on screen.
  static void _logStreamFailure(Object error, StackTrace stack) {
    AppLogger.w('game stream failed', error, stack);
  }

  Future<Result<void>> _withRoom(
    Future<void> Function(String roomId) action,
  ) async {
    final String? roomId = _roomId ?? _rooms.currentRoom?.id;
    if (roomId == null || roomId.isEmpty) {
      return const Err<void>(
        Failure(AppErrorCode.invalidAction, 'You are not in a room.'),
      );
    }
    try {
      await action(roomId);
      return const Ok<void>(null);
    } on AppException catch (error) {
      return Err<void>(error.failure);
    } on Object catch (error, stack) {
      return Err<void>(toAppException(error, stack).failure);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _deadlineTimer?.cancel();
    unawaited(_roomSubscription?.cancel());
    unawaited(_gameSubscription?.cancel());
    unawaited(_roundSubscription?.cancel());
    unawaited(_states.close());
    unawaited(_choices.close());
    unawaited(_roundResults.close());
    unawaited(_gameResults.close());
  }
}
