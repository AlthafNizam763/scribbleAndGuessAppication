import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/platform_match.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/providers/session_providers.dart';
import 'package:scribble_guess/repositories/repositories.dart';

/// Everything one platform-game session is, at a moment.
///
/// One object for all four games rather than three near-identical ones: the
/// *transport* is the same for all of them — a room, a match projection, a
/// chat transcript, a connection — and only the contents of
/// [PlatformMatch.state] differ. Each game parses that into its own typed view
/// (`KazhuthaState` and friends) at the point where it knows what the fields
/// mean, which is the only place that knowledge belongs.
@immutable
class PlatformSession {
  const PlatformSession({
    this.gameId,
    this.room,
    this.match,
    this.frame,
    this.chat = const <ChatMessage>[],
    this.connection = ConnectionStatus.idle,
    this.lastError,
    this.subscribing = false,
    this.acting = false,
  });

  /// Which game this session is for. `null` before [PlatformSessionNotifier.open].
  final GameId? gameId;

  final PlatformRoom? room;

  /// The turn-based projection: Kazhutha, Bluff Bar, Ludo.
  final PlatformMatch? match;

  /// Space Mystery's latest realtime frame. Null for every other game.
  final Map<String, dynamic>? frame;

  final List<ChatMessage> chat;
  final ConnectionStatus connection;

  /// The most recent server refusal, for the screen to say out loud. Cleared
  /// once shown, so the same refusal is not reported twice.
  final Failure? lastError;

  /// Attaching to the room. Distinct from [acting]: one is "getting to the
  /// table", the other is "taking a turn at it".
  final bool subscribing;

  /// An action is in flight. Used to stop a double-tap sending two draws.
  final bool acting;

  bool get hasMatch => match != null || frame != null;

  /// Whether the server is reachable. The match keeps running without it.
  bool get isLive => connection == ConnectionStatus.connected;

  PlatformSession copyWith({
    GameId? gameId,
    PlatformRoom? room,
    PlatformMatch? match,
    Map<String, dynamic>? frame,
    List<ChatMessage>? chat,
    ConnectionStatus? connection,
    Failure? lastError,
    bool clearError = false,
    bool? subscribing,
    bool? acting,
  }) =>
      PlatformSession(
        gameId: gameId ?? this.gameId,
        room: room ?? this.room,
        match: match ?? this.match,
        frame: frame ?? this.frame,
        chat: chat ?? this.chat,
        connection: connection ?? this.connection,
        lastError: clearError ? null : (lastError ?? this.lastError),
        subscribing: subscribing ?? this.subscribing,
        acting: acting ?? this.acting,
      );
}

/// Owns one platform-game session: the room, the match and the wire under them.
///
/// ## Why this is not three controllers
///
/// The brief asks for a socket controller per game, and there is one — see
/// `KazhuthaController` and its siblings. They are *command surfaces*: typed,
/// game-shaped methods that say `draw` and `declare` and `move`. What they are
/// not is three copies of subscribe-broadcast-reconnect-chat, which is what a
/// controller per game would have meant. That lives here, once.
///
/// ## The subscription is the whole trick
///
/// A room is created and joined over REST, and a REST call has no socket, so
/// nothing in it can put this connection into the room's broadcast channel.
/// [open] is what attaches it, and until it has been called this session will
/// receive nothing at all. It is also the reconnect path: a socket that drops
/// and comes back is in no channels, so [open] runs again — which is why it is
/// idempotent on the server.
class PlatformSessionNotifier extends Notifier<PlatformSession> {
  StreamSubscription<PlatformRoom>? _rooms;
  StreamSubscription<PlatformMatch>? _matches;
  StreamSubscription<Map<String, dynamic>>? _frames;
  StreamSubscription<ChatMessage>? _chat;
  StreamSubscription<Failure>? _errors;

  /// The room this session is attached to, kept so a reconnect can re-attach
  /// without the screen having to remember.
  String _roomId = '';

  @override
  PlatformSession build() {
    final PlatformGameRepository repository =
        ref.watch(platformGameRepositoryProvider);

    _rooms = repository.roomStream.listen(_onRoom);
    _matches = repository.matchStream.listen(_onMatch);
    _frames = repository.realtimeStream.listen(_onFrame);
    _chat = repository.chatStream.listen(_onChat);
    _errors = repository.errorStream.listen(_onError);

    // Re-attaching on reconnect is the reason this watches the connection
    // rather than just reporting it: the socket comes back in no channels at
    // all, so without this the game would go quiet and stay quiet.
    ref.listen<ConnectionStatus>(connectionProvider, (
      ConnectionStatus? previous,
      ConnectionStatus next,
    ) {
      state = state.copyWith(connection: next);
      if (previous != ConnectionStatus.connected &&
          next == ConnectionStatus.connected &&
          _roomId.isNotEmpty) {
        unawaited(_resubscribe());
      }
    });

    ref.onDispose(() {
      unawaited(_rooms?.cancel());
      unawaited(_matches?.cancel());
      unawaited(_frames?.cancel());
      unawaited(_chat?.cancel());
      unawaited(_errors?.cancel());
    });

    return PlatformSession(connection: ref.read(connectionProvider));
  }

  /// Attaches to [roomId] and starts receiving its broadcasts.
  ///
  /// Safe to call again for the same room — the server treats it as "I am
  /// already here" — which is what makes it usable as the reconnect path.
  Future<Result<PlatformRoom>> open(GameId gameId, String roomId) async {
    _roomId = roomId;
    state = state.copyWith(gameId: gameId, subscribing: true, clearError: true);

    final Result<PlatformRoom> result = await ref
        .read(platformGameRepositoryProvider)
        .subscribe(gameId, roomId);

    state = switch (result) {
      Ok<PlatformRoom>(:final PlatformRoom value) =>
        state.copyWith(room: value, subscribing: false),
      Err<PlatformRoom>(:final Failure failure) =>
        state.copyWith(subscribing: false, lastError: failure),
    };

    return result;
  }

  /// Sends a game action and reports whether the server accepted it.
  ///
  /// What it does *not* do is apply anything. The consequences arrive on the
  /// broadcast, which is the same one everybody else gets — so the player who
  /// acted never sees a different table from the players who did not.
  Future<Result<void>> act(String event, [Map<String, dynamic> body = const <String, dynamic>{}]) async {
    final GameId? gameId = state.gameId;

    // The same resolution movement uses, and for the same reason.
    //
    // This used to read `state.match?.matchId` alone, which is a dead end for
    // a real-time game: Space Mystery's truth arrives as `space:state` frames,
    // and there are windows — a reconnect whose subscribe ack carried no
    // match, a first frame that beats the match broadcast — where the frame is
    // the only thing that knows the match id. Every discrete action in the
    // game (use a console, report, vote, call a meeting, sabotage) then failed
    // with "No match in progress" while the player could still walk about,
    // because movement went through `push` and took the other path. Two ways
    // of answering one question is how that happened, so now there is one.
    final String matchId = _matchIdForPush();
    if (gameId == null || matchId.isEmpty) {
      return const Err<void>(Failure(AppErrorCode.invalidAction, 'No match in progress.'));
    }
    if (state.acting) {
      // A second tap while the first is still in flight. Dropped rather than
      // queued: the server would refuse it anyway — it is no longer this
      // player's turn by then — and a queued action fires into a table that
      // has moved on.
      return const Ok<void>(null);
    }

    state = state.copyWith(acting: true, clearError: true);
    final Result<void> result = await ref
        .read(platformGameRepositoryProvider)
        .action(gameId, matchId, event, body);
    state = state.copyWith(acting: false);

    if (result case Err<void>(:final Failure failure)) {
      state = state.copyWith(lastError: failure);
    }
    return result;
  }

  /// Fires an action without waiting. For continuous input only.
  void push(String event, [Map<String, dynamic> body = const <String, dynamic>{}]) {
    final GameId? gameId = state.gameId;
    final String matchId = _matchIdForPush();
    if (gameId == null || matchId.isEmpty) return;

    ref.read(platformGameRepositoryProvider).send(gameId, matchId, event, body);
  }

  /// Offers another round at this table.
  ///
  /// The reply is discarded on purpose: the offer arrives on the room
  /// broadcast like everything else, so the player who asked and the players
  /// who were asked are looking at the same object. Taking the ack's copy
  /// would put the asker a round trip ahead of the table.
  Future<Result<void>> requestRematch() =>
      _roomCall(SocketEvents.clientGameRematchRequest);

  /// Answers a standing offer. Declining also leaves the room — see the
  /// server's `rematch.service.ts` for why that is the right behaviour.
  Future<Result<void>> respondRematch({required bool accept}) =>
      _roomCall(
        SocketEvents.clientGameRematchRespond,
        <String, dynamic>{'accept': accept},
      );

  /// A room-scoped call that needs no match id.
  Future<Result<void>> _roomCall(
    String event, [
    Map<String, dynamic> body = const <String, dynamic>{},
  ]) async {
    final GameId? gameId = state.gameId;
    if (gameId == null || _roomId.isEmpty) {
      return const Err<void>(Failure(AppErrorCode.invalidAction, 'You are not in a room.'));
    }

    state = state.copyWith(acting: true, clearError: true);
    final Result<void> result = await ref
        .read(platformGameRepositoryProvider)
        .roomAction(gameId, _roomId, event, body);
    state = state.copyWith(acting: false);

    if (result case Err<void>(:final Failure failure)) {
      state = state.copyWith(lastError: failure);
    }
    return result;
  }

  Future<Result<void>> sendChat(String text) async {
    final GameId? gameId = state.gameId;
    if (gameId == null || _roomId.isEmpty) {
      return const Err<void>(Failure(AppErrorCode.invalidAction, 'You are not in a room.'));
    }
    return ref.read(platformGameRepositoryProvider).sendChat(gameId, _roomId, text);
  }

  /// Leaves the room for good.
  Future<Result<void>> leave() async {
    final GameId? gameId = state.gameId;
    if (gameId == null || _roomId.isEmpty) return const Ok<void>(null);

    final Result<void> result =
        await ref.read(platformGameRepositoryProvider).leave(gameId, _roomId);
    _roomId = '';
    state = const PlatformSession();
    return result;
  }

  /// Marks the last refusal as shown, so it is not reported twice.
  void clearError() {
    if (state.lastError == null) return;
    state = state.copyWith(clearError: true);
  }

  Future<void> _resubscribe() async {
    final GameId? gameId = state.gameId;
    if (gameId == null || _roomId.isEmpty) return;

    AppLogger.i('[PlatformGame] re-attaching to $_roomId after a reconnect');
    await open(gameId, _roomId);
  }

  /// The match this session is acting on, wherever the id happens to live.
  ///
  /// Three sources, most authoritative first. A turn-based game always has the
  /// match envelope. Space Mystery's frames are not `PlatformMatch`
  /// envelopes — they are the projection itself — so a session driven entirely
  /// by the tick has the id in the frame and nowhere else, and a session that
  /// has only just attached has it on the room.
  ///
  /// Used by both [act] and [push], deliberately: when they disagreed, half
  /// the game worked.
  String _matchIdForPush() {
    final String fromMatch = state.match?.matchId ?? '';
    if (fromMatch.isNotEmpty) return fromMatch;

    final Object? fromFrame = state.frame?['matchId'];
    if (fromFrame is String && fromFrame.isNotEmpty) return fromFrame;

    return state.room?.matchId ?? '';
  }

  void _onRoom(PlatformRoom room) {
    _roomId = room.roomId;
    state = state.copyWith(room: room);
  }

  void _onMatch(PlatformMatch match) => state = state.copyWith(match: match);

  void _onFrame(Map<String, dynamic> frame) => state = state.copyWith(frame: frame);

  void _onChat(ChatMessage message) {
    final List<ChatMessage> next = <ChatMessage>[...state.chat, message];
    // Capped like the Scribble transcript: a long match must not grow a list
    // without bound, and nobody scrolls back two hundred lines mid-turn.
    if (next.length > AppConstants.chatHistoryLimit) {
      next.removeRange(0, next.length - AppConstants.chatHistoryLimit);
    }
    state = state.copyWith(chat: next);
  }

  void _onError(Failure failure) => state = state.copyWith(lastError: failure);
}

/// The one live platform-game session.
final NotifierProvider<PlatformSessionNotifier, PlatformSession>
    platformSessionProvider =
    NotifierProvider<PlatformSessionNotifier, PlatformSession>(
  PlatformSessionNotifier.new,
);

/// The local player's seat id in the current platform room.
///
/// The backend user id, which is what every projection keys on. Read from the
/// profile rather than from the room so it is available before the room is.
final Provider<String> platformSelfIdProvider = Provider<String>(
  (Ref ref) => ref.watch(selfIdProvider),
);
