import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// What a push notification asks the app to open.
///
/// ## Why the payload is parsed rather than trusted
///
/// A notification arrives from outside the app's own state machine, often
/// minutes after it was sent and sometimes on a build that is older than the
/// server which sent it. Everything about it is therefore optional: the type
/// may be one this build has never heard of, the tournament id may name a
/// tournament that has since finished, and on a malformed message the fields
/// may simply not be there.
///
/// So this parses defensively and [PushMessage.isEmpty] is a normal answer.
/// The rule the routing follows is that an unusable payload opens the app and
/// nothing else — never a crash, and never a screen built around a missing id.
///
/// ## What a payload may carry
///
/// Ids and a route, and nothing that could be read as authoritative. The
/// screen a tap opens re-reads the real state over REST, which is what makes a
/// notification tapped an hour late show the tournament as it is now rather
/// than as it was when the message was written.

/// What a push is about.
enum PushKind {
  /// A tournament this player registered for has opened check-in.
  tournamentCheckInOpen('TOURNAMENT_CHECKIN_OPEN'),

  /// A kind this build does not know. Opens the app and stops there.
  unknown('');

  const PushKind(this.wire);

  /// The string the server sends in `data.type`.
  final String wire;

  /// Parses [value], falling back to [unknown] rather than throwing.
  static PushKind parse(dynamic value) {
    final String raw = asString(value);

    for (final PushKind kind in PushKind.values) {
      if (kind.wire.isNotEmpty && kind.wire == raw) return kind;
    }

    return PushKind.unknown;
  }
}

/// One push notification's tap payload.
class PushMessage extends Equatable {
  /// Creates a message.
  const PushMessage({
    this.kind = PushKind.unknown,
    this.tournamentId = '',
    this.route = '',
  });

  /// Builds a message from an FCM `data` map. Never throws.
  factory PushMessage.fromData(Map<String, dynamic> data) => PushMessage(
        kind: PushKind.parse(data['type']),
        tournamentId: asString(data['tournamentId']),
        route: asString(data['route']),
      );

  /// What happened.
  final PushKind kind;

  /// Which tournament, when the kind concerns one. May be empty.
  final String tournamentId;

  /// The destination the server suggested, as a path. May be empty.
  ///
  /// Advisory rather than authoritative: the client decides where a kind it
  /// recognises goes, and only falls back to this for one it does not. A
  /// server that could name any route would be a server that could send a
  /// player anywhere in the app.
  final String route;

  /// Whether there is anything here worth acting on.
  bool get isEmpty => kind == PushKind.unknown && route.isEmpty;

  /// Whether this names a tournament the app can open.
  bool get hasTournament => tournamentId.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[kind, tournamentId, route];

  @override
  bool get stringify => true;
}
