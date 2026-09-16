import 'dart:async';

import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/replay_stream.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/round_result.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/repositories/game_repository.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// The gateway's inbound record, aliased for readability.
typedef _Inbound = ({String event, Map<String, dynamic> data});

/// [GameRepository] backed by a [RealtimeGateway].
///
/// The server owns the match; this class only decodes what it pushes. It keeps
/// the last [GameState] so that partial pushes — above all `s:game:hint`,
/// which carries nothing but the new mask — are merged onto the known state
/// instead of replacing it with a half-empty snapshot.
///
/// Merging is key-driven, not null-driven: a field present in the payload
/// wins (an explicit `null` clears it), a field absent from the payload keeps
/// its cached value. The secret word is the one exception — it is carried over
/// only while the turn is unchanged, so an answer can never survive into
/// somebody else's turn just because the server stopped sending it.
///
/// ## Why all four streams replay
///
/// Every one of these events is pushed at a phase boundary, and a phase
/// boundary is exactly when the client is busy changing screens. The word
/// choices go out as a turn opens, while the drawer may still be looking at
/// the previous round's scoreboard; the round result goes out with the phase
/// change that *causes* the results screen to be pushed. A plain broadcast
/// stream has no listener until the screen that wants it is built, so in both
/// cases the payload is delivered into an empty room and is gone — the drawer
/// never gets a word to choose, and the results screen spins forever under a
/// heading with no word beneath it.
///
/// So the last value of each stream is kept and replayed to every new
/// listener, and the subscription is wired up in `onListen` — synchronously,
/// with no `async*` gap between replaying the cached value and attaching to
/// the live one, which is its own way to drop an event.
///
/// A malformed payload is logged and dropped; it never breaks the gateway
/// subscription and never reaches the UI.
class SocketGameRepository implements GameRepository {
  /// Starts listening to [gateway] for match traffic.
  SocketGameRepository(RealtimeGateway gateway) : _gateway = gateway {
    _inboundSubscription = _gateway.inbound.listen(
      _onInbound,
      onError: _onStreamError,
    );
  }

  final RealtimeGateway _gateway;

  final StreamController<GameState> _gameController =
      StreamController<GameState>.broadcast();
  final StreamController<List<WordItem>> _wordChoicesController =
      StreamController<List<WordItem>>.broadcast();
  final StreamController<RoundResult> _roundResultController =
      StreamController<RoundResult>.broadcast();
  final StreamController<GameResult> _gameResultController =
      StreamController<GameResult>.broadcast();

  StreamSubscription<_Inbound>? _inboundSubscription;

  GameState _state = GameState.initial;
  List<WordItem> _choices = const <WordItem>[];
  RoundResult? _lastRoundResult;
  GameResult? _lastGameResult;
  bool _disposed = false;

  @override
  Stream<GameState> get gameStream =>
      replaying<GameState>(_gameController, () => _state);

  @override
  Stream<List<WordItem>> get wordChoicesStream => replaying<List<WordItem>>(
        _wordChoicesController,
        () => _choices.isEmpty ? null : _choices,
      );

  @override
  Stream<RoundResult> get roundResultStream =>
      replaying<RoundResult>(_roundResultController, () => _lastRoundResult);

  @override
  Stream<GameResult> get gameResultStream =>
      replaying<GameResult>(_gameResultController, () => _lastGameResult);

  /// The most recent state, mirroring the last value of [gameStream].
  GameState get currentState => _state;

  @override
  Future<Result<void>> startGame() async =>
      _asVoid(await _gateway.request(SocketEvents.clientGameStart));

  @override
  Future<Result<void>> selectWord(int index) async {
    if (index < 0 || (_choices.isNotEmpty && index >= _choices.length)) {
      return const Err<void>(
        Failure(AppErrorCode.invalidAction, AppStrings.errorInvalidAction),
      );
    }
    return _asVoid(
      await _gateway.request(
        SocketEvents.clientGameSelectWord,
        <String, dynamic>{'index': index},
      ),
    );
  }

  @override
  Future<Result<void>> playAgain() async =>
      _asVoid(await _gateway.request(SocketEvents.clientGamePlayAgain));

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_inboundSubscription?.cancel());
    _inboundSubscription = null;
    _choices = const <WordItem>[];
    _lastRoundResult = null;
    _lastGameResult = null;
    unawaited(_gameController.close());
    unawaited(_wordChoicesController.close());
    unawaited(_roundResultController.close());
    unawaited(_gameResultController.close());
  }

  // ---------------------------------------------------------------------------
  // Inbound
  // ---------------------------------------------------------------------------

  void _onInbound(_Inbound message) {
    switch (message.event) {
      case SocketEvents.serverGameState:
        _handleGameState(message.data);
      case SocketEvents.serverGameRoundStart:
        _handleRoundStart(message.data);
      case SocketEvents.serverGameWordChoices:
        _handleWordChoices(message.data);
      case SocketEvents.serverGameHint:
        _handleHint(message.data);
      case SocketEvents.serverGameRoundEnd:
        _handleRoundEnd(message.data);
      case SocketEvents.serverGameEnd:
        _handleGameEnd(message.data);
    }
  }

  void _handleGameState(Map<String, dynamic> data) {
    try {
      _emitState(_merged(_gamePayload(data)));
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketGameRepository: dropped malformed game state',
        error,
        stackTrace,
      );
    }
  }

  /// A new turn resets the state wholesale: nothing from the previous turn —
  /// least of all its word — may leak into the new one.
  void _handleRoundStart(Map<String, dynamic> data) {
    try {
      final GameState next = GameState.fromJson(_gamePayload(data));
      // The previous turn's choices and scoreboard must not be replayed into
      // this one: a screen built a moment from now would show last turn's word.
      _choices = const <WordItem>[];
      _lastRoundResult = null;
      _lastGameResult = null;
      _emitState(next);
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketGameRepository: dropped malformed round start',
        error,
        stackTrace,
      );
    }
  }

  void _handleWordChoices(Map<String, dynamic> data) {
    try {
      final List<WordItem> choices = <WordItem>[
        for (final dynamic raw in asList(data['choices']))
          WordItem.fromJson(asMap(raw)),
      ];
      if (choices.isEmpty) {
        AppLogger.w('SocketGameRepository: dropped empty word choices');
        return;
      }
      _choices = List<WordItem>.unmodifiable(choices);
      if (!_disposed && !_wordChoicesController.isClosed) {
        _wordChoicesController.add(_choices);
      }
      _emitState(_state.copyWith(wordChoices: _choices));
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketGameRepository: dropped malformed word choices',
        error,
        stackTrace,
      );
    }
  }

  /// Patches the revealed letters onto the cached state and re-emits it.
  void _handleHint(Map<String, dynamic> data) {
    try {
      final List<int> hintIndices = <int>[
        for (final dynamic raw in asList(data['hintIndices'])) asInt(raw),
      ];
      final String maskedWord = asString(data['maskedWord']);
      _emitState(
        _state.copyWith(
          hintIndices: hintIndices,
          maskedWord: maskedWord.isEmpty ? _state.maskedWord : maskedWord,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketGameRepository: dropped malformed hint',
        error,
        stackTrace,
      );
    }
  }

  void _handleRoundEnd(Map<String, dynamic> data) {
    try {
      final Object? rawGame = data['game'];
      if (rawGame is Map) {
        _emitState(_merged(asMap(rawGame)));
      }
      _choices = const <WordItem>[];
      final RoundResult result = RoundResult.fromJson(_resultPayload(data));
      _lastRoundResult = result;
      if (!_disposed && !_roundResultController.isClosed) {
        _roundResultController.add(result);
      }
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketGameRepository: dropped malformed round end',
        error,
        stackTrace,
      );
    }
  }

  /// The final standings arrive on their own; the closing phase comes through
  /// `s:game:state`, so the cached state is left to the server.
  void _handleGameEnd(Map<String, dynamic> data) {
    try {
      final GameResult result = GameResult.fromJson(_resultPayload(data));
      _choices = const <WordItem>[];
      _lastGameResult = result;
      if (!_disposed && !_gameResultController.isClosed) {
        _gameResultController.add(result);
      }
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketGameRepository: dropped malformed game end',
        error,
        stackTrace,
      );
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    AppLogger.w(
      'SocketGameRepository: gateway stream error',
      error,
      stackTrace,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Unwraps the `{game: ...}` envelope, tolerating a bare game payload.
  Map<String, dynamic> _gamePayload(Map<String, dynamic> data) {
    final Object? raw = data['game'];
    return raw is Map ? asMap(raw) : data;
  }

  /// Unwraps the `{result: ...}` envelope, tolerating a bare result payload.
  Map<String, dynamic> _resultPayload(Map<String, dynamic> data) {
    final Object? raw = data['result'];
    return raw is Map ? asMap(raw) : data;
  }

  /// Merges [json] onto the cached state, key by key.
  GameState _merged(Map<String, dynamic> json) {
    final GameState base = _state;
    final GameState parsed = GameState.fromJson(json);
    bool has(String key) => json.containsKey(key);

    final GameState next = base.copyWith(
      roomCode: has('roomCode') ? parsed.roomCode : null,
      phase: has('phase') ? parsed.phase : null,
      currentRound: has('currentRound') ? parsed.currentRound : null,
      totalRounds: has('totalRounds') ? parsed.totalRounds : null,
      turnIndex: has('turnIndex') ? parsed.turnIndex : null,
      drawerId: has('drawerId') ? parsed.drawerId : null,
      clearDrawerId: has('drawerId') && parsed.drawerId == null,
      word: has('word') ? parsed.word : null,
      clearWord: has('word') && parsed.word == null,
      maskedWord: has('maskedWord') ? parsed.maskedWord : null,
      wordLength: has('wordLength') ? parsed.wordLength : null,
      hintIndices: has('hintIndices') ? parsed.hintIndices : null,
      turnStartMs: has('turnStartMs') ? parsed.turnStartMs : null,
      turnEndMs: has('turnEndMs') ? parsed.turnEndMs : null,
      correctGuesserIds:
          has('correctGuesserIds') ? parsed.correctGuesserIds : null,
      roundScores: has('roundScores') ? parsed.roundScores : null,
      wordChoices: has('wordChoices') ? parsed.wordChoices : null,
    );

    final bool sameTurn = next.currentRound == base.currentRound &&
        next.turnIndex == base.turnIndex &&
        next.drawerId == base.drawerId;
    if (!has('word') && !sameTurn) {
      return next.copyWith(clearWord: true);
    }
    return next;
  }

  void _emitState(GameState next) {
    if (_disposed) {
      return;
    }
    final bool changed = _state != next;
    _state = next;
    if (changed && !_gameController.isClosed) {
      _gameController.add(next);
    }
  }

  Result<void> _asVoid(Result<Map<String, dynamic>> ack) =>
      ack.fold<Result<void>>(
        (Map<String, dynamic> _) => const Ok<void>(null),
        Err<void>.new,
      );
}
