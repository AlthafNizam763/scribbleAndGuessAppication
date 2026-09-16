import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/drawing_event.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';

/// Canvas seam between the UI and whatever backend relays strokes.
///
/// Traffic is deliberately asymmetric. Inbound [events] are the shared board:
/// the implementation applies them to a `DrawingBoard` in the order received.
/// Outbound calls are only requests to the relay — the server checks that the
/// caller is the current drawer and drops the stroke otherwise, so a watching
/// client must not be able to paint by calling these methods directly.
///
/// All coordinates are normalized to `0..1` against the fixed
/// `AppConstants.canvasAspectRatio` box (see `Geometry.normalize`), which
/// keeps a stroke identical on every screen size. Points should be simplified
/// with `Geometry.simplify` and batched at `AppConstants.strokeBatchMs` before
/// being sent.
///
/// The wire is fire-and-forget for latency, so an [Ok] means "handed to the
/// transport", not "acknowledged by the server". The authoritative board is
/// whatever arrives back as a [BoardSnapshot] on join or after a reconnect.
///
/// No method throws. Failures are returned as [Err] carrying a [Failure].
abstract interface class DrawingRepository {
  /// Board mutations to apply, in arrival order.
  ///
  /// Carries the sealed [DrawingEvent] variants: [StrokeBegan],
  /// [StrokeAppended], [StrokeEnded], [StrokeUndone], [StrokeRedone],
  /// [BoardCleared] and the full [BoardSnapshot] sent on join or reconnect. A
  /// snapshot replaces the local board wholesale and is the recovery path
  /// after dropped events. Completes only on [dispose].
  Stream<DrawingEvent> get events;

  /// Announces a new [stroke] whose id, colour, width and tool are fixed for
  /// its lifetime.
  ///
  /// Send the first points with it; the rest follow through [appendPoints].
  /// Fails with [AppErrorCode.notDrawer] when the implementation can already
  /// tell the caller is not drawing, or [AppErrorCode.connectionLost] when the
  /// transport is down.
  Future<Result<void>> beginStroke(Stroke stroke);

  /// Appends a batch of [points] to the open stroke [strokeId].
  ///
  /// Points must be normalized and in draw order; batching keeps the message
  /// rate bounded. Points for an unknown or already-ended stroke are dropped
  /// by the server rather than reopening it.
  Future<Result<void>> appendPoints(String strokeId, List<StrokePoint> points);

  /// Marks the stroke [strokeId] finished so it can be committed.
  ///
  /// After this, [appendPoints] for the same id has no effect.
  Future<Result<void>> endStroke(String strokeId);

  /// Asks to undo the drawer's most recent stroke.
  ///
  /// The client must not remove the stroke on its own: the removal is applied
  /// when the matching [StrokeUndone] arrives on [events], so every device
  /// converges on the same board. Fails with [AppErrorCode.notDrawer] for a
  /// non-drawer.
  Future<Result<void>> undo();

  /// Asks to restore the most recently undone stroke.
  ///
  /// Applied only when the matching [StrokeRedone] arrives on [events]. Fails
  /// with [AppErrorCode.notDrawer], and is a no-op when the redo stack is
  /// empty.
  Future<Result<void>> redo();

  /// Asks to wipe the board for everyone. Drawer only.
  ///
  /// Applied when [BoardCleared] arrives on [events]. Fails with
  /// [AppErrorCode.notDrawer].
  Future<Result<void>> clear();

  /// Releases subscriptions and closes [events].
  ///
  /// Safe to call more than once; the instance is unusable afterwards.
  void dispose();
}
