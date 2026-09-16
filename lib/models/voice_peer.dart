import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// What voice chat means for the local player this turn.
///
/// Derived from the authoritative game state, never chosen locally: the server
/// decides who holds the pen, and the server refuses voice signalling from
/// whoever that is. This enum exists so the UI and the service can say which
/// of the three situations they are in without each re-deriving it from a
/// phase and a drawer id.
enum VoiceRole {
  /// Holds the pen. No microphone, no remote audio, no peer connections.
  drawer,

  /// Guessing, and therefore in the voice mesh with the other guessers.
  guesser,

  /// Voice is not running at all — the lobby, a paused match, the final
  /// scoreboard, or a room that has not been joined yet.
  disabled,
}

/// How far along one peer connection is.
///
/// A deliberately coarse view of `RTCPeerConnectionState`. The UI only ever
/// needs to distinguish "still working on it" from "we can hear each other"
/// from "this one is not going to happen", and the extra states underneath
/// those change too often to render without flicker.
enum VoicePeerState {
  /// The offer/answer exchange is in flight.
  connecting,

  /// Audio is flowing.
  connected,

  /// ICE gave up, or the peer went away. Retried on the next state push.
  failed,
}

/// Why the local player cannot use their microphone, when they cannot.
enum VoiceBlocker {
  /// Nothing is wrong.
  none,

  /// The player declined the microphone permission.
  permissionDenied,

  /// The device reported no usable capture device.
  microphoneUnavailable,

  /// Something else went wrong opening the microphone.
  failed,
}

/// One other guesser in the voice mesh.
class VoicePeer extends Equatable {
  const VoicePeer({
    required this.userId,
    this.muted = false,
    this.state = VoicePeerState.connecting,
    this.speaking = false,
  });

  /// Builds a peer from a `s:voice:*` payload fragment.
  factory VoicePeer.fromJson(Map<String, dynamic> json) => VoicePeer(
        userId: asString(json['userId']),
        muted: asBool(json['muted']),
      );

  /// The peer's player id, the same one the room and scoreboard use.
  final String userId;

  /// Whether the peer has muted their own microphone.
  ///
  /// Advisory, and that is all it can be: the track is disabled on *their*
  /// device, so this is what the indicator renders, not what makes them
  /// inaudible.
  final bool muted;

  /// How far along the connection to this peer is.
  final VoicePeerState state;

  /// Whether audio is currently arriving from them.
  ///
  /// Best effort. It is driven by the WebRTC audio level where the platform
  /// reports one and stays false where it does not, so the indicator is a
  /// nicety rather than something the UI may rely on.
  final bool speaking;

  /// Whether audio is actually flowing from this peer.
  bool get isLive => state == VoicePeerState.connected;

  VoicePeer copyWith({
    bool? muted,
    VoicePeerState? state,
    bool? speaking,
  }) =>
      VoicePeer(
        userId: userId,
        muted: muted ?? this.muted,
        state: state ?? this.state,
        speaking: speaking ?? this.speaking,
      );

  @override
  List<Object?> get props => <Object?>[userId, muted, state, speaking];

  @override
  bool get stringify => true;
}

/// One ICE server, exactly as `RTCPeerConnection` wants it.
///
/// Supplied by the server over `s:voice:state` rather than compiled into the
/// app. A TURN credential baked into a binary is a credential anybody with the
/// APK has, and rotating it would mean shipping a new build; taking it off the
/// wire means the app holds nothing and a relay can be introduced by
/// restarting the backend.
class IceServer extends Equatable {
  const IceServer({
    required this.urls,
    this.username,
    this.credential,
  });

  factory IceServer.fromJson(Map<String, dynamic> json) {
    // The server sends a list, but a single string is legal in the WebRTC
    // configuration too, so both are accepted rather than dropping the entry.
    final dynamic raw = json['urls'];
    final List<String> urls = raw is String
        ? <String>[raw]
        : <String>[
            for (final dynamic entry in asList(raw))
              if (asString(entry).isNotEmpty) asString(entry),
          ];

    final String username = asString(json['username']);
    final String credential = asString(json['credential']);

    return IceServer(
      urls: urls,
      username: username.isEmpty ? null : username,
      credential: credential.isEmpty ? null : credential,
    );
  }

  final List<String> urls;
  final String? username;
  final String? credential;

  /// The map shape `flutter_webrtc` expects inside `iceServers`.
  Map<String, dynamic> toConfig() => <String, dynamic>{
        'urls': <String>[...urls],
        if (username != null) 'username': username,
        if (credential != null) 'credential': credential,
      };

  @override
  List<Object?> get props => <Object?>[urls, username, credential];
}

/// Everything the UI needs to know about voice, in one value.
///
/// Immutable and cheap to compare, so a widget bound to it rebuilds only when
/// something it renders actually moved — which matters here, because peer
/// state changes far more often than anything visible does.
class VoiceChatState extends Equatable {
  const VoiceChatState({
    this.role = VoiceRole.disabled,
    this.isJoined = false,
    this.isMuted = false,
    this.peers = const <String, VoicePeer>{},
    this.blocker = VoiceBlocker.none,
    this.error,
  });

  /// Voice as it stands before a game is joined.
  static const VoiceChatState initial = VoiceChatState();

  /// What voice means for this player right now.
  final VoiceRole role;

  /// Whether the server has admitted this client to the voice group.
  final bool isJoined;

  /// Whether the local microphone track is disabled.
  final bool isMuted;

  /// The mesh, keyed by player id.
  final Map<String, VoicePeer> peers;

  /// Why the microphone is unusable, when it is.
  final VoiceBlocker blocker;

  /// The last failure worth showing, or null.
  final String? error;

  /// Whether this player may speak at all right now.
  bool get isEnabled => role == VoiceRole.guesser;

  /// Whether this player holds the pen, and so must be silent.
  bool get isDrawer => role == VoiceRole.drawer;

  /// Peers that are actually carrying audio.
  Iterable<VoicePeer> get livePeers =>
      peers.values.where((VoicePeer peer) => peer.isLive);

  /// Whether the mesh is still coming up: admitted, but nobody audible yet.
  bool get isConnecting =>
      isEnabled && isJoined && peers.isNotEmpty && livePeers.isEmpty;

  VoiceChatState copyWith({
    VoiceRole? role,
    bool? isJoined,
    bool? isMuted,
    Map<String, VoicePeer>? peers,
    VoiceBlocker? blocker,
    String? error,
    bool clearError = false,
  }) =>
      VoiceChatState(
        role: role ?? this.role,
        isJoined: isJoined ?? this.isJoined,
        isMuted: isMuted ?? this.isMuted,
        peers: peers ?? this.peers,
        blocker: blocker ?? this.blocker,
        error: clearError ? null : error ?? this.error,
      );

  @override
  List<Object?> get props => <Object?>[
        role,
        isJoined,
        isMuted,
        peers,
        blocker,
        error,
      ];

  @override
  bool get stringify => true;
}
