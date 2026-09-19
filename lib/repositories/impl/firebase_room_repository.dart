import 'dart:async';

import 'package:scribble_guess/core/errors/app_exception.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/repositories/room_repository.dart';
import 'package:scribble_guess/services/firestore_service.dart';
import 'package:scribble_guess/services/room_service.dart';

/// [RoomRepository] backed by Firestore and callable Cloud Functions.
///
/// Reads are a live Firestore subscription; writes are callables. That split is
/// the whole design: the room document is unwritable by clients, so the only
/// way membership or settings can change is through a function that checked
/// the caller's authority first (§48, §50).
///
/// Nothing here is ever optimistic. A kick, a mute or a settings change is not
/// reflected locally until the server's write comes back down the subscription,
/// because the server is entitled to refuse and the UI must not have already
/// claimed otherwise.
class FirebaseRoomRepository implements RoomRepository {
  FirebaseRoomRepository({
    required RoomService service,
    required FirestoreService firestore,
    required String userId,
  })  : _service = service,
        _firestore = firestore,
        _userId = userId;

  final RoomService _service;
  final FirestoreService _firestore;
  final String _userId;

  final StreamController<Room> _rooms = StreamController<Room>.broadcast();
  final StreamController<Failure> _errors =
      StreamController<Failure>.broadcast();

  StreamSubscription<Room?>? _subscription;
  Timer? _heartbeat;
  Room? _currentRoom;
  String? _roomId;
  bool _disposed = false;

  @override
  Stream<Room> get roomStream => _rooms.stream;

  @override
  Stream<Failure> get errorStream => _errors.stream;

  @override
  Room? get currentRoom => _currentRoom;

  @override
  Future<Result<Room>> createRoom(
    RoomSettings settings,
    PlayerProfile profile,
  ) async {
    return _guard(() async {
      final RoomHandle handle = await _service.createRoom(
        profile: profile,
        settings: settings,
      );
      return _attach(handle.roomId);
    });
  }

  @override
  Future<Result<Room>> joinRoom(String code, PlayerProfile profile) async {
    return _guard(() async {
      final RoomHandle handle = await _service.joinRoom(
        roomCode: code,
        profile: profile,
      );
      return _attach(handle.roomId);
    });
  }

  @override
  Future<Result<Room>> acceptInvitation(
    String invitationId,
    PlayerProfile profile,
  ) async {
    // Room invitations are a Node-backend feature: the invitation row, its
    // expiry and the accept's concurrency guard all live there, and this
    // implementation predates them. Refused rather than faked, because the
    // only honest alternative would be to join by a code this layer has no way
    // to look up.
    return const Err<Room>(
      Failure(
        AppErrorCode.invalidAction,
        'Invitations need the game server.',
      ),
    );
  }

  @override
  Future<Result<void>> leaveRoom() async {
    final String? roomId = _roomId;
    if (roomId == null) return const Ok<void>(null);
    return _guard(() async {
      await _service.leaveRoom(roomId);
      await _detach();
    });
  }

  @override
  Future<Result<void>> setReady(bool ready) =>
      _withRoom((String id) => _service.setReady(id, isReady: ready));

  @override
  Future<Result<void>> updateSettings(RoomSettings settings) =>
      _withRoom((String id) => _service.updateSettings(id, settings));

  @override
  Future<Result<int>> addStupids(int count) async => const Err<int>(
    // The bot engine lives in the socket server, not in Firestore. This
    // implementation is legacy and unwired; saying so beats seating bots
    // nothing would ever play.
    Failure(AppErrorCode.invalidAction, 'Stupids need the live game server.'),
  );

  @override
  Future<Result<int>> clearStupids() async => const Err<int>(
    Failure(AppErrorCode.invalidAction, 'Stupids need the live game server.'),
  );

  @override
  Future<Result<void>> kickPlayer(String playerId) =>
      _withRoom((String id) => _service.kickPlayer(id, playerId));

  @override
  Future<Result<void>> banPlayer(String playerId) =>
      _withRoom((String id) => _service.banPlayer(id, playerId));

  @override
  Future<Result<void>> mutePlayer(String playerId, bool muted) =>
      _withRoom((String id) => _service.mutePlayer(id, playerId, muted: muted));

  @override
  Future<Result<void>> transferHost(String playerId) =>
      _withRoom((String id) => _service.transferHost(id, playerId));

  @override
  Future<Result<void>> voteKick(String playerId) =>
      _withRoom((String id) => _service.voteKick(id, playerId));

  @override
  Future<Result<void>> reportPlayer(String playerId, String reason) =>
      _withRoom((String id) => _service.reportPlayer(id, playerId, reason));

  /// Subscribes to a room and waits for its first snapshot.
  ///
  /// The callable has already committed the membership by the time this runs,
  /// so the first snapshot is guaranteed to include this player — which is why
  /// the caller can treat the returned [Room] as the joined state.
  Future<Room> _attach(String roomId) async {
    await _detach();
    _roomId = roomId;

    final Completer<Room> first = Completer<Room>();

    _subscription = _firestore.watchRoom(roomId).listen(
      (Room? room) {
        if (room == null) {
          // The room document vanished: cleaned up, or closed and reaped.
          _push(const Failure(AppErrorCode.roomNotFound, 'The room closed.'));
          unawaited(_detach());
          return;
        }

        // Being absent from a room we are subscribed to means removal.
        final bool stillSeated = room.playerById(_userId) != null;
        if (!stillSeated && _currentRoom != null) {
          final bool banned = room.bannedIds.contains(_userId);
          _push(
            Failure(
              banned ? AppErrorCode.banned : AppErrorCode.kicked,
              banned ? 'You were banned from the room.' : 'You were removed.',
            ),
          );
          unawaited(_detach());
          return;
        }

        if (room.status == RoomStatus.closed) {
          _push(const Failure(AppErrorCode.roomNotFound, 'The room closed.'));
        }

        _currentRoom = room;
        if (!_rooms.isClosed) _rooms.add(room);
        if (!first.isCompleted) first.complete(room);
      },
      onError: (Object error, StackTrace stack) {
        final AppException failure = toAppException(error, stack);
        _push(failure.failure);
        if (!first.isCompleted) first.completeError(failure, stack);
      },
    );

    _startHeartbeat(roomId);

    // A room that never produces a snapshot is a broken subscription, not a
    // slow one; failing here beats hanging the join screen forever.
    return first.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw AppException.of(
        AppErrorCode.timeout,
        'The room did not load.',
      ),
    );
  }

  /// Tells the server we are still here, on a slow timer (§35).
  ///
  /// Deliberately infrequent: presence is worth one write every fifteen
  /// seconds, not one per second. Failures are swallowed — a missed heartbeat
  /// is recoverable, and surfacing it would spam the player with errors for
  /// something they cannot act on.
  void _startHeartbeat(String roomId) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (Timer _) async {
      try {
        await _service.heartbeat(roomId);
      } on Object catch (error) {
        AppLogger.d('heartbeat failed', error);
      }
    });
  }

  Future<void> _detach() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    _currentRoom = null;
    _roomId = null;
  }

  void _push(Failure failure) {
    if (!_errors.isClosed) _errors.add(failure);
  }

  /// Runs [action] against the joined room, or fails when there is none.
  Future<Result<void>> _withRoom(
    Future<void> Function(String roomId) action,
  ) async {
    final String? roomId = _roomId;
    if (roomId == null) {
      return const Err<void>(
        Failure(AppErrorCode.invalidAction, 'You are not in a room.'),
      );
    }
    return _guard(() => action(roomId));
  }

  /// Turns a throwing call into a [Result], per this layer's contract.
  Future<Result<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Ok<T>(await action());
    } on AppException catch (error) {
      return Err<T>(error.failure);
    } on Object catch (error, stack) {
      return Err<T>(toAppException(error, stack).failure);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_detach());
    unawaited(_rooms.close());
    unawaited(_errors.close());
  }
}
