import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';

/// The *Meridian*, as the screen is allowed to ask for it.
///
/// ## Why [move] does not await anything
///
/// It is sent while a thumb is on the stick — twenty times a second on a
/// touch device — and it is a *direction*, not a position. Awaiting an ack per
/// frame would put a round trip in the input path and queue stale directions
/// behind a slow network, and the next frame's direction is always better than
/// a retry of the last one. The server clamps it to a unit vector, integrates
/// it against the floor plan on its own tick, and the result comes back in the
/// broadcast like everything else.
///
/// Every other method here goes through the acked path, because every other
/// action is a discrete decision somebody can be told they cannot take.
class SpaceMysteryController {
  const SpaceMysteryController(this._ref);

  final Ref _ref;

  /// Pushes a movement intent. Never a position.
  ///
  /// [dx] and [dy] should already be a unit vector or shorter — a half-pushed
  /// stick is a legitimate half-speed walk. Anything longer is clamped by the
  /// server rather than refused, because that is also what an analogue stick
  /// pushed into its corner produces honestly.
  void move(double dx, double dy) {
    _ref.read(platformSessionProvider.notifier).push(
      SocketEvents.clientSpaceMove,
      <String, dynamic>{'dx': dx, 'dy': dy},
    );
  }

  /// Stops. Sent once on release rather than repeatedly, because a zero
  /// direction the server already has is a packet that changes nothing.
  void halt() => move(0, 0);

  /// Starts work at a console. The server times it and decides whether — and
  /// when — it finished; nothing on the client can declare a task complete.
  Future<Result<void>> useStation(String stationId) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientSpaceTask,
      <String, dynamic>{'stationId': stationId},
    );
  }

  /// Traitor only. Refused unless the server agrees they are close enough and
  /// off cooldown.
  Future<Result<void>> eliminate(String targetId) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientSpaceEliminate,
      <String, dynamic>{'targetId': targetId},
    );
  }

  /// Reports a body you are standing next to.
  Future<Result<void>> report() =>
      _ref.read(platformSessionProvider.notifier).act(SocketEvents.clientSpaceReport);

  /// Calls an emergency meeting from the table. One per player per match.
  Future<Result<void>> callMeeting() =>
      _ref.read(platformSessionProvider.notifier).act(SocketEvents.clientSpaceMeeting);

  /// Votes, or skips.
  ///
  /// A skip is a real vote — it is how a crew declines to eject anybody — so
  /// it is sent as an empty target rather than by not voting at all.
  Future<Result<void>> vote(String? targetId) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientSpaceVote,
      <String, dynamic>{'targetId': targetId ?? ''},
    );
  }

  /// Traitor only.
  Future<Result<void>> sabotage(SabotageKind kind) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientSpaceSabotage,
      <String, dynamic>{'kind': kind.wire},
    );
  }

  /// Traitor only. Omitting [ventId] climbs out where they are.
  Future<Result<void>> vent({String? ventId}) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientSpaceVent,
      <String, dynamic>{'ventId': ?ventId},
    );
  }
}

final Provider<SpaceMysteryController> spaceMysteryControllerProvider =
    Provider<SpaceMysteryController>(SpaceMysteryController.new);

/// The latest frame, parsed.
///
/// Reads the realtime frame when there is one and falls back to the match
/// envelope before the first tick arrives — which is the window between a
/// match starting and the simulation's first broadcast, and is exactly when a
/// screen is being built.
final Provider<SpaceMysteryState> spaceMysteryStateProvider =
    Provider<SpaceMysteryState>(
  (Ref ref) {
    final PlatformSession session = ref.watch(platformSessionProvider);
    final Map<String, dynamic>? frame = session.frame;
    if (frame != null) return SpaceMysteryState.fromJson(frame);

    final Map<String, dynamic>? envelope = session.match?.state;
    if (envelope == null) return SpaceMysteryState.empty;
    return SpaceMysteryState.fromJson(envelope);
  },
);

/// The floor plan, which arrives once and never changes.
///
/// Taken from the match envelope rather than the frame: sending a map ten
/// times a second would be the largest thing on the wire by an order of
/// magnitude, so the server sends it with the match and never again.
final Provider<ShipMap> shipMapProvider = Provider<ShipMap>(
  (Ref ref) {
    final Map<String, dynamic>? envelope =
        ref.watch(platformSessionProvider).match?.state;
    if (envelope == null) return ShipMap.empty;

    final Map<String, dynamic> map = asMap(envelope['map']);
    if (map.isEmpty) return ShipMap.empty;
    return ShipMap.fromJson(map);
  },
);
