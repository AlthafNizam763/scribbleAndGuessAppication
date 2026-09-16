import 'dart:async';

import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// What Quick Play is doing, for the button to render.
///
/// The states are separate rather than one boolean because they take
/// noticeably different amounts of time and a player deserves to know which
/// one they are waiting on: finding is a round trip, creating allocates a room
/// code, and joining is the part that can fail because somebody else took the
/// last seat.
enum QuickPlayStage {
  /// Nothing in flight. The button reads "Play".
  idle,

  /// Establishing the session and the socket.
  connecting,

  /// Asking the server for a room.
  finding,

  /// A room was found and the seat is being taken.
  joining,

  /// Nothing was waiting, so a room is being opened.
  creating,

  /// Seated. The caller navigates away on this.
  done,

  /// It did not work, and [QuickPlayService.lastFailure] says why.
  failed,
}

/// The Quick Play flow: connect, match, seat.
///
/// ## Why this is a service and not a few lines in the button
///
/// Three things have to be true of the Play button and none of them belongs in
/// a widget: it must not run twice at once, it must report which stage it is
/// at, and it must establish a session and a socket before it can ask for
/// anything. That is the same preamble `RoomController` does for create and
/// join, and this service is deliberately built on top of that rather than
/// beside it — [connect] is passed in, so there is exactly one place in the
/// app that knows how to get a connection.
///
/// ## Why the socket and not the REST endpoint
///
/// `POST /api/rooms/quick-play` exists and does the same matchmaking, but the
/// server's live room registry is process-local: in the split deployment the
/// REST host has no registry and can only hand back a room code. The socket
/// path always seats the player in one round trip, and this app is holding a
/// socket anyway because that is how it plays the game. The REST endpoint is
/// for clients that are not.
///
/// ## Duplicate taps
///
/// Guarded twice. [_inFlight] here means a second tap while the first is still
/// running is ignored outright; the server keeps its own per-user gate, so two
/// *devices* tapping at once cannot open two rooms either. Neither guard alone
/// is enough — this one cannot see the other device, and the server's cannot
/// stop this one from queueing a second request behind the first.
class QuickPlayService {
  /// Creates the service.
  ///
  /// [connect] must establish a session and an open socket, and is expected to
  /// be `RoomController`'s connect step so that Quick Play and the ordinary
  /// join path cannot diverge about what "connected" means.
  QuickPlayService({
    required RealtimeGateway gateway,
    required Future<Result<void>> Function(PlayerProfile profile) connect,
  })  : _gateway = gateway,
        _connect = connect;

  final RealtimeGateway _gateway;
  final Future<Result<void>> Function(PlayerProfile profile) _connect;

  final StreamController<QuickPlayStage> _stages =
      StreamController<QuickPlayStage>.broadcast();

  QuickPlayStage _stage = QuickPlayStage.idle;
  Failure? _lastFailure;
  bool _inFlight = false;
  bool _disposed = false;

  /// What the flow is doing right now.
  QuickPlayStage get stage => _stage;

  /// Stage changes, for a button that wants to relabel itself live.
  Stream<QuickPlayStage> get stages => _stages.stream;

  /// Why the last attempt failed, or null.
  Failure? get lastFailure => _lastFailure;

  /// Whether a request is already running.
  bool get isBusy => _inFlight;

  /// Finds a public room for [profile] and seats them in it.
  ///
  /// Returns the room on success. A second call while one is running is
  /// refused rather than queued: the player tapped twice, they did not ask for
  /// two rooms.
  Future<Result<Room>> play(PlayerProfile profile) async {
    if (_disposed) {
      return const Err<Room>(
        Failure(AppErrorCode.invalidAction, 'Quick Play is no longer available.'),
      );
    }

    if (_inFlight) {
      AppLogger.d('QuickPlay: ignoring a tap while one is already running');
      return const Err<Room>(
        Failure(AppErrorCode.invalidAction, 'Already finding you a room.'),
      );
    }

    _inFlight = true;
    _lastFailure = null;

    try {
      return await _run(profile);
    } finally {
      _inFlight = false;
    }
  }

  Future<Result<Room>> _run(PlayerProfile profile) async {
    _emit(QuickPlayStage.connecting);

    final Result<void> ready = await _connect(profile);
    if (ready case Err<void>(:final Failure failure)) {
      return _fail<Room>(failure);
    }

    _emit(QuickPlayStage.finding);

    final Result<Map<String, dynamic>> ack = await _gateway.request(
      SocketEvents.clientRoomQuickPlay,
      <String, dynamic>{'profile': profile.toJson()},
    );

    if (ack case Err<Map<String, dynamic>>(:final Failure failure)) {
      AppLogger.w('QuickPlay: refused (${failure.code.name})');
      return _fail<Room>(failure);
    }

    final Map<String, dynamic> data = ack.valueOrNull ?? <String, dynamic>{};
    final Object? raw = data['room'];

    if (raw is! Map) {
      // An ack that said ok but carried no room is a server bug, not something
      // the player did. Report it as a server error rather than as a refusal
      // they could act on.
      AppLogger.e('QuickPlay: ack carried no room');
      return _fail<Room>(const Failure.server());
    }

    // Purely for the label: by the time this is read the work is already done,
    // but a room that had to be created took visibly longer and saying so
    // makes the wait legible in hindsight rather than looking like a stall.
    _emit(
      asBool(data['created'])
          ? QuickPlayStage.creating
          : QuickPlayStage.joining,
    );

    final Room room = Room.fromJson(asMap(raw));

    AppLogger.i(
      'QuickPlay: seated in ${room.code} '
      '(created: ${asBool(data['created'])}, '
      'already there: ${asBool(data['alreadySeated'])})',
    );

    _emit(QuickPlayStage.done);
    return Ok<Room>(room);
  }

  /// Returns the button to its resting state after a failure was shown.
  void reset() {
    _lastFailure = null;
    _emit(QuickPlayStage.idle);
  }

  /// Closes the stage stream.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stages.close();
  }

  Result<T> _fail<T>(Failure failure) {
    _lastFailure = failure;
    _emit(QuickPlayStage.failed);
    return Err<T>(failure);
  }

  void _emit(QuickPlayStage stage) {
    if (_disposed || _stage == stage) return;
    _stage = stage;
    if (!_stages.isClosed) _stages.add(stage);
  }
}
