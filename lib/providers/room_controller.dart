import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/auth_api.dart';
import 'package:scribble_guess/data/api/health_api.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/providers/session_providers.dart';
import 'package:scribble_guess/providers/settings_provider.dart';
import 'package:scribble_guess/providers/sound_provider.dart';
import 'package:scribble_guess/repositories/repositories.dart';
import 'package:scribble_guess/services/connectivity_service.dart';

/// Entering and leaving rooms.
///
/// ## The order matters, and it is the opposite of what it used to be
///
/// This used to create the room over Firebase first and open a socket
/// afterwards, because the socket only carried strokes and the game itself ran
/// on Firestore. A failed connection was therefore survivable: the player was
/// still properly in the room, they just could not see anybody drawing.
///
/// With the Node backend the socket *is* the game — `c:room:create` and
/// `c:room:join` are socket calls — so the connection has to be established
/// first, and a failure to connect is a genuine failure to join. Pretending
/// otherwise would leave the player looking at a lobby the server has never
/// heard of.
///
/// A session is guaranteed before connecting: the server rejects the handshake
/// outright without a token, and doing it here means a player who reaches this
/// screen on a cold start does not need the splash to have finished first.
class RoomController {
  const RoomController(this._ref);

  static const Failure _noProfile = Failure(
    AppErrorCode.invalidAction,
    'Set up your profile before joining a game.',
  );

  final Ref _ref;

  /// Hosts a room under [settings].
  Future<Result<Room>> createRoom(RoomSettings settings) async {
    final PlayerProfile? profile = _ref.read(profileProvider);
    if (profile == null) return const Err<Room>(_noProfile);

    _resetSessionState();

    final Result<void> ready = await _connect(profile);
    if (ready case Err<void>(:final Failure failure)) {
      return Err<Room>(failure);
    }

    return _ref.read(roomRepositoryProvider).createRoom(settings, profile);
  }

  /// Joins the room with [code].
  Future<Result<Room>> joinRoom(String code) async {
    final PlayerProfile? profile = _ref.read(profileProvider);
    if (profile == null) return const Err<Room>(_noProfile);

    _resetSessionState();

    final Result<void> ready = await _connect(profile);
    if (ready case Err<void>(:final Failure failure)) {
      return Err<Room>(failure);
    }

    return _ref.read(roomRepositoryProvider).joinRoom(code, profile);
  }

  /// Clears the last room's state and gets a connection, joining nothing.
  ///
  /// Public because Quick Play needs exactly this preamble and must not grow
  /// its own copy of it. Entering a room is three steps — forget the previous
  /// room, establish a session, open the socket — and a second implementation
  /// that got the order wrong would produce a lobby showing the last game's
  /// chat, or a room call made before the handshake the server requires.
  ///
  /// The caller performs its own room call afterwards: this gets them to the
  /// door, it does not decide which room they walk into.
  Future<Result<void>> prepare(PlayerProfile profile) async {
    _resetSessionState();
    return _connect(profile);
  }

  /// Establishes a session and opens the socket.
  ///
  /// Both steps are required before any room call: the handshake presents the
  /// token, and the server refuses a socket that has none.
  Future<Result<void>> _connect(PlayerProfile profile) async {
    // Unpack the audio while the handshake is in flight. Doing it here rather
    // than at app start keeps the first frame free of it, and a room being
    // entered is the last moment before the first sound can possibly fire.
    unawaited(_ref.read(soundServiceProvider).warmUp());

    final Result<AuthSession> session =
        await _ref.read(authServiceProvider).ensureSession(profile: profile);

    if (session case Err<AuthSession>(:final Failure failure)) {
      return Err<void>(failure);
    }

    final Result<void> socket =
        await _ref.read(connectivityProvider).connect(_serverUrl(), profile);

    if (socket case Err<void>(:final Failure failure)) {
      return Err<void>(await _diagnose(failure));
    }
    return socket;
  }

  /// Turns a failed socket connection into a failure that names the cause.
  ///
  /// The socket going down and the phone going offline produce the same
  /// `Failure.network()`, and "No connection. Check your network" is actively
  /// misleading in the first case — the player's network is fine and there is
  /// nothing for them to fix. So when the socket fails, the REST API is asked
  /// whether *it* is reachable, which separates the two:
  ///
  /// - REST unreachable too — the device really is offline. Keep the original.
  /// - REST fine, database down — the backend is broken, not the network.
  /// - REST fine, database fine — only realtime is down, which on a host that
  ///   idles usually means it is still waking up and a retry will work.
  ///
  /// The health endpoint is only ever read *after* a failure and only to
  /// explain it. It never decides whether the game may proceed: it lives on
  /// the REST host, so it cannot know whether this device can hold a socket
  /// open to the realtime host. A connection is proof of realtime
  /// connectivity; a 200 here is not.
  Future<Failure> _diagnose(Failure failure) async {
    // Only transport failures are ambiguous. A rejected handshake or a refused
    // action already says exactly what went wrong.
    if (failure.code != AppErrorCode.network &&
        failure.code != AppErrorCode.timeout &&
        failure.code != AppErrorCode.connectionLost) {
      return failure;
    }

    final BackendHealth health = await _ref.read(healthApiProvider).check();
    AppLogger.i('Connection diagnosis: $health');

    if (!health.reachable) {
      return failure;
    }
    if (!health.restUsable) {
      return const Failure(
        AppErrorCode.serverError,
        AppStrings.errorBackendDegraded,
      );
    }
    return const Failure(
      AppErrorCode.connectionLost,
      AppStrings.errorRealtimeUnreachable,
    );
  }

  /// The backend URL: the player's override, else the build's default.
  ///
  /// Resolved by `socketUrlProvider` rather than here, so the socket and the
  /// REST client cannot disagree about which backend this is. The override
  /// exists for testing against a laptop on the same wifi, which is the only
  /// practical way to play from two physical phones.
  String _serverUrl() => _ref.read(socketUrlProvider);

  /// Leaves the room and drops the socket.
  ///
  /// The local transcript and canvas are cleared too, so the next room does
  /// not open showing the last one's chat.
  Future<Result<void>> leaveRoom() async {
    final RoomRepository repository = _ref.read(roomRepositoryProvider);
    final Result<void> outcome = await repository.leaveRoom();
    await _ref.read(connectivityProvider).disconnect();
    _resetSessionState();
    return outcome;
  }

  /// Retries a dropped connection using the last URL and profile.
  Future<Result<void>> retry() {
    final ConnectivityService connectivity = _ref.read(connectivityProvider);
    if (!connectivity.canRetry) {
      return Future<Result<void>>.value(
        const Err<void>(
          Failure(AppErrorCode.invalidAction, AppStrings.errorConnectionLost),
        ),
      );
    }
    return connectivity.retry();
  }

  void _resetSessionState() {
    _ref.read(chatProvider.notifier).clear();
    _ref.read(boardProvider.notifier).reset();
  }
}

final Provider<RoomController> roomControllerProvider = Provider<RoomController>(
  RoomController.new,
);
