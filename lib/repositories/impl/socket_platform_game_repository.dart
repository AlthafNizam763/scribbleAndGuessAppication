import 'dart:async';

import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/replay_stream.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/platform_match.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/repositories/platform_game_repository.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// The gateway's inbound record, aliased for readability.
typedef _Inbound = ({String event, Map<String, dynamic> data});

/// [PlatformGameRepository] backed by a [RealtimeGateway].
///
/// It translates the `game:*` and `space:*` pushes into typed snapshots and
/// forwards every write as a request whose ack decides the outcome. It holds
/// no rules and never edits a snapshot optimistically: the cached room, match
/// and frame are replaced only by what the server sent.
///
/// A malformed payload is logged and dropped. It never breaks the subscription
/// and never reaches a screen.
class SocketPlatformGameRepository implements PlatformGameRepository {
  /// Starts listening to [gateway] for platform-game traffic.
  SocketPlatformGameRepository(RealtimeGateway gateway) : _gateway = gateway {
    _inbound = _gateway.inbound.listen(_onInbound, onError: _onStreamError);
  }

  final RealtimeGateway _gateway;

  final StreamController<PlatformRoom> _rooms =
      StreamController<PlatformRoom>.broadcast();
  final StreamController<PlatformMatch> _matches =
      StreamController<PlatformMatch>.broadcast();
  final StreamController<Map<String, dynamic>> _frames =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<ChatMessage> _chat =
      StreamController<ChatMessage>.broadcast();
  final StreamController<Failure> _errors = StreamController<Failure>.broadcast();

  StreamSubscription<_Inbound>? _inbound;

  PlatformRoom? _room;
  PlatformMatch? _match;
  Map<String, dynamic>? _frame;
  bool _disposed = false;

  @override
  Stream<PlatformRoom> get roomStream => replaying<PlatformRoom>(_rooms, () => _room);

  @override
  PlatformRoom? get currentRoom => _room;

  @override
  Stream<PlatformMatch> get matchStream =>
      replaying<PlatformMatch>(_matches, () => _match);

  @override
  PlatformMatch? get currentMatch => _match;

  /// Not replayed, on purpose.
  ///
  /// A frame describes where everybody was a tenth of a second ago, and the
  /// next one is already on its way. Handing a stale one to a late listener
  /// would draw the ship as it was when they looked away.
  @override
  Stream<Map<String, dynamic>> get realtimeStream => _frames.stream;

  @override
  Map<String, dynamic>? get currentFrame => _frame;

  @override
  Stream<ChatMessage> get chatStream => _chat.stream;

  @override
  Stream<Failure> get errorStream => _errors.stream;

  @override
  Future<Result<PlatformRoom>> subscribe(GameId gameId, String roomId) async {
    final Result<Map<String, dynamic>> ack = await _gateway.request(
      SocketEvents.clientGameSubscribe,
      <String, dynamic>{'gameId': gameId.wire, 'roomId': roomId},
    );

    return switch (ack) {
      Ok<Map<String, dynamic>>(:final Map<String, dynamic> value) => () {
          final PlatformRoom room = PlatformRoom.fromJson(asMap(value['room']));
          _pushRoom(room);

          // The ack carries this seat's view of a match already in progress.
          // Pushed before the future completes, so a caller that awaits this
          // can read `currentMatch` on the very next line — which is what a
          // screen opening onto a running game needs.
          final Map<String, dynamic> match = asMap(value['match']);
          if (match.isNotEmpty) _pushMatch(PlatformMatch.fromJson(match));

          return Ok<PlatformRoom>(room);
        }(),
      Err<Map<String, dynamic>>(:final Failure failure) => Err<PlatformRoom>(failure),
    };
  }

  @override
  Future<Result<void>> action(
    GameId gameId,
    String matchId,
    String event, [
    Map<String, dynamic> body = const <String, dynamic>{},
  ]) async {
    final Result<Map<String, dynamic>> ack = await _gateway.request(event, <String, dynamic>{
      ...body,
      'gameId': gameId.wire,
      'matchId': matchId,
    });

    return switch (ack) {
      // Deliberately discards the payload. The ack echoes this viewer's state,
      // but so does the broadcast that follows it, and taking the ack's copy
      // would let the player who acted see the new position a round trip
      // before everybody else — which is how a client ends up a move ahead of
      // the table it is sitting at.
      Ok<Map<String, dynamic>>() => const Ok<void>(null),
      Err<Map<String, dynamic>>(:final Failure failure) => () {
          _errors.add(failure);
          return Err<void>(failure);
        }(),
    };
  }

  @override
  Future<Result<void>> roomAction(
    GameId gameId,
    String roomId,
    String event, [
    Map<String, dynamic> body = const <String, dynamic>{},
  ]) async {
    final Result<Map<String, dynamic>> ack = await _gateway.request(event, <String, dynamic>{
      ...body,
      'gameId': gameId.wire,
      'roomId': roomId,
    });

    return switch (ack) {
      // As with [action], the payload is discarded: the consequence arrives on
      // the room broadcast that everybody else receives.
      Ok<Map<String, dynamic>>() => const Ok<void>(null),
      Err<Map<String, dynamic>>(:final Failure failure) => () {
          _errors.add(failure);
          return Err<void>(failure);
        }(),
    };
  }

  @override
  void send(
    GameId gameId,
    String matchId,
    String event, [
    Map<String, dynamic> body = const <String, dynamic>{},
  ]) {
    _gateway.emit(event, <String, dynamic>{
      ...body,
      'gameId': gameId.wire,
      'matchId': matchId,
    });
  }

  @override
  Future<Result<void>> sendChat(GameId gameId, String roomId, String text) async {
    final String clean = text.trim();
    if (clean.isEmpty) {
      return const Err<void>(Failure(AppErrorCode.validation, 'Write a message first.'));
    }

    final Result<Map<String, dynamic>> ack = await _gateway.request(
      SocketEvents.clientGameChatSend,
      <String, dynamic>{'gameId': gameId.wire, 'roomId': roomId, 'message': clean},
    );

    return switch (ack) {
      // The line is not added locally. It arrives on the same push everybody
      // else gets, so one transcript exists rather than one per device.
      Ok<Map<String, dynamic>>() => const Ok<void>(null),
      Err<Map<String, dynamic>>(:final Failure failure) => Err<void>(failure),
    };
  }

  @override
  Future<Result<void>> leave(GameId gameId, String roomId) async {
    final Result<Map<String, dynamic>> ack = await _gateway.request(
      SocketEvents.clientGameRoomLeave,
      <String, dynamic>{'gameId': gameId.wire, 'roomId': roomId},
    );
    reset();

    return switch (ack) {
      Ok<Map<String, dynamic>>() => const Ok<void>(null),
      Err<Map<String, dynamic>>(:final Failure failure) => Err<void>(failure),
    };
  }

  @override
  void reset() {
    _room = null;
    _match = null;
    _frame = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_inbound?.cancel());
    _inbound = null;
    unawaited(_rooms.close());
    unawaited(_matches.close());
    unawaited(_frames.close());
    unawaited(_chat.close());
    unawaited(_errors.close());
  }

  // ---------------------------------------------------------------- inbound --

  void _onInbound(_Inbound message) {
    if (_disposed) return;

    try {
      switch (message.event) {
        case SocketEvents.serverGameRoomUpdated:
        case SocketEvents.serverGameRoomCreated:
          _pushRoom(PlatformRoom.fromJson(asMap(message.data['room'])));

        case SocketEvents.serverGameMatchStarted:
        case SocketEvents.serverGameMatchState:
        case SocketEvents.serverGameMatchCompleted:
          _pushMatch(PlatformMatch.fromJson(message.data));

        case SocketEvents.serverSpaceState:
          // The frame *is* the projection — there is no envelope, because at
          // ten a second an envelope is a tenth of the payload.
          _frame = message.data;
          _frames.add(message.data);

        case SocketEvents.serverGameChatMessage:
          _pushChat(asMap(message.data['message']));
      }
    } catch (error, stackTrace) {
      // A malformed push is a server or version problem, not a reason to tear
      // down a live match. It is logged and the game carries on with the last
      // good state.
      AppLogger.w('[PlatformGame] dropped ${message.event}', error, stackTrace);
    }
  }

  void _pushRoom(PlatformRoom room) {
    _room = room;
    if (!_rooms.isClosed) _rooms.add(room);
  }

  void _pushMatch(PlatformMatch match) {
    // A completed match must not be walked backwards by a late in-flight
    // update for the same match: the result screen is already up.
    final PlatformMatch? previous = _match;
    if (previous != null &&
        previous.matchId == match.matchId &&
        previous.isOver &&
        !match.isOver) {
      return;
    }

    _match = match;
    if (!_matches.isClosed) _matches.add(match);
  }

  void _pushChat(Map<String, dynamic> json) {
    if (json.isEmpty) return;

    // The platform chat row is shaped by `GameChatMessage`, which names its
    // fields differently from the Scribble transcript: `username` rather than
    // `senderName`, `message` rather than `text`. Translated here so one
    // `ChatMessage` serves both panels.
    final ChatMessage message = ChatMessage(
      id: asString(json['id']),
      senderId: asString(json['userId']),
      senderName: asString(json['username']),
      text: asString(json['message']),
      type: ChatMessageType.fromName(asString(json['type'], 'chat')),
      timestampMs: asInt(json['createdAtMs']),
    );

    if (message.text.isEmpty) return;
    if (!_chat.isClosed) _chat.add(message);
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    AppLogger.w('[PlatformGame] gateway stream error', error, stackTrace);
  }
}
