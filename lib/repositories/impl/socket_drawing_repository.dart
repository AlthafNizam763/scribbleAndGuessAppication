import 'dart:async';

import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/drawing_event.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';
import 'package:scribble_guess/repositories/drawing_repository.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// The gateway's inbound record, aliased for readability.
typedef _Inbound = ({String event, Map<String, dynamic> data});

/// [DrawingRepository] backed by a [RealtimeGateway].
///
/// Inbound `s:draw:*` pushes are decoded into the sealed [DrawingEvent]
/// variants and forwarded in arrival order, including the [BoardSnapshot] a
/// late joiner or a reconnecting client receives. Outbound calls travel on the
/// fire-and-forget `c:draw:*` channel, so an [Ok] means "handed to the
/// transport", never "accepted by the server" — the server still checks that
/// the caller is the drawer and drops the stroke otherwise.
///
/// ## Why local operations are echoed back onto [events]
///
/// The server relays a stroke to the room *except the socket that sent it*
/// (`emitToRoomExcept`), deliberately: echoing it back would tie the drawer's
/// own line to their own network latency. The consequence is that nothing the
/// local player draws ever arrives on [events] — so if the board is built only
/// from inbound traffic, the drawer is the one person who cannot see their own
/// drawing. Their strokes disappear the moment the live preview is dropped,
/// and their own undo, redo and clear appear to do nothing.
///
/// So the two hot-path operations — [beginStroke] and [appendPoints] — are
/// echoed back onto [events] locally, in the order they were sent. That keeps
/// one rule for every device, that the board is the ordered replay of [events],
/// with no duplication: the sender is exactly who the server leaves out. An
/// operation the transport refuses is not echoed, and anything that drifts is
/// corrected wholesale by the [BoardSnapshot] the server sends on join and on
/// reconnect.
///
/// A malformed payload is logged and dropped; it never breaks the gateway
/// subscription and never reaches the board.
class SocketDrawingRepository implements DrawingRepository {
  /// Starts listening to [gateway] for board traffic.
  SocketDrawingRepository(RealtimeGateway gateway) : _gateway = gateway {
    _inboundSubscription = _gateway.inbound.listen(
      _onInbound,
      onError: _onStreamError,
    );
  }

  final RealtimeGateway _gateway;

  final StreamController<DrawingEvent> _eventController =
      StreamController<DrawingEvent>.broadcast();

  StreamSubscription<_Inbound>? _inboundSubscription;

  bool _disposed = false;

  @override
  Stream<DrawingEvent> get events => _eventController.stream;

  @override
  Future<Result<void>> beginStroke(Stroke stroke) async {
    if (stroke.id.isEmpty) {
      return const Err<void>(
        Failure(AppErrorCode.validation, AppStrings.errorValidation),
      );
    }
    return _sendAndEcho(
      SocketEvents.clientDrawBegin,
      <String, dynamic>{'stroke': stroke.toJson()},
      StrokeBegan(stroke),
    );
  }

  @override
  Future<Result<void>> appendPoints(
    String strokeId,
    List<StrokePoint> points,
  ) async {
    if (strokeId.isEmpty) {
      return const Err<void>(
        Failure(AppErrorCode.validation, AppStrings.errorValidation),
      );
    }
    if (points.isEmpty) {
      // An empty batch carries nothing; sending it would only add traffic.
      return const Ok<void>(null);
    }
    return _sendAndEcho(
      SocketEvents.clientDrawAppend,
      <String, dynamic>{
        'strokeId': strokeId,
        'points': <List<double>>[
          for (final StrokePoint point in points) point.toJsonList(),
        ],
      },
      StrokeAppended(strokeId, List<StrokePoint>.unmodifiable(points)),
    );
  }

  @override
  Future<Result<void>> endStroke(String strokeId) async {
    if (strokeId.isEmpty) {
      return const Err<void>(
        Failure(AppErrorCode.validation, AppStrings.errorValidation),
      );
    }
    // No echo: `StrokeEnded` is a no-op on the board — the stroke and all of
    // its points are already there — so emitting it locally would say nothing.
    return _send(
      SocketEvents.clientDrawEnd,
      <String, dynamic>{'strokeId': strokeId},
    );
  }

  // Undo, redo and clear are *not* echoed. Which stroke each one moves is the
  // server's decision — `DrawingService.undo` drops the last stroke authored by
  // this user, `redo` pops the board's own redo stack — and guessing at it here
  // is how the two boards would drift apart. They are also one-off button
  // presses rather than the per-frame hot path, so the round trip costs nothing
  // anybody can perceive. The server broadcasts all three to the whole room,
  // the sender included, and the board applies them like any other event.
  @override
  Future<Result<void>> undo() => _send(SocketEvents.clientDrawUndo);

  @override
  Future<Result<void>> redo() => _send(SocketEvents.clientDrawRedo);

  @override
  Future<Result<void>> clear() => _send(SocketEvents.clientDrawClear);

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_inboundSubscription?.cancel());
    _inboundSubscription = null;
    unawaited(_eventController.close());
  }

  // ---------------------------------------------------------------------------
  // Inbound
  // ---------------------------------------------------------------------------

  void _onInbound(_Inbound message) {
    switch (message.event) {
      case SocketEvents.serverDrawBegin:
        _emit(_parseBegin(message.data));
      case SocketEvents.serverDrawAppend:
        _emit(_parseAppend(message.data));
      case SocketEvents.serverDrawEnd:
        _emit(_parseEnd(message.data));
      case SocketEvents.serverDrawUndo:
        _emit(_parseUndo(message.data));
      case SocketEvents.serverDrawRedo:
        _emit(_parseRedo(message.data));
      case SocketEvents.serverDrawClear:
        _emit(const BoardCleared());
      case SocketEvents.serverDrawSnapshot:
        _emit(_parseSnapshot(message.data));
    }
  }

  DrawingEvent? _parseBegin(Map<String, dynamic> data) => _guardParse(
        'begin',
        () {
          final Stroke stroke = Stroke.fromJson(_strokePayload(data));
          return stroke.id.isEmpty ? null : StrokeBegan(stroke);
        },
      );

  DrawingEvent? _parseAppend(Map<String, dynamic> data) => _guardParse(
        'append',
        () {
          final String strokeId = asString(data['strokeId']);
          final List<StrokePoint> points = <StrokePoint>[
            for (final dynamic raw in asList(data['points']))
              StrokePoint.fromJsonList(raw),
          ];
          if (strokeId.isEmpty || points.isEmpty) {
            return null;
          }
          return StrokeAppended(strokeId, points);
        },
      );

  DrawingEvent? _parseEnd(Map<String, dynamic> data) => _guardParse(
        'end',
        () {
          final String strokeId = asString(data['strokeId']);
          return strokeId.isEmpty ? null : StrokeEnded(strokeId);
        },
      );

  DrawingEvent? _parseUndo(Map<String, dynamic> data) => _guardParse(
        'undo',
        () {
          final String strokeId = asString(data['strokeId']);
          return strokeId.isEmpty ? null : StrokeUndone(strokeId);
        },
      );

  DrawingEvent? _parseRedo(Map<String, dynamic> data) => _guardParse(
        'redo',
        () {
          final Stroke stroke = Stroke.fromJson(_strokePayload(data));
          return stroke.id.isEmpty ? null : StrokeRedone(stroke);
        },
      );

  /// The snapshot is the recovery path, so an empty stroke list is legal: it
  /// means the board is genuinely blank.
  DrawingEvent? _parseSnapshot(Map<String, dynamic> data) => _guardParse(
        'snapshot',
        () => BoardSnapshot(<Stroke>[
          for (final dynamic raw in asList(data['strokes']))
            Stroke.fromJson(asMap(raw)),
        ]),
      );

  void _onStreamError(Object error, StackTrace stackTrace) {
    AppLogger.w(
      'SocketDrawingRepository: gateway stream error',
      error,
      stackTrace,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Unwraps the `{stroke: ...}` envelope, tolerating a bare stroke payload.
  Map<String, dynamic> _strokePayload(Map<String, dynamic> data) {
    final Object? raw = data['stroke'];
    return raw is Map ? asMap(raw) : data;
  }

  /// Runs [parse], logging and swallowing anything it throws.
  DrawingEvent? _guardParse(String label, DrawingEvent? Function() parse) {
    try {
      return parse();
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketDrawingRepository: dropped malformed draw $label',
        error,
        stackTrace,
      );
      return null;
    }
  }

  void _emit(DrawingEvent? event) {
    if (event == null || _disposed || _eventController.isClosed) {
      return;
    }
    _eventController.add(event);
  }

  /// [_send], plus [echo] applied to the local board when the send succeeded.
  ///
  /// The echo is emitted synchronously, before the future resolves, so two
  /// calls made in order reach the board in that order — a stroke is always
  /// begun before points are appended to it.
  Future<Result<void>> _sendAndEcho(
    String event,
    Map<String, dynamic> data,
    DrawingEvent? echo,
  ) async {
    final Result<void> sent = await _send(event, data);
    if (sent is Ok<void>) {
      _emit(echo);
    }
    return sent;
  }

  /// Hands [data] to the fire-and-forget channel, refusing while offline so a
  /// silently dropped stroke is reported instead of looking like a success.
  Future<Result<void>> _send(
    String event, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) async {
    if (_gateway.currentStatus != ConnectionStatus.connected) {
      return const Err<void>(
        Failure(AppErrorCode.connectionLost, AppStrings.errorConnectionLost),
      );
    }
    try {
      _gateway.emit(event, data);
      return const Ok<void>(null);
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketDrawingRepository: failed to emit $event',
        error,
        stackTrace,
      );
      return Err<void>(failureFrom(error));
    }
  }
}
