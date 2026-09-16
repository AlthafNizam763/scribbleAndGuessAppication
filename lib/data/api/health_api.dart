import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// What `GET /api/health` said about the backend.
///
/// Every field is a report *about* the REST deployment and what it can see
/// from where it stands. None of it is evidence that this device has a
/// working realtime connection — see [socketStatus].
class BackendHealth {
  const BackendHealth({
    required this.reachable,
    required this.status,
    required this.database,
    required this.socketMode,
    required this.socketStatus,
    required this.socketUrl,
    required this.socketReason,
  });

  /// Parses the payload `GET /api/health` returns.
  factory BackendHealth.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> socket = asMap(json['socket']);
    return BackendHealth(
      reachable: true,
      status: asString(json['status']),
      database: asString(json['database']),
      // The realtime deployment answers with a flat `socket: "attached"`
      // string, the REST one with a `{mode, status, ...}` report of its probe.
      // Both shapes are accepted so either host can be asked.
      socketMode: socket.isEmpty
          ? asString(json['socket'])
          : asString(socket['mode']),
      socketStatus: socket.isEmpty
          ? asString(json['socket'])
          : asString(socket['status']),
      socketUrl: asString(socket['url']),
      socketReason: asString(socket['reason']),
    );
  }

  /// A backend that could not be reached at all.
  static const BackendHealth unreachable = BackendHealth(
    reachable: false,
    status: '',
    database: '',
    socketMode: '',
    socketStatus: '',
    socketUrl: '',
    socketReason: '',
  );

  /// Whether the REST deployment answered at all.
  ///
  /// This is the only field that says something about *this device's* network,
  /// and it says it about HTTP only.
  final bool reachable;

  /// `healthy` or `degraded`.
  final String status;

  /// `connected` while Mongo is reachable from the backend.
  final String database;

  /// How the REST deployment relates to the realtime server: `attached`,
  /// `external` or `not_configured`.
  final String socketMode;

  /// What the REST deployment's probe of the realtime host found: `up`,
  /// `down`, `unknown` — or, from the realtime host itself, `attached`.
  final String socketStatus;

  /// The origin the REST deployment probed, which is whatever `SOCKET_URL` is
  /// set to in *its* environment — not necessarily the one this app uses.
  final String socketUrl;

  /// Why the probe failed, when it did.
  final String socketReason;

  /// Whether the backend can serve sign-in and the profile.
  ///
  /// Mongo is the thing that has to be up: a `degraded` status caused only by
  /// the realtime probe still leaves REST perfectly able to mint a token.
  bool get restUsable => reachable && database == 'connected';

  /// Whether the backend believes the realtime server is up.
  ///
  /// Advisory only, and never a substitute for the socket's own status. This
  /// is one server's opinion of another, taken seconds ago and possibly
  /// through a `SOCKET_URL` that differs from the one this build connects to.
  /// Only an established Socket.IO connection proves realtime connectivity.
  bool get realtimeLooksUp =>
      socketStatus == 'up' || socketStatus == 'attached';

  @override
  String toString() => reachable
      ? 'BackendHealth($status, db: $database, '
          'socket: $socketMode/$socketStatus'
          '${socketReason.isEmpty ? '' : ' — $socketReason'})'
      : 'BackendHealth(unreachable)';
}

/// `GET /api/health`, for diagnosing *why* something failed.
///
/// ## What this is for, and what it is not for
///
/// It exists to tell three failures apart that otherwise produce the same
/// "no connection" message: the REST deployment being down, its database
/// being down, and the realtime host being down. Knowing which one it is
/// changes the advice a player gets and is the difference between a five
/// minute diagnosis and an hour of guessing.
///
/// It is *not* a connectivity check for the game. The socket decides that,
/// and only the socket: this endpoint lives on a different host, so a 200
/// here says nothing about whether this device can hold a websocket open to
/// the realtime server. Nothing may gate the game on this call, and nothing
/// may report "connected" on the strength of it.
///
/// Unauthenticated, so it works before sign-in — which is exactly when a
/// misconfigured backend needs diagnosing.
class HealthApi {
  const HealthApi(this._client);

  final ApiClient _client;

  /// Asks the backend how it is doing.
  ///
  /// Never fails: an unreachable backend is itself the answer, and is
  /// reported as [BackendHealth.unreachable] rather than an error, because
  /// every caller is already handling a failure when it reaches here.
  Future<BackendHealth> check() async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/health',
      authenticated: false,
    );
    return response.fold<BackendHealth>(
      BackendHealth.fromJson,
      // A 503 still carries a body worth reading: it is what the backend
      // returns when Mongo is down, which is precisely the case this is here
      // to identify. The client has already turned it into a `Failure`
      // though, so the detail is gone and only "not usable" survives.
      (_) => BackendHealth.unreachable,
    );
  }
}
