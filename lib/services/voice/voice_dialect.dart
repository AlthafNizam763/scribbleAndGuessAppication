import 'package:flutter/foundation.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/voice_peer.dart';

/// Which game's voice chat is being spoken.
///
/// Voice on this platform is one feature over two protocols, because it sits
/// on top of two room systems. Scribble & Guess runs on the `Room`/`Game`
/// services with `c:voice:*` / `s:voice:*`; the other four run on the
/// `GameRoom`/`GameMatch` layer with `game:voice_*`. They are not going to be
/// merged — see `platformVoice.service.ts` for why — so the client speaks both
/// and chooses by context.
enum VoiceGameContext {
  scribble,
  kazhutha,
  bluffBar,
  spaceMystery,
  ludo;

  /// The context for a catalogue game.
  static VoiceGameContext of(GameId gameId) => switch (gameId) {
        GameId.scribbleGuess => VoiceGameContext.scribble,
        GameId.kazhutha => VoiceGameContext.kazhutha,
        GameId.bluffBar => VoiceGameContext.bluffBar,
        GameId.spaceMystery => VoiceGameContext.spaceMystery,
        GameId.ludo => VoiceGameContext.ludo,
      };

  /// Whether this context talks to the platform room layer.
  bool get isPlatform => this != VoiceGameContext.scribble;
}

/// One voice protocol, as a set of names and four small readers.
///
/// ## Why a value object and not two subclasses of the service
///
/// Because the *behaviour* is identical. Opening a microphone, building a
/// mesh, offering to the higher id, polling levels, tearing a peer down and
/// releasing the track are the same in both games, and the only differences
/// are six event names, a couple of extra fields on every outbound payload,
/// and which key the sender's id is under. Subclassing would duplicate four
/// hundred lines of WebRTC to vary a dozen strings.
///
/// ## Why the readers are here rather than in the service
///
/// The two servers spell the same fact differently — Scribble's relay says
/// `from`, the platform's says `fromUserId`; Scribble sends a `peer` object,
/// the platform sends the fields inline. Those are protocol facts, so they
/// live with the protocol. The service asks "who sent this" and never learns
/// which spelling answered.
@immutable
class VoiceDialect {
  const VoiceDialect({
    required this.context,
    required this.clientJoin,
    required this.clientLeave,
    required this.clientMute,
    required this.clientOffer,
    required this.clientAnswer,
    required this.clientIce,
    required this.serverState,
    required this.serverPeerJoined,
    required this.serverPeerLeft,
    required this.serverOffer,
    required this.serverAnswer,
    required this.serverIce,
    required this.serverMute,
    required this.serverError,
    required this.envelope,
  });

  final VoiceGameContext context;

  final String clientJoin;
  final String clientLeave;
  final String clientMute;
  final String clientOffer;
  final String clientAnswer;
  final String clientIce;

  final String serverState;
  final String serverPeerJoined;
  final String serverPeerLeft;
  final String serverOffer;
  final String serverAnswer;
  final String serverIce;
  final String serverMute;
  final String serverError;

  /// Fields added to every outbound frame.
  ///
  /// Empty for Scribble, whose server reads the room off the socket. The
  /// platform needs `gameId` and `roomId` on each one, because a socket can be
  /// in a platform room and a Scribble room at the same time and the server
  /// will not guess which this frame meant.
  final Map<String, dynamic> Function() envelope;

  /// Every server event this dialect cares about, for routing.
  Set<String> get serverEvents => <String>{
        serverState,
        serverPeerJoined,
        serverPeerLeft,
        serverOffer,
        serverAnswer,
        serverIce,
        serverMute,
        serverError,
      };

  /// Who sent an inbound signalling frame.
  String senderOf(Map<String, dynamic> data) => switch (context) {
        VoiceGameContext.scribble => asString(data['from']),
        _ => asString(data['fromUserId']),
      };

  /// The peer described by a peer-joined frame.
  VoicePeer peerFrom(Map<String, dynamic> data) => switch (context) {
        VoiceGameContext.scribble => VoicePeer.fromJson(asMap(data['peer'])),
        // The platform announces a joiner inline rather than wrapped, because
        // the same event carries the joiner's own ack shape on the way out.
        _ => VoicePeer(
            userId: asString(data['fromUserId']),
            muted: asBool(data['muted']),
          ),
      };

  /// Who left, from a peer-left frame.
  String leaverOf(Map<String, dynamic> data) => switch (context) {
        VoiceGameContext.scribble => asString(data['userId']),
        _ => asString(data['fromUserId']),
      };

  /// What role a `state` frame puts the local player in.
  ///
  /// Scribble's answer is about the pen. The platform's is about whether the
  /// server is letting this player talk at all — a ghost on the Meridian, a
  /// drinker who has run out of glasses — which collapses to the same two
  /// outcomes the UI has always had: in the mesh, or not.
  VoiceRole roleFrom(Map<String, dynamic> data) {
    final bool enabled = asBool(data['enabled']);
    if (enabled) return VoiceRole.guesser;

    if (context == VoiceGameContext.scribble) {
      return asBool(data['isDrawer']) ? VoiceRole.drawer : VoiceRole.disabled;
    }
    return VoiceRole.disabled;
  }

  /// A human explanation of why voice is closed, when the server gave one.
  String? reasonFrom(Map<String, dynamic> data) {
    if (context == VoiceGameContext.scribble) {
      return asBool(data['isDrawer']) ? 'Voice is off while you draw.' : null;
    }

    return switch (asString(data['reason'])) {
      'spectating' => 'The dead do not talk to the living.',
      'no_meeting' => 'Voice opens when a meeting is called.',
      'eliminated' => 'You are out. Listen from the bar.',
      'match_over' => 'That match has finished.',
      'not_seated' => 'You are not in this game.',
      _ => null,
    };
  }

  /// Scribble & Guess: one room, one drawer, no extra envelope.
  static const VoiceDialect scribble = VoiceDialect(
    context: VoiceGameContext.scribble,
    clientJoin: SocketEvents.clientVoiceJoin,
    clientLeave: SocketEvents.clientVoiceLeave,
    clientMute: SocketEvents.clientVoiceMute,
    clientOffer: SocketEvents.clientVoiceOffer,
    clientAnswer: SocketEvents.clientVoiceAnswer,
    clientIce: SocketEvents.clientVoiceIce,
    serverState: SocketEvents.serverVoiceState,
    serverPeerJoined: SocketEvents.serverVoicePeerJoined,
    serverPeerLeft: SocketEvents.serverVoicePeerLeft,
    serverOffer: SocketEvents.serverVoiceOffer,
    serverAnswer: SocketEvents.serverVoiceAnswer,
    serverIce: SocketEvents.serverVoiceIce,
    serverMute: SocketEvents.serverVoiceMute,
    serverError: SocketEvents.serverVoiceError,
    envelope: _noEnvelope,
  );

  /// The four platform games. Identical protocol; the envelope names the room.
  static VoiceDialect platform({
    required GameId gameId,
    required String Function() roomId,
  }) =>
      VoiceDialect(
        context: VoiceGameContext.of(gameId),
        clientJoin: SocketEvents.clientGameVoiceJoin,
        clientLeave: SocketEvents.clientGameVoiceLeave,
        clientMute: SocketEvents.clientGameVoiceMute,
        clientOffer: SocketEvents.clientGameVoiceOffer,
        clientAnswer: SocketEvents.clientGameVoiceAnswer,
        clientIce: SocketEvents.clientGameVoiceIce,
        serverState: SocketEvents.serverGameVoiceState,
        serverPeerJoined: SocketEvents.serverGameVoiceJoined,
        serverPeerLeft: SocketEvents.serverGameVoiceLeft,
        serverOffer: SocketEvents.serverGameVoiceOffer,
        serverAnswer: SocketEvents.serverGameVoiceAnswer,
        serverIce: SocketEvents.serverGameVoiceIce,
        serverMute: SocketEvents.serverGameVoiceMuted,
        serverError: SocketEvents.serverGameVoiceError,
        envelope: () => <String, dynamic>{
          'gameId': gameId.wire,
          'roomId': roomId(),
        },
      );
}

Map<String, dynamic> _noEnvelope() => const <String, dynamic>{};
