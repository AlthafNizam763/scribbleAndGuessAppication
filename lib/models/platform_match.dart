import 'package:flutter/foundation.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// Where a platform match is in its life.
enum PlatformMatchStatus {
  waiting('waiting'),
  playing('playing'),
  completed('completed'),
  cancelled('cancelled');

  const PlatformMatchStatus(this.wire);
  final String wire;

  bool get isOver =>
      this == PlatformMatchStatus.completed || this == PlatformMatchStatus.cancelled;

  static PlatformMatchStatus fromWire(String value) {
    for (final PlatformMatchStatus status in values) {
      if (status.wire == value) return status;
    }
    return PlatformMatchStatus.waiting;
  }
}

/// The envelope every turn-based game state arrives in.
///
/// ## Why [state] is an untyped map here
///
/// Because this is the *envelope*, and the envelope is the same for all four
/// games while its contents are not. Each game parses [state] into its own
/// typed model — `KazhuthaState`, `BluffBarState` — at the point where it
/// knows what the fields mean. Parsing it here would mean one class that knew
/// about donkeys, shot glasses and reactors at the same time.
///
/// ## What [state] actually is
///
/// **This viewer's projection**, not the match. The server runs
/// `getPrivatePlayerState` for each watcher and sends each of them a different
/// object. Anything a player is not entitled to — another hand, a hidden role,
/// the pile's faces — is simply absent, so there is nothing here for a
/// modified client to reveal. Treat a missing field as "not mine to know",
/// never as "the server forgot".
@immutable
class PlatformMatch {
  const PlatformMatch({
    required this.matchId,
    required this.roomId,
    required this.gameId,
    required this.status,
    required this.state,
    required this.result,
  });

  factory PlatformMatch.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> state = asMap(json['state']);
    final Map<String, dynamic> result = asMap(json['result']);

    return PlatformMatch(
      matchId: asString(json['matchId']),
      roomId: asString(json['roomId']),
      gameId: GameId.fromWire(asString(json['gameId'])),
      status: PlatformMatchStatus.fromWire(asString(json['status'])),
      state: state,
      result: result.isEmpty ? null : result,
    );
  }

  final String matchId;
  final String roomId;
  final GameId? gameId;
  final PlatformMatchStatus status;

  /// This viewer's projection. See the class comment before reading a field.
  final Map<String, dynamic> state;

  /// Populated only once the match is over.
  final Map<String, dynamic>? result;

  bool get isOver => status.isOver;
}
