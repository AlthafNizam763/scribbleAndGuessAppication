import 'dart:async';

import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// Owns the user-visible connection story on top of a [RealtimeGateway].
///
/// The gateway reports raw transport truth, which flaps: a Wi-Fi handover can
/// produce `disconnected -> reconnecting -> connected` inside a few hundred
/// milliseconds, and a banner bound straight to it would strobe. This service
/// sits in between and only surfaces the "down" states once they have
/// persisted for [dropGrace], while promoting recoveries immediately. It also
/// remembers the last [connect] target so [retry] can replay it after the
/// automatic attempts are exhausted.
///
/// It knows nothing about Socket.IO — it talks to [RealtimeGateway] only, so
/// swapping the transport changes nothing here.
class ConnectivityService {
  /// Wraps [gateway] and starts watching its status immediately.
  ///
  /// [dropGrace] is how long a disconnect must persist before it is surfaced.
  ConnectivityService({
    required RealtimeGateway gateway,
    Duration dropGrace = const Duration(milliseconds: 600),
  })  : _gateway = gateway,
        _dropGrace = dropGrace,
        _status = gateway.currentStatus {
    _subscription = gateway.status.listen(_onGatewayStatus);
  }

  static const Failure _noTarget = Failure(
    AppErrorCode.invalidAction,
    'No server has been connected to yet.',
  );

  final RealtimeGateway _gateway;
  final Duration _dropGrace;
  final StreamController<ConnectionStatus> _controller =
      StreamController<ConnectionStatus>.broadcast();

  StreamSubscription<ConnectionStatus>? _subscription;
  Timer? _dropTimer;
  ConnectionStatus _status;
  ConnectionStatus? _pending;
  PlayerProfile? _profile;
  String? _url;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  /// How long a disconnect must persist before the UI is told about it.
  Duration get dropGrace => _dropGrace;

  /// The connection state the UI should currently render.
  ConnectionStatus get status => _status;

  /// The debounced status stream, replaying [status] to every new listener.
  ///
  /// Emits only on change and completes on [dispose].
  Stream<ConnectionStatus> get onStatusChanged async* {
    yield _status;
    yield* _controller.stream;
  }

  /// How many times the connection has dropped into reconnecting since the
  /// last successful connect.
  ///
  /// Resets to zero whenever the connection comes back or a manual [retry]
  /// starts, so it reads as "attempts on the current outage".
  int get reconnectAttempts => _reconnectAttempts;

  /// Whether the socket is live right now.
  bool get isConnected => _status == ConnectionStatus.connected;

  /// Whether the app is mid-recovery and should show a soft banner.
  bool get isRecovering =>
      _status == ConnectionStatus.connecting ||
      _status == ConnectionStatus.reconnecting;

  /// Whether offering the player a manual retry button makes sense.
  ///
  /// True only once the automatic attempts have stopped and there is a target
  /// to retry against.
  bool get canRetry =>
      !_disposed &&
      _url != null &&
      _profile != null &&
      (_status == ConnectionStatus.disconnected ||
          _status == ConnectionStatus.failed);

  /// Connects [gateway] to [url] as [profile] and remembers the target.
  ///
  /// The remembered target is what [retry] replays.
  Future<Result<void>> connect(String url, PlayerProfile profile) {
    if (_disposed) {
      return Future<Result<void>>.value(const Err<void>(_noTarget));
    }
    _url = url;
    _profile = profile;
    _reconnectAttempts = 0;
    return _gateway.connect(url, profile);
  }

  /// Reconnects to the last target after the automatic attempts gave up.
  ///
  /// Fails with [AppErrorCode.invalidAction] when [connect] was never called.
  Future<Result<void>> retry() {
    final String? url = _url;
    final PlayerProfile? profile = _profile;
    if (_disposed || url == null || profile == null) {
      return Future<Result<void>>.value(const Err<void>(_noTarget));
    }
    AppLogger.i('ConnectivityService: manual retry');
    _reconnectAttempts = 0;
    _cancelPending();
    return _gateway.connect(url, profile);
  }

  /// Disconnects deliberately, which surfaces as
  /// [ConnectionStatus.disconnected] without waiting out [dropGrace].
  Future<void> disconnect() async {
    if (_disposed) {
      return;
    }
    await _gateway.disconnect();
    _cancelPending();
    _publish(ConnectionStatus.disconnected);
  }

  /// Cancels the subscription and timer and closes the status stream.
  ///
  /// The wrapped gateway is left alone: whoever created it owns it.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _dropTimer?.cancel();
    _dropTimer = null;
    _pending = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_controller.close());
  }

  void _onGatewayStatus(ConnectionStatus next) {
    if (_disposed) {
      return;
    }
    // Down states are held back; anything that reads as progress wins now.
    if (next == ConnectionStatus.disconnected ||
        next == ConnectionStatus.reconnecting) {
      _pending = next;
      _dropTimer ??= Timer(_dropGrace, _flushPending);
      return;
    }
    _cancelPending();
    _publish(next);
  }

  void _flushPending() {
    _dropTimer = null;
    final ConnectionStatus? pending = _pending;
    _pending = null;
    if (pending == null || _disposed) {
      return;
    }
    _publish(pending);
  }

  void _cancelPending() {
    _dropTimer?.cancel();
    _dropTimer = null;
    _pending = null;
  }

  void _publish(ConnectionStatus next) {
    if (_status == next || _controller.isClosed) {
      return;
    }
    if (next == ConnectionStatus.reconnecting) {
      _reconnectAttempts++;
    } else if (next == ConnectionStatus.connected) {
      _reconnectAttempts = 0;
    }
    _status = next;
    AppLogger.i('ConnectivityService: surfacing ${next.name}');
    _controller.add(next);
  }
}
