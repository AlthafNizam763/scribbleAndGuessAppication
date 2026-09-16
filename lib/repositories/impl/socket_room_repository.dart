import 'dart:async';

import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/replay_stream.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/validators.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';
import 'package:scribble_guess/repositories/room_repository.dart';

/// The gateway's inbound record, aliased for readability.
typedef _Inbound = ({String event, Map<String, dynamic> data});

/// [RoomRepository] backed by a [RealtimeGateway].
///
/// It owns no rules. It translates the `s:room:*` pushes into typed [Room]
/// snapshots and typed [Failure]s, and forwards every write as a `c:room:*`
/// request whose ack decides the outcome. The server remains the only
/// authority on membership, host identity and moderation, so the cached room
/// is never edited optimistically — it is replaced only by what the server
/// pushed or acked.
///
/// A malformed payload is logged and dropped: it never breaks the gateway
/// subscription and never reaches the UI.
class SocketRoomRepository implements RoomRepository {
  /// Starts listening to [gateway] for room traffic.
  SocketRoomRepository(RealtimeGateway gateway) : _gateway = gateway {
    _inboundSubscription = _gateway.inbound.listen(
      _onInbound,
      onError: _onStreamError,
    );
    _statusSubscription = _gateway.status.listen(
      _onStatus,
      onError: _onStreamError,
    );
  }

  final RealtimeGateway _gateway;

  final StreamController<Room> _roomController =
      StreamController<Room>.broadcast();
  final StreamController<Failure> _errorController =
      StreamController<Failure>.broadcast();

  StreamSubscription<_Inbound>? _inboundSubscription;
  StreamSubscription<ConnectionStatus>? _statusSubscription;

  Room? _room;
  bool _disposed = false;

  @override
  Stream<Room> get roomStream => replaying<Room>(_roomController, () => _room);

  @override
  Stream<Failure> get errorStream => _errorController.stream;

  @override
  Room? get currentRoom => _room;

  @override
  Future<Result<Room>> createRoom(
    RoomSettings settings,
    PlayerProfile profile,
  ) async {
    final List<String> problems = settings.validate();
    if (problems.isNotEmpty) {
      return Err<Room>(Failure.validation(problems.first));
    }
    final Result<Map<String, dynamic>> ack = await _gateway.request(
      SocketEvents.clientRoomCreate,
      <String, dynamic>{
        'settings': settings.toJson(),
        'profile': profile.toJson(),
      },
    );
    return _roomFromAck(ack, 'create');
  }

  @override
  Future<Result<Room>> joinRoom(String code, PlayerProfile profile) async {
    final String? problem = Validators.roomCode(code);
    if (problem != null) {
      return Err<Room>(Failure(AppErrorCode.invalidCode, problem));
    }
    final Result<Map<String, dynamic>> ack = await _gateway.request(
      SocketEvents.clientRoomJoin,
      <String, dynamic>{
        'code': Validators.normalizeRoomCode(code),
        'profile': profile.toJson(),
      },
    );
    return _roomFromAck(ack, 'join');
  }

  @override
  Future<Result<void>> leaveRoom() async {
    if (_room == null) {
      return const Ok<void>(null);
    }
    final Result<Map<String, dynamic>> ack =
        await _gateway.request(SocketEvents.clientRoomLeave);
    _clearCache();
    return _asVoid(ack);
  }

  @override
  Future<Result<void>> setReady(bool ready) async => _asVoid(
        await _gateway.request(
          SocketEvents.clientRoomReady,
          <String, dynamic>{'ready': ready},
        ),
      );

  @override
  Future<Result<void>> updateSettings(RoomSettings settings) async {
    final List<String> problems = settings.validate();
    if (problems.isNotEmpty) {
      return Err<void>(Failure.validation(problems.first));
    }
    return _asVoid(
      await _gateway.request(
        SocketEvents.clientRoomSettings,
        <String, dynamic>{'settings': settings.toJson()},
      ),
    );
  }

  @override
  Future<Result<void>> kickPlayer(String playerId) =>
      _playerAction(SocketEvents.clientRoomKick, playerId);

  @override
  Future<Result<void>> banPlayer(String playerId) =>
      _playerAction(SocketEvents.clientRoomBan, playerId);

  @override
  Future<Result<void>> mutePlayer(String playerId, bool muted) => _playerAction(
        SocketEvents.clientRoomMute,
        playerId,
        <String, dynamic>{'muted': muted},
      );

  @override
  Future<Result<void>> transferHost(String playerId) =>
      _playerAction(SocketEvents.clientRoomTransferHost, playerId);

  @override
  Future<Result<void>> voteKick(String playerId) =>
      _playerAction(SocketEvents.clientRoomVoteKick, playerId);

  @override
  Future<Result<void>> reportPlayer(String playerId, String reason) async {
    final String trimmed = reason.trim();
    if (trimmed.isEmpty) {
      return const Err<void>(
        Failure(AppErrorCode.validation, AppStrings.validationMessageRequired),
      );
    }
    if (trimmed.runes.length > AppConstants.maxChatLength) {
      return const Err<void>(
        Failure(AppErrorCode.validation, AppStrings.validationMessageTooLong),
      );
    }
    return _playerAction(
      SocketEvents.clientRoomReport,
      playerId,
      <String, dynamic>{'reason': trimmed},
    );
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_inboundSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    _inboundSubscription = null;
    _statusSubscription = null;
    _room = null;
    unawaited(_roomController.close());
    unawaited(_errorController.close());
  }

  // ---------------------------------------------------------------------------
  // Inbound
  // ---------------------------------------------------------------------------

  void _onInbound(_Inbound message) {
    switch (message.event) {
      case SocketEvents.serverRoomState:
        _handleRoomState(message.data);
      case SocketEvents.serverRoomClosed:
        _handleRoomClosed(message.data);
      case SocketEvents.serverYouKicked:
        _handleYouKicked(message.data);
      case SocketEvents.serverError:
        _handleServerError(message.data);
    }
  }

  void _handleRoomState(Map<String, dynamic> data) {
    try {
      final Room room = Room.fromJson(_roomPayload(data));
      if (room.code.isEmpty) {
        AppLogger.w('SocketRoomRepository: room state without a code');
        return;
      }
      _cache(room);
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketRoomRepository: dropped malformed room state',
        error,
        stackTrace,
      );
    }
  }

  /// A closed room is gone for everyone, so the cache is dropped and the
  /// reason travels as a server-side failure.
  void _handleRoomClosed(Map<String, dynamic> data) {
    try {
      final String reason = asString(data['reason']).trim();
      _clearCache();
      _pushError(
        Failure(
          AppErrorCode.serverError,
          reason.isEmpty ? AppStrings.lobbyRoomClosed : reason,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketRoomRepository: dropped malformed room close',
        error,
        stackTrace,
      );
    }
  }

  /// Removal is reported as [AppErrorCode.banned] when the server says the
  /// player may not come back, and as [AppErrorCode.kicked] otherwise.
  void _handleYouKicked(Map<String, dynamic> data) {
    try {
      final String reason = asString(data['reason']).trim().toLowerCase();
      final bool banned = reason.contains('ban');
      _clearCache();
      _pushError(
        banned
            ? const Failure(
                AppErrorCode.banned,
                AppStrings.moderationYouWereBanned,
              )
            : const Failure(
                AppErrorCode.kicked,
                AppStrings.moderationYouWereKicked,
              ),
      );
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketRoomRepository: dropped malformed kick push',
        error,
        stackTrace,
      );
    }
  }

  void _handleServerError(Map<String, dynamic> data) {
    try {
      final Object? raw = data['error'];
      _pushError(Failure.fromJson(raw is Map ? asMap(raw) : data));
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketRoomRepository: dropped malformed error push',
        error,
        stackTrace,
      );
    }
  }

  /// Losing the transport while seated is an out-of-band failure; a reconnect
  /// re-pushes the authoritative room, so the cache is kept.
  void _onStatus(ConnectionStatus status) {
    if (_room == null) {
      return;
    }
    if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.failed) {
      _pushError(
        const Failure(
          AppErrorCode.connectionLost,
          AppStrings.errorConnectionLost,
        ),
      );
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    AppLogger.w(
      'SocketRoomRepository: gateway stream error',
      error,
      stackTrace,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Unwraps the `{room: ...}` envelope, tolerating a bare room payload.
  Map<String, dynamic> _roomPayload(Map<String, dynamic> data) {
    final Object? raw = data['room'];
    return raw is Map ? asMap(raw) : data;
  }

  Result<Room> _roomFromAck(Result<Map<String, dynamic>> ack, String action) =>
      ack.fold<Result<Room>>(
        (Map<String, dynamic> data) {
          try {
            final Room room = Room.fromJson(_roomPayload(data));
            if (room.code.isEmpty) {
              AppLogger.w('SocketRoomRepository: $action ack without a room');
              return const Err<Room>(Failure.server());
            }
            _cache(room);
            return Ok<Room>(room);
          } catch (error, stackTrace) {
            AppLogger.e(
              'SocketRoomRepository: malformed $action ack',
              error,
              stackTrace,
            );
            return const Err<Room>(Failure.server());
          }
        },
        Err<Room>.new,
      );

  Future<Result<void>> _playerAction(
    String event,
    String playerId, [
    Map<String, dynamic> extra = const <String, dynamic>{},
  ]) async {
    if (playerId.trim().isEmpty) {
      return const Err<void>(
        Failure(AppErrorCode.invalidAction, AppStrings.errorInvalidAction),
      );
    }
    return _asVoid(
      await _gateway.request(event, <String, dynamic>{
        'playerId': playerId,
        ...extra,
      }),
    );
  }

  Result<void> _asVoid(Result<Map<String, dynamic>> ack) =>
      ack.fold<Result<void>>(
        (Map<String, dynamic> _) => const Ok<void>(null),
        Err<void>.new,
      );

  void _cache(Room room) {
    if (_disposed) {
      return;
    }
    final bool changed = _room != room;
    _room = room;
    if (changed && !_roomController.isClosed) {
      _roomController.add(room);
    }
  }

  void _clearCache() {
    _room = null;
  }

  void _pushError(Failure failure) {
    if (_disposed || _errorController.isClosed) {
      return;
    }
    _errorController.add(failure);
  }
}
