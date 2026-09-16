import 'dart:async';

import 'package:scribble_guess/app/app_config.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// The Socket.IO implementation of [RealtimeGateway], and the only place in
/// the Flutter app that knows Socket.IO exists.
///
/// Everything above this class talks in `(event, data)` pairs and [Result]s:
/// repositories subscribe to [inbound], call [request] for anything that needs
/// a verdict and [emit] for loss-tolerant traffic. Nothing throws out of here.
///
/// ## Clock synchronisation
///
/// The turn countdown must be server-authoritative, so this service measures
/// the `server - client` clock difference instead of trusting the device.
/// After every successful (re)connect, and then every
/// `AppConstants.timeSyncIntervalSeconds`, it runs
/// `AppConstants.timeSyncSamples` `c:time:ping` round trips and keeps the
/// sample with the *lowest* round-trip time rather than the mean: one delayed
/// packet skews an average badly, while the fastest round trip of a burst is
/// the closest thing to a symmetric, uncongested measurement. The one-way
/// `s:time:sync` broadcast cannot be latency-compensated, so it is folded in
/// with a small weight instead of replacing the measurement.
class SocketService implements RealtimeGateway {
  /// Creates a gateway with tunable deadlines.
  ///
  /// [connectTimeout] bounds [connect] up to and including the handshake ack,
  /// [requestTimeout] bounds a single [request], and [pingTimeout] bounds one
  /// clock-sync round trip.
  ///
  /// [connectTimeout] must stay comfortably above [_engineTimeout], or it
  /// fires first and reports a timeout while the transport is still legitimately
  /// opening — which is what a cold realtime host looks like. The margin covers
  /// the `c:hello` round trip that follows the transport coming up.
  SocketService({
    Duration connectTimeout = const Duration(seconds: 28),
    Duration requestTimeout = const Duration(seconds: 8),
    Duration pingTimeout = const Duration(seconds: 3),
  })  : _connectTimeout = connectTimeout,
        _requestTimeout = requestTimeout,
        _pingTimeout = pingTimeout;

  // Transport-level event names. These belong to Socket.IO itself rather than
  // to the game protocol, so they deliberately do not live in `SocketEvents`.
  static const String _evConnect = 'connect';
  static const String _evDisconnect = 'disconnect';
  static const String _evConnectError = 'connect_error';
  static const String _evError = 'error';
  static const String _evReconnect = 'reconnect';
  static const String _evReconnectAttempt = 'reconnect_attempt';
  static const String _evReconnectError = 'reconnect_error';
  static const String _evReconnectFailed = 'reconnect_failed';

  /// The Socket.IO endpoint path, which is the client default and the one the
  /// server mounts on.
  ///
  /// Recorded only so the connection log can state it. It is *not* appended to
  /// the URL: the client adds it itself, and a `SOCKET_URL` that already ends
  /// in `/socket.io` produces requests to `/socket.io/socket.io/`.
  static const String _path = '/socket.io';

  /// Websocket only, and deliberately so — this was measured, not assumed.
  ///
  /// The server accepts both transports (`src/config/socket.ts`), and the
  /// obvious configuration is `['websocket', 'polling']` so a network that
  /// blocks upgrades can still play. Neither half of that works here.
  ///
  /// First, a trailing `'polling'` is decorative in this client. Engine.IO
  /// opens `transports[0]` and, on a connection error, goes to `onClose` —
  /// `engine/socket.dart` only advances to the next entry when *constructing*
  /// a transport throws, which never happens for these two. So a
  /// websocket-first list never reaches polling anyway; the reconnect just
  /// retries websocket.
  ///
  /// Second, the order that *would* use both — polling first, upgrading once
  /// connected — does not work against this backend at all. Measured against
  /// the deployed realtime host with a valid token:
  ///
  ///   websocket only      connected in ~1.3s
  ///   polling only        timed out at 25s
  ///   polling, websocket  timed out at 25s (from a cold process)
  ///
  /// The server is not the problem: a Node `socket.io-client` completes the
  /// same polling handshake against the same host. It is this client's polling
  /// transport. So listing polling would not buy a fallback, it would only
  /// spend 25 seconds discovering it does not have one, on every connect.
  ///
  /// Revisit if `socket_io_client` fixes its polling transport — re-run the
  /// three measurements above before changing this line.
  static const List<String> _transports = <String>['websocket'];

  /// Deadline for one engine-level open.
  ///
  /// Generous because the realtime host may be idle: a container that has
  /// scaled to zero takes tens of seconds to answer its first request, and
  /// giving up at the default would turn a cold start into a hard failure.
  static const Duration _engineTimeout = Duration(seconds: 20);

  static const Failure _connectionLost = Failure(
    AppErrorCode.connectionLost,
    AppStrings.errorConnectionLost,
  );
  static const Failure _disposedFailure = Failure(
    AppErrorCode.invalidAction,
    'The realtime gateway was disposed.',
  );
  static const Failure _noProfileFailure = Failure(
    AppErrorCode.invalidAction,
    'No profile available for the handshake.',
  );

  final Duration _connectTimeout;
  final Duration _requestTimeout;
  final Duration _pingTimeout;

  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<({String event, Map<String, dynamic> data})>
      _inboundController =
      StreamController<({String event, Map<String, dynamic> data})>.broadcast();
  final List<void Function()> _offHandlers = <void Function()>[];

  io.Socket? _socket;
  ConnectionStatus _status = ConnectionStatus.idle;
  PlayerProfile? _profile;
  String? _url;
  Future<String?> Function()? _tokenSource;
  String? _roomId;
  int _clockOffsetMs = 0;
  bool _clockSynced = false;
  Timer? _clockTimer;
  Completer<Result<void>>? _handshakeGate;
  Completer<Result<void>>? _connectCall;
  bool _manualDisconnect = false;
  bool _disposed = false;

  /// Whether the last handshake actually carried a token.
  ///
  /// Kept only for the failure log: a rejected handshake and one that was
  /// never authenticated look identical from `connect_error`, and this is what
  /// tells them apart.
  bool _sentToken = false;

  /// Supplies the credentials the game server authenticates with.
  ///
  /// The socket is the game: rooms, rounds, drawing, guessing and scoring all
  /// run over it, and the server verifies this token in a connection
  /// middleware before a single event handler runs. A socket that presents no
  /// token is refused at the handshake.
  ///
  /// A token *source* is stored rather than a token because the session is
  /// established asynchronously at startup and can be replaced by a sign-out;
  /// asking for one at handshake time always yields the current one.
  ///
  /// [roomId] is optional and only a hint for the server's reconnect path —
  /// the socket is opened *before* a room exists, since creating one is itself
  /// a socket call.
  void setCredentials({
    required Future<String?> Function() tokenSource,
    String? roomId,
  }) {
    _tokenSource = tokenSource;
    _roomId = roomId;
  }

  /// Lifecycle of the underlying socket, replaying the current value first.
  @override
  Stream<ConnectionStatus> get status async* {
    yield _status;
    yield* _statusController.stream;
  }

  /// The latest [status] value, read synchronously.
  @override
  ConnectionStatus get currentStatus => _status;

  /// Every server-pushed event as a normalised `(event, data)` pair.
  @override
  Stream<({String event, Map<String, dynamic> data})> get inbound =>
      _inboundController.stream;

  /// Measured `server - client` clock difference in milliseconds.
  @override
  int get clockOffsetMs => _clockOffsetMs;

  /// The server clock in milliseconds since the Unix epoch.
  @override
  int get serverTimeMs => DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;

  /// Connects to [url], handshakes as [profile] and synchronises the clock.
  ///
  /// Safe to call repeatedly: a second call for the same target either returns
  /// success immediately or rides along with the attempt already in flight.
  @override
  Future<Result<void>> connect(String url, PlayerProfile profile) async {
    if (_disposed) {
      return const Err<void>(_disposedFailure);
    }
    final String target = url.trim();
    final Uri? uri = Uri.tryParse(target);
    if (target.isEmpty ||
        uri == null ||
        !uri.isAbsolute ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const Err<void>(
        Failure.validation(AppStrings.validationUrlInvalid),
      );
    }

    _profile = profile;

    if (_url == target) {
      final io.Socket? live = _socket;
      if (live != null &&
          live.connected &&
          _status == ConnectionStatus.connected) {
        return const Ok<void>(null);
      }
      final Completer<Result<void>>? pending = _connectCall;
      if (pending != null) {
        return pending.future;
      }
    }

    final Completer<Result<void>> call = Completer<Result<void>>();
    _connectCall = call;
    _url = target;

    Result<void> outcome;
    try {
      outcome = await _openSocket(target, profile);
    } catch (error, stackTrace) {
      AppLogger.e('[Socket] connect threw', error, stackTrace);
      outcome = Err<void>(failureFrom(error));
    }

    if (identical(_connectCall, call)) {
      _connectCall = null;
    }
    if (!call.isCompleted) {
      call.complete(outcome);
    }
    return outcome;
  }

  /// Sends [event] with [data] and unwraps the server's `{ok, ...}` ack.
  @override
  Future<Result<Map<String, dynamic>>> request(
    String event, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) async {
    final Result<Map<String, dynamic>> raw =
        await _ack(event, data, _requestTimeout);
    return switch (raw) {
      Ok<Map<String, dynamic>>(:final Map<String, dynamic> value) =>
        _unwrapEnvelope(value),
      Err<Map<String, dynamic>>(:final Failure failure) =>
        Err<Map<String, dynamic>>(failure),
    };
  }

  /// Fires [event] with [data] and waits for nothing.
  @override
  void emit(
    String event, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) {
    final io.Socket? socket = _socket;
    if (_disposed || socket == null || !socket.connected) {
      return;
    }
    try {
      socket.emit(event, data);
    } catch (error, stackTrace) {
      AppLogger.w('[Socket] emit $event failed', error, stackTrace);
    }
  }

  /// Closes the socket deliberately and stops every reconnect attempt.
  @override
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _stopClockTimer();
    _completeGate(const Err<void>(_connectionLost));
    final io.Socket? socket = _socket;
    if (socket != null) {
      try {
        socket.disconnect();
      } catch (error, stackTrace) {
        AppLogger.w('[Socket] disconnect failed', error, stackTrace);
      }
    }
    _setStatus(ConnectionStatus.disconnected);
  }

  /// Detaches every listener, cancels every timer and closes every controller.
  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _manualDisconnect = true;
    _teardownSocket();
    _setStatus(ConnectionStatus.disconnected);
    unawaited(_statusController.close());
    unawaited(_inboundController.close());
  }

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  Future<Result<void>> _openSocket(String url, PlayerProfile profile) async {
    _teardownSocket();
    _manualDisconnect = false;
    _setStatus(ConnectionStatus.connecting);

    AppLogger.i('[Socket] connecting to $url (path $_path)');

    // `enableForceNew` matters: `io()` otherwise hands back a cached Manager
    // and its cached namespace socket, so reconnecting after a `dispose()`
    // would resurrect a dead instance.
    final io.Socket socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(_transports)
          // The connect *call* owns its own deadline (`_connectTimeout`), but
          // the engine needs one too, or a reconnect attempt against a host
          // that accepts the TCP connection and then says nothing hangs until
          // the OS gives up.
          .setTimeout(_engineTimeout.inMilliseconds)
          .disableAutoConnect()
          .enableReconnection()
          .enableForceNew()
          .setReconnectionAttempts(AppConstants.reconnectAttempts)
          .setReconnectionDelay(AppConstants.reconnectDelayMs)
          // Backoff is exponential from `reconnectionDelay`; without a ceiling
          // the later attempts drift into the tens of seconds, which is a long
          // time to sit in a round watching a "Reconnecting" banner.
          .setReconnectionDelayMax(AppConstants.reconnectDelayMaxMs)
          .setAuthFn(_supplyAuth)
          .build(),
    );
    _socket = socket;
    _attachListeners(socket);

    final Completer<Result<void>> gate = Completer<Result<void>>();
    _handshakeGate = gate;
    final Completer<Result<void>> deadline = Completer<Result<void>>();
    final Timer timer = Timer(_connectTimeout, () {
      if (!deadline.isCompleted) {
        deadline.complete(const Err<void>(Failure.timeout()));
      }
    });

    socket.connect();

    final Result<void> outcome = await Future.any(<Future<Result<void>>>[
      gate.future,
      deadline.future,
    ]);
    timer.cancel();
    if (identical(_handshakeGate, gate)) {
      _handshakeGate = null;
    }
    if (outcome case Err<void>(:final Failure failure)) {
      AppLogger.w(
        '[Socket] connect to $url failed (${failure.code.name})',
      );
    } else {
      AppLogger.i('[Socket] handshake complete as ${profile.name}');
    }
    return outcome;
  }

  /// Builds the handshake credentials, once per connection attempt.
  ///
  /// The server authenticates in a connection middleware, before any event
  /// handler runs, so the token has to travel with the handshake itself rather
  /// than in `c:hello`. A socket that arrives without one is refused outright
  /// and never reaches the game.
  ///
  /// This is a *function* rather than the fixed map `setAuth` takes, because
  /// the client is invoked again on every reconnect: `socket.dart`'s `onopen`
  /// calls it before each CONNECT packet. A map captured when the socket was
  /// first built would still be presenting the original token hours later,
  /// after a sign-out and sign-in have replaced it, and the reconnect would
  /// fail as `AUTH_ERROR` with nothing to explain why. Asking the source each
  /// time means a reconnect always presents whatever is current.
  ///
  /// [send] must be called exactly once whatever happens: the engine is open
  /// and waiting for the CONNECT packet, and never calling back would hang the
  /// socket until the connect deadline rather than failing cleanly.
  void _supplyAuth(void Function(Map<dynamic, dynamic> auth) send) {
    unawaited(() async {
      String? token;
      try {
        token = await _tokenSource?.call();
      } catch (error, stackTrace) {
        // A token that cannot be read is not a reason to skip the handshake:
        // connecting without one gets a clean `AUTH_REQUIRED` from the server,
        // which is a far more legible failure than a socket that never speaks.
        AppLogger.w('[Socket] could not read the session token', error, stackTrace);
      }

      final bool present = token != null && token.isNotEmpty;
      _sentToken = present;
      // The token itself is never logged — only whether one was found.
      AppLogger.i(
        '[Socket] handshake auth ${present ? 'token present' : 'TOKEN MISSING'}',
      );

      send(<String, dynamic>{if (present) 'token': token});
    }());
  }

  void _attachListeners(io.Socket socket) {
    _offHandlers
      ..add(socket.on(_evConnect, _onConnect))
      ..add(socket.on(_evDisconnect, _onDisconnect))
      ..add(socket.on(_evConnectError, _onConnectError))
      ..add(socket.io.on(_evError, _onTransportError))
      ..add(socket.io.on(_evReconnect, _onReconnect))
      ..add(socket.io.on(_evReconnectAttempt, _onReconnectAttempt))
      ..add(socket.io.on(_evReconnectError, _onReconnectError))
      ..add(socket.io.on(_evReconnectFailed, _onReconnectFailed));

    for (final String event in SocketEvents.serverEvents) {
      _offHandlers.add(
        socket.on(event, (dynamic payload) {
          _onServerEvent(event, payload);
        }),
      );
    }
  }

  void _teardownSocket() {
    _stopClockTimer();
    _completeGate(const Err<void>(_connectionLost));
    for (final void Function() off in _offHandlers) {
      try {
        off();
      } catch (error, stackTrace) {
        AppLogger.w(
          '[Socket] detaching a listener failed',
          error,
          stackTrace,
        );
      }
    }
    _offHandlers.clear();
    final io.Socket? socket = _socket;
    _socket = null;
    if (socket == null) {
      return;
    }
    try {
      socket.dispose();
    } catch (error, stackTrace) {
      AppLogger.w('[Socket] socket dispose failed', error, stackTrace);
    }
  }

  void _setStatus(ConnectionStatus next) {
    if (_status == next || _statusController.isClosed) {
      return;
    }
    _status = next;
    AppLogger.i('[Socket] status -> ${next.name}');
    _statusController.add(next);
  }

  void _completeGate(Result<void> outcome) {
    final Completer<Result<void>>? gate = _handshakeGate;
    if (gate == null || gate.isCompleted) {
      return;
    }
    _handshakeGate = null;
    gate.complete(outcome);
  }

  // ---------------------------------------------------------------------------
  // Transport callbacks
  // ---------------------------------------------------------------------------

  void _onConnect(dynamic _) {
    final String transport = _activeTransport();
    AppLogger.i('[Socket] connected over $transport');
    _setStatus(ConnectionStatus.connected);
    // Runs on every connect, reconnects included, and that is what restores
    // the session rather than starting a new one. A reconnecting socket is a
    // brand new connection as far as Socket.IO is concerned, so the server
    // learns who this is from `c:hello` and puts them back into the seat they
    // still hold — same player, same room, same score — then replays the board
    // and the authoritative game state. See `restoreSeat` in
    // `presence.socket.ts`.
    unawaited(_handshake());
  }

  void _onDisconnect(dynamic reason) {
    AppLogger.w('[Socket] disconnected ($reason)');
    _stopClockTimer();
    _setStatus(
      _manualDisconnect || _disposed
          ? ConnectionStatus.disconnected
          : ConnectionStatus.reconnecting,
    );
  }

  void _onConnectError(dynamic error) {
    // The user-facing copy stays deliberately vague, but a developer reading
    // the log needs the real reason: "No connection" is the same sentence
    // whether the phone is in a tunnel, the token expired, or the socket is
    // pointed at a host that cannot serve websockets at all.
    AppLogger.e(
      'Socket connection failed:\n${_describeConnectFailure(error)}',
      error,
    );
    _completeGate(const Err<void>(Failure.network()));
    if (!_manualDisconnect &&
        !_disposed &&
        _status != ConnectionStatus.connected) {
      _setStatus(ConnectionStatus.reconnecting);
    }
  }

  /// Turns a `connect_error` into something worth reading in a log.
  ///
  /// Socket.IO reports a handshake rejection and a dead host through the same
  /// callback, so the message alone rarely says which happened. The target,
  /// the transport and whether a token was even sent narrow it down, and the
  /// two failures that actually recur get named outright.
  String _describeConnectFailure(dynamic error) {
    final String detail = switch (error) {
      null => 'no error detail supplied',
      final Map<dynamic, dynamic> map =>
        map['message']?.toString() ?? map.toString(),
      _ => error.toString(),
    };

    final StringBuffer out = StringBuffer()
      ..writeln('  reason:    $detail')
      ..writeln('  url:       ${_url ?? '(none)'}')
      ..writeln('  path:      $_path')
      ..writeln('  transport: ${_transports.join(', ')}')
      ..writeln('  token:     ${_sentToken ? 'sent' : 'MISSING'}');

    // The server's handshake middleware rejects with the error code as the
    // message, so these come through verbatim.
    if (detail.contains('AUTH_REQUIRED')) {
      out.writeln(
        '  hint:      the handshake carried no token. Sign in first: the '
        'JWT from POST /api/auth/guest is what the socket authenticates with.',
      );
    } else if (detail.contains('AUTH_ERROR') ||
        detail.contains('TOKEN_EXPIRED')) {
      out.writeln(
        '  hint:      the server refused the token. Either it expired, or the '
        'realtime server signs with a different JWT_SECRET than the REST API '
        'that minted it — the two must match exactly.',
      );
    }

    if (AppConfig.current.realtimeOriginLooksUnconfigured) {
      out.writeln(
        '  hint:      the socket is pointed at the REST deployment '
        '(${AppConfig.current.apiBaseUrl}), which is serverless and cannot '
        'hold a websocket open — its /api/health reports the socket as '
        'detached. Point the app at the realtime host with '
        '--dart-define=SOCKET_URL=https://<realtime-host>, or set '
        'AppConfig.deployedRealtimeUrl.',
      );
    }

    final Uri? target = Uri.tryParse(_url ?? '');
    if (target != null && target.path.contains('socket.io')) {
      out.writeln(
        '  hint:      the URL already contains "$_path". The client appends '
        'that itself, so this asks the server for '
        '"${target.path}$_path/" and gets a 404. Configure SOCKET_URL as the '
        'bare origin.',
      );
    }

    return out.toString().trimRight();
  }

  void _onTransportError(dynamic error) {
    AppLogger.w('[Socket] transport error — ${error ?? 'no detail'}', error);
  }

  /// The transport actually in use, for the log line.
  ///
  /// Worth stating: the engine opens on polling and upgrades, so "connected"
  /// on its own does not say whether the upgrade succeeded, and a client stuck
  /// on polling is the first thing to look at when drawing feels laggy.
  String _activeTransport() {
    try {
      final Object? name = _socket?.io.engine?.transport?.name;
      return name is String && name.isNotEmpty ? name : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  void _onReconnect(dynamic attempt) {
    // `connect` fires alongside this and does the real work — re-handshaking
    // and restoring the seat. This is only the log.
    AppLogger.i('[Socket] reconnected on attempt $attempt');
  }

  void _onReconnectAttempt(dynamic attempt) {
    AppLogger.i(
      '[Socket] reconnecting (attempt $attempt of '
      '${AppConstants.reconnectAttempts}) to ${_url ?? '(none)'}',
    );
    if (!_manualDisconnect && !_disposed) {
      _setStatus(ConnectionStatus.reconnecting);
    }
  }

  /// One failed reconnection attempt, with more still to come.
  ///
  /// Deliberately not a status change: the manager is already scheduling the
  /// next attempt, so the UI should stay on "Reconnecting" rather than flicker
  /// through a failure state and back. Only [_onReconnectFailed], which fires
  /// once the attempts are exhausted, is allowed to surface as failed.
  void _onReconnectError(dynamic error) {
    AppLogger.w('[Socket] reconnect attempt failed — ${error ?? 'no detail'}');
  }

  void _onReconnectFailed(dynamic _) {
    AppLogger.e(
      '[Socket] reconnection gave up after '
      '${AppConstants.reconnectAttempts} attempts against ${_url ?? '(none)'}',
    );
    _completeGate(const Err<void>(Failure.network()));
    _setStatus(ConnectionStatus.failed);
  }

  void _onServerEvent(String event, dynamic payload) {
    if (_disposed || _inboundController.isClosed) {
      return;
    }
    final Map<String, dynamic> data = _normalisePayload(payload);
    if (event == SocketEvents.serverTimeSync) {
      final int broadcast = asInt(data['serverTimeMs']);
      if (broadcast > 0) {
        _foldServerTime(broadcast);
      }
    }
    _inboundController.add((event: event, data: data));
  }

  /// Coerces any inbound payload into a string-keyed map.
  ///
  /// Socket.IO hands over whatever the server emitted, so a scalar, a `null`
  /// or a single-element argument list must never crash a repository.
  Map<String, dynamic> _normalisePayload(dynamic payload) {
    if (payload == null) {
      return <String, dynamic>{};
    }
    if (payload is Map) {
      return asMap(payload);
    }
    if (payload is List && payload.length == 1) {
      return _normalisePayload(payload.first);
    }
    return <String, dynamic>{'value': payload};
  }

  // ---------------------------------------------------------------------------
  // Handshake, acks and clock sync
  // ---------------------------------------------------------------------------

  Future<void> _handshake() async {
    final PlayerProfile? profile = _profile;
    if (profile == null) {
      _completeGate(const Err<void>(_noProfileFailure));
      return;
    }
    final String? idToken = await _tokenSource?.call();
    final Result<Map<String, dynamic>> ack = await request(
      SocketEvents.clientHello,
      <String, dynamic>{
        'profile': profile.toJson(),
        'idToken': ?idToken,
        'roomId': ?_roomId,
      },
    );
    switch (ack) {
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        // The ack already carries the server clock, so `serverTimeMs` is
        // usable the moment `connect` returns. Release the caller on that
        // coarse seed and let the round-trip refinement land afterwards —
        // five samples could otherwise outlast the connect deadline.
        final int serverNow = asInt(value['serverTimeMs']);
        if (serverNow > 0) {
          _foldServerTime(serverNow);
        }
        // The server answers with the room it put this player back into, when
        // it found one still holding their seat. Remembered so a later
        // reconnect can name it, and logged because "did the rejoin work?" is
        // the first question asked of any reconnect bug. The code identifies a
        // room, not a person, and reveals nothing about the word in play.
        final String restored = asString(value['roomCode']);
        if (restored.isNotEmpty) {
          _roomId = restored;
          AppLogger.i('[Socket] session restored into room $restored');
        }
        _completeGate(const Ok<void>(null));
        await _syncClock();
        _startClockTimer();
      case Err<Map<String, dynamic>>(:final Failure failure):
        AppLogger.e('[Socket] handshake rejected (${failure.code.name})');
        _completeGate(Err<void>(failure));

        // A live socket whose handshake failed is the worst of both worlds:
        // the transport says connected, so nothing retries, but the server has
        // not seated this player and every event they send will be refused.
        // Dropping it converts that into an ordinary disconnect, which the
        // manager already knows how to retry — and the retry re-reads the
        // token, so an expired one that has since been refreshed recovers on
        // its own. A deliberate teardown is exempt: nobody is waiting on it.
        if (!_manualDisconnect && !_disposed) {
          AppLogger.w('[Socket] dropping the socket so the retry can re-auth');
          _setStatus(ConnectionStatus.reconnecting);
          try {
            _socket?.io.engine?.close();
          } catch (error, stackTrace) {
            AppLogger.w('[Socket] could not close the engine', error, stackTrace);
          }
        }
    }
  }

  /// Emits [event] and resolves the raw ack map, leaving the `{ok, ...}`
  /// envelope alone — `c:time:ping` answers `{t0, t1}` and has none.
  Future<Result<Map<String, dynamic>>> _ack(
    String event,
    Map<String, dynamic> data,
    Duration timeout,
  ) async {
    final io.Socket? socket = _socket;
    if (_disposed || socket == null || !socket.connected) {
      return const Err<Map<String, dynamic>>(_connectionLost);
    }
    final Completer<Result<Map<String, dynamic>>> completer =
        Completer<Result<Map<String, dynamic>>>();
    final Timer timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(const Err<Map<String, dynamic>>(Failure.timeout()));
      }
    });
    try {
      socket.emitWithAck(
        event,
        data,
        ack: (dynamic response) {
          if (completer.isCompleted) {
            return;
          }
          if (response is Map) {
            completer.complete(Ok<Map<String, dynamic>>(asMap(response)));
          } else {
            completer
                .complete(const Err<Map<String, dynamic>>(Failure.server()));
          }
        },
      );
    } catch (error, stackTrace) {
      timer.cancel();
      AppLogger.e('[Socket] request $event failed', error, stackTrace);
      return Err<Map<String, dynamic>>(failureFrom(error));
    }
    final Result<Map<String, dynamic>> result = await completer.future;
    timer.cancel();
    return result;
  }

  Result<Map<String, dynamic>> _unwrapEnvelope(Map<String, dynamic> ack) {
    if (asBool(ack['ok'])) {
      final Map<String, dynamic> payload = Map<String, dynamic>.of(ack)
        ..remove('ok');
      return Ok<Map<String, dynamic>>(payload);
    }
    final Object? error = ack['error'];
    if (error != null) {
      return Err<Map<String, dynamic>>(Failure.fromJson(asMap(error)));
    }
    return const Err<Map<String, dynamic>>(Failure.server());
  }

  /// Runs `AppConstants.timeSyncSamples` round trips and keeps the offset of
  /// the fastest one.
  Future<void> _syncClock() async {
    int? bestOffset;
    int bestRtt = -1;
    for (int sample = 0; sample < AppConstants.timeSyncSamples; sample++) {
      final io.Socket? socket = _socket;
      if (_disposed || socket == null || !socket.connected) {
        break;
      }
      final int t0 = DateTime.now().millisecondsSinceEpoch;
      final Result<Map<String, dynamic>> ack = await _ack(
        SocketEvents.clientTimePing,
        <String, dynamic>{'t0': t0},
        _pingTimeout,
      );
      if (ack case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value)) {
        final int t2 = DateTime.now().millisecondsSinceEpoch;
        final int t1 = asInt(value['t1']);
        final int sentAt = asInt(value['t0'], t0);
        final int rtt = t2 - sentAt;
        if (t1 > 0 && rtt >= 0 && (bestRtt < 0 || rtt < bestRtt)) {
          final int half = rtt ~/ 2;
          bestRtt = rtt;
          bestOffset = t1 - sentAt - half;
        }
      } else {
        break;
      }
    }
    final int? offset = bestOffset;
    if (offset != null) {
      _clockSynced = true;
      _clockOffsetMs = offset;
      AppLogger.d('[Socket] clock offset ${offset}ms, rtt ${bestRtt}ms');
    }
  }

  /// Folds a one-way server timestamp into the offset.
  ///
  /// Broadcasts and the handshake ack carry no round-trip information, so they
  /// are biased by one-way latency. They seed the offset before the first
  /// measurement, and afterwards only nudge it, leaving the round-trip
  /// estimate in charge.
  void _foldServerTime(int serverNowMs) {
    final int candidate = serverNowMs - DateTime.now().millisecondsSinceEpoch;
    if (!_clockSynced) {
      _clockSynced = true;
      _clockOffsetMs = candidate;
      return;
    }
    _clockOffsetMs = (_clockOffsetMs * 3 + candidate) ~/ 4;
  }

  void _startClockTimer() {
    _stopClockTimer();
    _clockTimer = Timer.periodic(
      const Duration(seconds: AppConstants.timeSyncIntervalSeconds),
      (Timer _) {
        unawaited(_syncClock());
      },
    );
  }

  void _stopClockTimer() {
    _clockTimer?.cancel();
    _clockTimer = null;
  }
}
