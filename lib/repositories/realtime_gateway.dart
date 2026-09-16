import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/player_profile.dart';

/// The transport-agnostic seam every realtime repository is built on.
///
/// A gateway moves named events with JSON payloads in both directions and
/// keeps a server-synchronised clock. The Socket.IO implementation satisfies
/// it today; a future Firebase or in-memory implementation can satisfy it
/// without a single change above this line, because nothing here mentions a
/// socket, a channel or a document.
///
/// ## Ack contract
///
/// Every request-shaped event uses the same envelope, mirrored in
/// `server/src/protocol.js`:
///
/// ```json
/// { "ok": true,  "room": { } }
/// { "ok": false, "error": { "code": "roomFull", "message": "..." } }
/// ```
///
/// [request] unwraps that envelope: `ok: true` becomes an [Ok] holding the
/// payload map with the `ok` flag stripped, while `ok: false` becomes an [Err]
/// holding `Failure.fromJson(error)`. A missing, malformed or non-map ack is
/// an [Err] with [AppErrorCode.serverError], and an ack that never arrives
/// within the transport deadline is [AppErrorCode.timeout] — a caller can rely
/// on every [request] future completing.
///
/// ## Authority
///
/// The gateway is a pipe, not a referee. It never invents an event, never
/// rewrites a payload and never derives scores, phases or permissions. The
/// server owns all of those, so a payload that arrives on [inbound] outranks
/// anything the client believes.
///
/// ## Reconnection
///
/// Reconnects are automatic and bounded by `AppConstants.reconnectAttempts`
/// and `AppConstants.reconnectDelayMs`. [status] reports the whole lifecycle:
/// [ConnectionStatus.connecting] on the first attempt,
/// [ConnectionStatus.reconnecting] while retrying,
/// [ConnectionStatus.connected] once live, [ConnectionStatus.disconnected]
/// after an intentional [disconnect] and [ConnectionStatus.failed] when the
/// attempts are exhausted.
///
/// On every successful (re)connect the gateway re-sends the handshake with the
/// profile passed to [connect] and re-runs clock synchronisation, then the
/// server replays the authoritative state (room, game and a board snapshot).
/// Events emitted while disconnected are dropped rather than queued — stale
/// strokes and stale guesses must never arrive late — so callers treat a
/// reconnect as "resync from the pushed state", not "resume where I was".
abstract interface class RealtimeGateway {
  /// Lifecycle of the underlying connection.
  ///
  /// Replays the current value to new listeners and emits only on change, so
  /// a banner can bind to it directly. Completes on [dispose].
  Stream<ConnectionStatus> get status;

  /// The latest value of [status], read synchronously.
  ///
  /// Starts at [ConnectionStatus.idle] before the first [connect].
  ConnectionStatus get currentStatus;

  /// Server time in milliseconds since the Unix epoch.
  ///
  /// Computed as the local clock plus the measured [clockOffsetMs], which
  /// makes it the only clock allowed to drive the turn countdown: device
  /// clocks are unsynchronised and can even move backwards, while every
  /// `turnStartMs` / `turnEndMs` stamp comes from the server. Before the first
  /// successful sync it degrades to the local clock.
  int get serverTimeMs;

  /// Measured `server - client` clock difference in milliseconds.
  ///
  /// Estimated from a handful of round trips (`AppConstants.timeSyncSamples`)
  /// and refreshed every `AppConstants.timeSyncIntervalSeconds`, taking the
  /// median to shrug off outliers. `0` until the first sync completes.
  int get clockOffsetMs;

  /// Every server-pushed event, as an `(event, data)` pair.
  ///
  /// `event` is one of the `s:` strings in `SocketEvents`, and `data` is the
  /// raw payload map — already normalised to `Map<String, dynamic>`, and empty
  /// rather than null for payload-less events. This is a broadcast stream:
  /// each repository filters it for the events it cares about, and a late
  /// listener sees only what arrives from then on. Completes on [dispose].
  Stream<({String event, Map<String, dynamic> data})> get inbound;

  /// Sends [event] with [data] and waits for the server's ack.
  ///
  /// Use for every action that needs a verdict — creating or joining a room,
  /// starting a game, selecting a word, sending chat, moderating a player. The
  /// returned map is the ack payload without its `ok` flag; see the ack
  /// contract above for how failures are shaped.
  ///
  /// Returns [AppErrorCode.connectionLost] when called while not connected,
  /// rather than silently dropping the request.
  Future<Result<Map<String, dynamic>>> request(
    String event, [
    Map<String, dynamic> data,
  ]);

  /// Sends [event] with [data] and does not wait for anything.
  ///
  /// Use only for high-frequency, loss-tolerant traffic such as the `c:draw:*`
  /// stream, where a dropped packet is corrected by the next board snapshot.
  /// Silently does nothing when not connected, so callers must not read
  /// success into the absence of an error.
  void emit(String event, [Map<String, dynamic> data]);

  /// Connects to [url] and performs the handshake as [profile].
  ///
  /// [url] is an absolute `http`/`https` origin, typically
  /// `AppSettings.serverUrl`. On success the handshake ack has been received,
  /// the clock is synchronised and [currentStatus] is
  /// [ConnectionStatus.connected]; [profile] is retained so automatic
  /// reconnects can repeat the handshake unattended.
  ///
  /// Calling it while already connected to the same [url] is a no-op success;
  /// a different [url] reconnects. Fails with [AppErrorCode.validation] for a
  /// malformed URL, [AppErrorCode.network] when the host is unreachable and
  /// [AppErrorCode.timeout] when the handshake stalls.
  Future<Result<void>> connect(String url, PlayerProfile profile);

  /// Closes the connection deliberately and stops all reconnect attempts.
  ///
  /// Settles [status] on [ConnectionStatus.disconnected] and completes once
  /// the transport is down. Safe to call when already disconnected; the
  /// gateway can be reused by calling [connect] again.
  Future<void> disconnect();

  /// Tears the gateway down for good.
  ///
  /// Disconnects, cancels the clock-sync timer and closes [status] and
  /// [inbound]. Safe to call more than once; the instance is unusable
  /// afterwards.
  void dispose();
}
