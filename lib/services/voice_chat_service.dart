import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:scribble_guess/app/app_config.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/voice_peer.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// The gateway's inbound record, aliased for readability.
typedef _Inbound = ({String event, Map<String, dynamic> data});

/// Guesser-only voice chat: one WebRTC mesh, driven by the game's own socket.
///
/// ## What it is
///
/// A small peer-to-peer conference. Every guesser holds one
/// [RTCPeerConnection] to every other guesser, carrying a single audio track
/// each way. The game's existing Socket.IO connection is used to exchange the
/// SDP and ICE candidates that set those up, and for nothing else — no audio
/// ever travels over it, which is what makes the feature free to run.
///
/// A mesh rather than a mixer because the rooms are small: at six players the
/// worst case is five connections per device, which a phone handles without
/// noticing. An SFU would be the answer at twenty, and would need a server
/// this project deliberately does not have.
///
/// ## The rule
///
/// The drawer can neither speak nor hear. This class enforces that locally by
/// closing every connection and stopping the microphone the moment it learns
/// the pen has moved to this player — but it is not *why* the rule holds. The
/// server refuses `c:voice:*` from the drawer outright, so a modified client
/// that skipped [disable] would still be unable to signal. See
/// `voice.service.ts`.
///
/// ## Who offers
///
/// Both ends of a new pair learn about each other at the same moment — the
/// joiner from its join ack, the incumbent from `s:voice:peerJoined` — so
/// something has to break the tie or both would send an offer and neither
/// could apply the other's (the "glare" problem). The tie-break is the player
/// ids: the lexicographically smaller id offers, the other waits. It needs no
/// round trip, it gives the same answer on both devices, and it survives the
/// two sides learning about each other in either order.
///
/// ## Nothing here rebuilds a widget
///
/// The class is a plain service with a [stateStream]; `VoiceChatNotifier`
/// adapts it to Riverpod. Peer connection states change far more often than
/// anything visible does, so [VoiceChatState] is compared before it is
/// published and identical values are dropped.
class VoiceChatService {
  VoiceChatService({
    required RealtimeGateway gateway,
    required String selfId,
  })  : _gateway = gateway,
        _selfId = selfId {
    _inboundSubscription = _gateway.inbound.listen(
      _onInbound,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.w('VoiceChatService: inbound stream error', error, stackTrace);
      },
    );
  }

  /// How often peers are polled for an audio level.
  ///
  /// Local only — it reads WebRTC's own statistics and sends nothing — so the
  /// cost is a few map lookups. Slow enough not to matter, fast enough that a
  /// speaking indicator does not feel laggy.
  static const Duration _levelPollInterval = Duration(milliseconds: 400);

  /// Audio level above which a peer counts as speaking.
  ///
  /// `audioLevel` is normalised 0..1 and idles around 0.001 on a live but
  /// silent microphone, so this sits comfortably above the noise floor without
  /// needing someone to shout.
  static const double _speakingThreshold = 0.01;

  final RealtimeGateway _gateway;
  final String _selfId;

  final StreamController<VoiceChatState> _stateController =
      StreamController<VoiceChatState>.broadcast();

  StreamSubscription<_Inbound>? _inboundSubscription;
  Timer? _levelTimer;

  /// One entry per peer. The key is the peer's player id.
  final Map<String, _PeerLink> _links = <String, _PeerLink>{};

  /// The microphone, held open for as long as this player is a guesser.
  MediaStream? _localStream;

  /// ICE servers as the server last supplied them.
  List<IceServer> _iceServers = const <IceServer>[];

  VoiceChatState _state = VoiceChatState.initial;

  /// The tail of the enable/disable queue, or null when nothing is in flight.
  ///
  /// Two things drive voice independently and routinely fire on the same
  /// frame: the server's `s:voice:state` push and the provider reacting to the
  /// game state that caused it. Overlapping an `enable` with a `disable` would
  /// leave a microphone open with no peers, or peers with no microphone, so
  /// every transition is chained onto this instead of running concurrently.
  Future<void>? _transition;

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Surface
  // ---------------------------------------------------------------------------

  /// The current state, read synchronously.
  VoiceChatState get state => _state;

  /// Voice state as it changes. Broadcast; emits only on an actual change.
  Stream<VoiceChatState> get stateStream => _stateController.stream;

  /// Remote audio renderers, keyed by peer id. Populated on the web only.
  ///
  /// Native platforms play a remote audio track as soon as it arrives, with no
  /// widget involved. A browser will not: audio only plays through a media
  /// element that is actually in the document, so on the web each remote
  /// stream needs a renderer and the UI has to mount it (see `VoiceControl`).
  /// Empty everywhere else, so the UI's handling of it costs nothing there.
  Map<String, RTCVideoRenderer> get remoteRenderers =>
      Map<String, RTCVideoRenderer>.unmodifiable(_renderers);
  final Map<String, RTCVideoRenderer> _renderers = <String, RTCVideoRenderer>{};

  /// Applies the role the authoritative game state implies.
  ///
  /// The only entry point the rest of the app needs. Idempotent: being told
  /// "you are still a guesser" on every hint and every guess — which is what
  /// happens, because the game state is re-pushed constantly — does nothing.
  Future<void> applyRole(VoiceRole role) async {
    if (_disposed || role == _state.role) return;

    _publish(_state.copyWith(role: role));

    if (role == VoiceRole.guesser) {
      await enable();
    } else {
      // Covers both the drawer and every phase without voice. A player who was
      // a guesser a moment ago has their microphone stopped and every peer
      // closed here, which is the client half of the rule.
      await disable(announce: true);
    }
  }

  /// Opens the microphone and joins the room's voice group.
  ///
  /// Safe to call when already joined. Failures land in [VoiceChatState.blocker]
  /// rather than being thrown: a refused microphone must not break the game,
  /// and a player who declined can still draw, guess and type.
  Future<void> enable() => _serialize(_enable);

  Future<void> _enable() async {
    if (_disposed || _state.isJoined) return;

    // The client half of the rule, and a cheap one: a caller that got the role
    // wrong stops here rather than being refused a round trip later.
    if (_state.role != VoiceRole.guesser) return;

    final MediaStream? stream = await _openMicrophone();
    if (stream == null) return;

    final Result<Map<String, dynamic>> ack =
        await _gateway.request(SocketEvents.clientVoiceJoin);

    if (ack case Err<Map<String, dynamic>>(:final failure)) {
      AppLogger.w('VoiceChatService: join refused - ${failure.message}');
      // Refused, so the microphone must not stay open. The drawer case is the
      // expected one and is not surfaced as an error: the UI already says
      // "Voice disabled" for them.
      await _releaseMicrophone();
      _publish(
        _state.copyWith(
          isJoined: false,
          error: failure.code == AppErrorCode.drawerVoiceDisabled
              ? null
              : failure.userMessage,
        ),
      );
      return;
    }

    final Map<String, dynamic> data = (ack as Ok<Map<String, dynamic>>).value;

    // The ack carries this deployment's ICE servers, so nothing about STUN or
    // TURN is compiled into the app. A build-time override is still honoured
    // for pointing a debug build at a local Coturn.
    _iceServers = _parseIceServers(data['iceServers']);

    _publish(
      _state.copyWith(
        isJoined: true,
        isMuted: asBool(data['muted']),
        clearError: true,
        blocker: VoiceBlocker.none,
      ),
    );

    _applyMuteToTracks(_state.isMuted);
    _startLevelPolling();

    // Everybody already in the group. Exactly one side of each pair offers,
    // decided by the id comparison in `_shouldOffer`.
    for (final dynamic raw in asList(data['peers'])) {
      final VoicePeer peer = VoicePeer.fromJson(asMap(raw));
      if (peer.userId.isEmpty) continue;
      await _addPeer(peer, offer: _shouldOffer(peer.userId));
    }
  }

  /// Closes every connection, stops the microphone and leaves the group.
  ///
  /// [announce] tells the server as well. It is false only when the server is
  /// the one that hung us up — it already knows — and true when this client
  /// decided, so the other guessers hear about it immediately rather than
  /// waiting for ICE to time out.
  ///
  /// Never touches the game socket. Voice going away must not cost the player
  /// their room, their score or their canvas.
  Future<void> disable({bool announce = false}) =>
      _serialize(() => _disable(announce: announce));

  Future<void> _disable({required bool announce}) async {
    _stopLevelPolling();

    for (final String peerId in <String>[..._links.keys]) {
      await _closePeer(peerId);
    }

    await _releaseMicrophone();

    if (announce && _state.isJoined) {
      // Fire and forget. The server drops us anyway when the turn changes, so
      // a failure here costs nothing and must not hold up the teardown.
      unawaited(
        _gateway.request(SocketEvents.clientVoiceLeave).then((_) {}),
      );
    }

    _publish(
      _state.copyWith(
        isJoined: false,
        peers: const <String, VoicePeer>{},
      ),
    );
  }

  /// Mutes or unmutes the local microphone.
  ///
  /// The track is disabled locally — which is what actually silences it — and
  /// the server is told only so the other guessers can render the indicator.
  Future<void> setMuted(bool muted) async {
    if (_disposed || _state.isMuted == muted) return;

    _applyMuteToTracks(muted);
    _publish(_state.copyWith(isMuted: muted));

    if (!_state.isJoined) return;

    final Result<Map<String, dynamic>> ack = await _gateway.request(
      SocketEvents.clientVoiceMute,
      <String, dynamic>{'muted': muted},
    );

    // A refused mute is not worth surfacing: the track is already disabled, so
    // the player is silent either way and only the remote indicator is stale.
    if (ack case Err<Map<String, dynamic>>(:final failure)) {
      AppLogger.w('VoiceChatService: mute not published - ${failure.message}');
    }
  }

  /// Tears the service down for good.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _stopLevelPolling();
    unawaited(_inboundSubscription?.cancel());
    _inboundSubscription = null;

    for (final String peerId in <String>[..._links.keys]) {
      await _closePeer(peerId);
    }
    await _releaseMicrophone();

    unawaited(_stateController.close());
  }

  // ---------------------------------------------------------------------------
  // Microphone
  // ---------------------------------------------------------------------------

  /// Opens the microphone, or records why it could not be opened.
  ///
  /// Audio only, and explicitly `video: false`: asking for a camera would make
  /// the operating system prompt for camera access in a drawing game, which is
  /// both alarming and unnecessary.
  Future<MediaStream?> _openMicrophone() async {
    final MediaStream? existing = _localStream;
    if (existing != null) return existing;

    try {
      final MediaStream stream = await navigator.mediaDevices.getUserMedia(
        <String, dynamic>{
          'audio': <String, dynamic>{
            // Three processors that matter far more for a group call than
            // fidelity does: without echo cancellation, every peer hears
            // themselves back through this device's loudspeaker.
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        },
      );

      _localStream = stream;
      await _routeToLoudspeaker();
      return stream;
    } catch (error, stackTrace) {
      AppLogger.w('VoiceChatService: microphone unavailable', error, stackTrace);

      _publish(
        _state.copyWith(
          blocker: _classifyMicrophoneError(error),
          error: _microphoneMessage(error),
          isJoined: false,
        ),
      );
      return null;
    }
  }

  /// Stops the microphone and drops it.
  ///
  /// Both the tracks and the stream: stopping a track releases the hardware —
  /// which is what takes the recording indicator out of the status bar — while
  /// disposing the stream releases the native object behind it. Skipping
  /// either one leaks, and leaking a microphone is the kind of bug players
  /// notice.
  Future<void> _releaseMicrophone() async {
    final MediaStream? stream = _localStream;
    _localStream = null;
    if (stream == null) return;

    for (final MediaStreamTrack track in stream.getAudioTracks()) {
      try {
        await track.stop();
      } catch (error, stackTrace) {
        AppLogger.w('VoiceChatService: stopping a track failed', error, stackTrace);
      }
    }

    try {
      await stream.dispose();
    } catch (error, stackTrace) {
      AppLogger.w('VoiceChatService: disposing the stream failed', error, stackTrace);
    }
  }

  /// Disables or enables the local audio track.
  ///
  /// `enabled = false` keeps the connection up and sends silence, which is
  /// what mute has to mean: renegotiating the whole peer connection every time
  /// somebody taps the button would drop audio for a second each way.
  void _applyMuteToTracks(bool muted) {
    final MediaStream? stream = _localStream;
    if (stream == null) return;
    for (final MediaStreamTrack track in stream.getAudioTracks()) {
      track.enabled = !muted;
    }
  }

  /// Points the output at the loudspeaker on mobile.
  ///
  /// A player is looking at the canvas, not holding the phone to their ear, so
  /// the earpiece — which is where a WebRTC audio session defaults on both
  /// platforms — is the wrong output. The platform still takes over when a
  /// wired or Bluetooth headset is connected, which is the behaviour a player
  /// expects and the reason this is not re-applied on every route change.
  Future<void> _routeToLoudspeaker() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (error, stackTrace) {
      // Audio still works through whatever the system chose; only the default
      // output is wrong. Never worth failing a call over.
      AppLogger.w('VoiceChatService: speakerphone routing failed', error, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // Peers
  // ---------------------------------------------------------------------------

  /// Whether this device opens the connection to [peerId].
  ///
  /// See the glare note in the class doc: both devices run this and get
  /// opposite answers, so exactly one offer is created per pair.
  bool _shouldOffer(String peerId) => _selfId.compareTo(peerId) < 0;

  /// Creates the connection to one peer, optionally sending the first offer.
  ///
  /// Re-entrant by design. `s:voice:peerJoined` for somebody already in
  /// [_links] means they reconnected, so the stale connection is torn down
  /// first rather than leaving two.
  Future<void> _addPeer(VoicePeer peer, {required bool offer}) async {
    if (_disposed || _localStream == null) return;
    if (_state.role != VoiceRole.guesser) return;

    if (_links.containsKey(peer.userId)) {
      await _closePeer(peer.userId);
    }

    try {
      final RTCPeerConnection connection = await createPeerConnection(
        <String, dynamic>{
          'iceServers': <Map<String, dynamic>>[
            for (final IceServer server in _effectiveIceServers())
              server.toConfig(),
          ],
          // Unified plan is the modern semantics and the only one that
          // describes a track-per-transceiver cleanly. It is the default in
          // current builds; naming it keeps the behaviour pinned.
          'sdpSemantics': 'unified-plan',
        },
      );

      final _PeerLink link = _PeerLink(peer: peer, connection: connection);
      _links[peer.userId] = link;

      _wire(link);

      // The microphone goes on every connection. `addTrack` rather than
      // `addStream`: the latter is the legacy plan-b API and is deprecated.
      final MediaStream stream = _localStream!;
      for (final MediaStreamTrack track in stream.getAudioTracks()) {
        await connection.addTrack(track, stream);
      }

      _upsertPeer(peer.copyWith(state: VoicePeerState.connecting));

      if (offer) await _sendOffer(link);
    } catch (error, stackTrace) {
      AppLogger.w(
        'VoiceChatService: could not open a connection to ${peer.userId}',
        error,
        stackTrace,
      );
      _upsertPeer(peer.copyWith(state: VoicePeerState.failed));
    }
  }

  /// Attaches the callbacks one connection needs.
  void _wire(_PeerLink link) {
    final String peerId = link.peer.userId;

    link.connection.onIceCandidate = (RTCIceCandidate candidate) {
      // A null `candidate` string is the end-of-candidates marker, and it is
      // forwarded rather than dropped: a peer that never receives it waits for
      // more that are not coming.
      _gateway.emit(
        SocketEvents.clientVoiceIce,
        <String, dynamic>{
          'targetId': peerId,
          'candidate': <String, dynamic>{
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        },
      );
    };

    link.connection.onTrack = (RTCTrackEvent event) {
      if (event.track.kind != 'audio') return;
      final MediaStream? stream =
          event.streams.isEmpty ? null : event.streams.first;
      if (stream == null) return;

      link.remoteStream = stream;
      unawaited(_attachRemoteAudio(peerId, stream));
    };

    link.connection.onConnectionState = (RTCPeerConnectionState rtcState) {
      final VoicePeerState next = switch (rtcState) {
        RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
          VoicePeerState.connected,
        RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
          VoicePeerState.failed,
        // `disconnected` is routinely transient — a phone changing from wifi
        // to cellular passes through it — and ICE recovers on its own, so it
        // is reported as still connecting rather than as a failure.
        _ => VoicePeerState.connecting,
      };

      final VoicePeer? current = _state.peers[peerId];
      if (current == null) return;
      _upsertPeer(current.copyWith(state: next));
    };
  }

  /// Creates and sends the offer for one pair.
  Future<void> _sendOffer(_PeerLink link) async {
    final RTCSessionDescription offer = await link.connection.createOffer(
      <String, dynamic>{
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      },
    );
    await link.connection.setLocalDescription(offer);

    _gateway.emit(
      SocketEvents.clientVoiceOffer,
      <String, dynamic>{
        'targetId': link.peer.userId,
        'description': <String, dynamic>{'type': offer.type, 'sdp': offer.sdp},
      },
    );
  }

  /// Closes one connection and forgets it.
  Future<void> _closePeer(String peerId) async {
    final _PeerLink? link = _links.remove(peerId);

    final RTCVideoRenderer? renderer = _renderers.remove(peerId);
    if (renderer != null) {
      renderer.srcObject = null;
      unawaited(renderer.dispose());
    }

    if (link != null) {
      try {
        await link.connection.close();
      } catch (error, stackTrace) {
        AppLogger.w('VoiceChatService: closing $peerId failed', error, stackTrace);
      }
      // Separate from `close`, and both are needed: closing ends the session,
      // disposing frees the native peer connection behind it.
      try {
        await link.connection.dispose();
      } catch (error, stackTrace) {
        AppLogger.w('VoiceChatService: disposing $peerId failed', error, stackTrace);
      }
    }

    if (_state.peers.containsKey(peerId)) {
      final Map<String, VoicePeer> next =
          Map<String, VoicePeer>.of(_state.peers)..remove(peerId);
      _publish(_state.copyWith(peers: next));
    }
  }

  /// Makes a remote audio stream audible.
  ///
  /// Nothing to do on a native platform: the audio session plays an inbound
  /// track as soon as it is negotiated. A browser needs a media element with
  /// the stream attached, which is what the renderer is.
  Future<void> _attachRemoteAudio(String peerId, MediaStream stream) async {
    if (!kIsWeb) return;

    try {
      final RTCVideoRenderer renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;

      final RTCVideoRenderer? previous = _renderers[peerId];
      if (previous != null) unawaited(previous.dispose());
      _renderers[peerId] = renderer;

      // The renderer has to be mounted for the browser to play it, so the
      // state is republished to prompt a rebuild.
      _stateController.add(_state);
    } catch (error, stackTrace) {
      AppLogger.w('VoiceChatService: remote audio for $peerId', error, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // Inbound signalling
  // ---------------------------------------------------------------------------

  void _onInbound(_Inbound message) {
    switch (message.event) {
      case SocketEvents.serverVoiceState:
        unawaited(_onServerState(message.data));
      case SocketEvents.serverVoicePeerJoined:
        unawaited(_onPeerJoined(message.data));
      case SocketEvents.serverVoicePeerLeft:
        unawaited(_onPeerLeft(message.data));
      case SocketEvents.serverVoiceOffer:
        unawaited(_onOffer(message.data));
      case SocketEvents.serverVoiceAnswer:
        unawaited(_onAnswer(message.data));
      case SocketEvents.serverVoiceIce:
        unawaited(_onCandidate(message.data));
      case SocketEvents.serverVoiceMute:
        _onPeerMute(message.data);
      case SocketEvents.serverVoiceError:
        unawaited(_onError(message.data));
    }
  }

  /// The server's verdict on whether this player may speak.
  ///
  /// Outranks anything this client believes. It arrives on a reconnect, on a
  /// mid-turn join, and — the case the whole feature turns on — the moment
  /// this player becomes the drawer.
  Future<void> _onServerState(Map<String, dynamic> data) async {
    final bool enabled = asBool(data['enabled']);
    final bool isDrawer = asBool(data['isDrawer']);

    if (!enabled) {
      _publish(
        _state.copyWith(
          role: isDrawer ? VoiceRole.drawer : VoiceRole.disabled,
        ),
      );
      // The server has already removed us, so there is nothing to announce.
      await disable();
      return;
    }

    _iceServers = _parseIceServers(data['iceServers']);
    _publish(_state.copyWith(role: VoiceRole.guesser));

    if (!_state.isJoined) {
      await enable();
      return;
    }

    // Already in the group and still allowed: reconcile the roster, which is
    // how a reconnect rebuilds a mesh it used to have.
    final Set<String> expected = <String>{
      for (final dynamic raw in asList(data['peers'])) asString(asMap(raw)['userId']),
    }..remove('');

    for (final String gone in _links.keys.toList()) {
      if (!expected.contains(gone)) await _closePeer(gone);
    }
    for (final dynamic raw in asList(data['peers'])) {
      final VoicePeer peer = VoicePeer.fromJson(asMap(raw));
      if (peer.userId.isEmpty || _links.containsKey(peer.userId)) continue;
      await _addPeer(peer, offer: _shouldOffer(peer.userId));
    }
  }

  Future<void> _onPeerJoined(Map<String, dynamic> data) async {
    final VoicePeer peer = VoicePeer.fromJson(asMap(data['peer']));
    if (peer.userId.isEmpty || peer.userId == _selfId) return;
    if (!_state.isJoined) return;

    await _addPeer(peer, offer: _shouldOffer(peer.userId));
  }

  Future<void> _onPeerLeft(Map<String, dynamic> data) async {
    final String userId = asString(data['userId']);
    if (userId.isEmpty) return;
    await _closePeer(userId);
  }

  Future<void> _onOffer(Map<String, dynamic> data) async {
    final String from = asString(data['from']);
    if (from.isEmpty || !_state.isJoined) return;

    // An offer from somebody not yet in the map is the normal case for the
    // side that waits, so the connection is created here rather than treating
    // it as an error.
    if (!_links.containsKey(from)) {
      await _addPeer(VoicePeer(userId: from), offer: false);
    }

    final _PeerLink? link = _links[from];
    if (link == null) return;

    try {
      final Map<String, dynamic> description = asMap(data['description']);
      await link.connection.setRemoteDescription(
        RTCSessionDescription(
          asString(description['sdp']),
          asString(description['type']),
        ),
      );
      await link.flushCandidates();

      final RTCSessionDescription answer = await link.connection.createAnswer(
        <String, dynamic>{
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        },
      );
      await link.connection.setLocalDescription(answer);

      _gateway.emit(
        SocketEvents.clientVoiceAnswer,
        <String, dynamic>{
          'targetId': from,
          'description': <String, dynamic>{
            'type': answer.type,
            'sdp': answer.sdp,
          },
        },
      );
    } catch (error, stackTrace) {
      AppLogger.w('VoiceChatService: answering $from failed', error, stackTrace);
      _markFailed(from);
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> data) async {
    final String from = asString(data['from']);
    final _PeerLink? link = _links[from];
    if (link == null) return;

    try {
      final Map<String, dynamic> description = asMap(data['description']);
      await link.connection.setRemoteDescription(
        RTCSessionDescription(
          asString(description['sdp']),
          asString(description['type']),
        ),
      );
      await link.flushCandidates();
    } catch (error, stackTrace) {
      AppLogger.w('VoiceChatService: answer from $from failed', error, stackTrace);
      _markFailed(from);
    }
  }

  Future<void> _onCandidate(Map<String, dynamic> data) async {
    final String from = asString(data['from']);
    final _PeerLink? link = _links[from];
    if (link == null) return;

    final Map<String, dynamic> raw = asMap(data['candidate']);
    final RTCIceCandidate candidate = RTCIceCandidate(
      raw['candidate'] == null ? null : asString(raw['candidate']),
      raw['sdpMid'] == null ? null : asString(raw['sdpMid']),
      raw['sdpMLineIndex'] == null ? null : asInt(raw['sdpMLineIndex']),
    );

    // Candidates routinely arrive before the description they belong to —
    // both travel over the same socket, but the description takes a round trip
    // through `createAnswer` first. Adding one early throws, so they are held
    // until the remote description lands.
    await link.addOrQueue(candidate);
  }

  void _onPeerMute(Map<String, dynamic> data) {
    final String userId = asString(data['userId']);
    final VoicePeer? peer = _state.peers[userId];
    if (peer == null) return;
    _upsertPeer(peer.copyWith(muted: asBool(data['muted'])));
  }

  /// A refused voice operation.
  ///
  /// `DRAWER_VOICE_DISABLED` is the one that matters: it means this client
  /// signalled while holding the pen, which should be impossible, so the local
  /// state is corrected to match the server rather than retried.
  Future<void> _onError(Map<String, dynamic> data) async {
    final String code = asString(data['code']);
    AppLogger.w('VoiceChatService: server refused a voice action - $code');

    if (code == _drawerRefusedWireCode) {
      _publish(_state.copyWith(role: VoiceRole.drawer));
      await disable();
      return;
    }

    _publish(
      _state.copyWith(
        error: asString(data['message']).isEmpty
            ? AppStrings.voiceFailed
            : asString(data['message']),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Speaking detection
  // ---------------------------------------------------------------------------

  void _startLevelPolling() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(_levelPollInterval, (_) => _pollLevels());
  }

  void _stopLevelPolling() {
    _levelTimer?.cancel();
    _levelTimer = null;
  }

  /// Reads each peer's inbound audio level.
  ///
  /// Entirely local — `getStats` reads WebRTC's own counters and sends
  /// nothing — and best effort: a platform that reports no `audioLevel` simply
  /// leaves every indicator off, which is what [VoicePeer.speaking] promises.
  Future<void> _pollLevels() async {
    if (_disposed || _links.isEmpty) return;

    for (final MapEntry<String, _PeerLink> entry in _links.entries) {
      try {
        final List<StatsReport> reports = await entry.value.connection.getStats();

        double level = 0;
        for (final StatsReport report in reports) {
          // Inbound only. The same connection also reports an `audioLevel`
          // for the *outgoing* track, and taking the maximum across every
          // report would light up every peer's indicator whenever this player
          // spoke. `inbound-rtp` is where it lives on a modern stack;
          // `track` with `remoteSource` is where older ones put it.
          final bool isRemote = report.type == 'inbound-rtp' ||
              (report.type == 'track' && report.values['remoteSource'] == true);
          if (!isRemote) continue;

          final Object? value = report.values['audioLevel'];
          if (value is num && value > level) level = value.toDouble();
        }

        final VoicePeer? peer = _state.peers[entry.key];
        if (peer == null) continue;

        final bool speaking = level >= _speakingThreshold;
        if (speaking != peer.speaking) {
          _upsertPeer(peer.copyWith(speaking: speaking));
        }
      } catch (_) {
        // Stats are a nicety. A platform that refuses them is not a problem
        // worth logging every 400ms.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  /// The ICE servers to configure a connection with.
  ///
  /// The server's list wins. A `--dart-define` override exists only so a debug
  /// build can be pointed at a Coturn on the same laptop, and a hardcoded
  /// STUN default backs both up so a deployment that forgot to configure
  /// anything still connects on most networks.
  List<IceServer> _effectiveIceServers() {
    if (_iceServers.isNotEmpty) return _iceServers;

    final List<IceServer> overrides = AppConfig.current.iceServerOverrides;
    if (overrides.isNotEmpty) return overrides;

    return const <IceServer>[
      IceServer(urls: <String>['stun:stun.l.google.com:19302']),
    ];
  }

  List<IceServer> _parseIceServers(dynamic raw) => <IceServer>[
        for (final dynamic entry in asList(raw))
          if (asMap(entry).isNotEmpty) IceServer.fromJson(asMap(entry)),
      ];

  void _upsertPeer(VoicePeer peer) {
    final Map<String, VoicePeer> next = Map<String, VoicePeer>.of(_state.peers);
    next[peer.userId] = peer;
    _publish(_state.copyWith(peers: next));
  }

  void _markFailed(String peerId) {
    final VoicePeer? peer = _state.peers[peerId];
    if (peer == null) return;
    _upsertPeer(peer.copyWith(state: VoicePeerState.failed));
  }

  VoiceBlocker _classifyMicrophoneError(Object error) {
    final String text = error.toString().toLowerCase();
    if (text.contains('notallowed') ||
        text.contains('permission') ||
        text.contains('denied')) {
      return VoiceBlocker.permissionDenied;
    }
    if (text.contains('notfound') || text.contains('no device')) {
      return VoiceBlocker.microphoneUnavailable;
    }
    return VoiceBlocker.failed;
  }

  String _microphoneMessage(Object error) =>
      switch (_classifyMicrophoneError(error)) {
        VoiceBlocker.permissionDenied => AppStrings.voiceNoPermission,
        VoiceBlocker.microphoneUnavailable => AppStrings.voiceNoMicrophone,
        _ => AppStrings.voiceFailed,
      };

  /// Runs [action] after every transition already queued.
  ///
  /// Each call appends to the chain and becomes the new tail, so `enable` and
  /// `disable` can be issued in any order from any number of places and still
  /// take effect in the order they were asked for. A failing transition is
  /// logged and swallowed rather than poisoning the chain — the next one has
  /// to run regardless, because it may be the one that closes a microphone.
  Future<void> _serialize(Future<void> Function() action) {
    final Future<void> queued = (_transition ?? Future<void>.value())
        .then((_) => action())
        .catchError((Object error, StackTrace stackTrace) {
      AppLogger.w('VoiceChatService: transition failed', error, stackTrace);
    });

    _transition = queued;

    // Cleared only when this call is still the tail, so a completing
    // transition cannot drop one that was queued behind it.
    unawaited(
      queued.whenComplete(() {
        if (identical(_transition, queued)) _transition = null;
      }),
    );

    return queued;
  }

  /// Publishes a state, dropping it when nothing actually changed.
  ///
  /// Peer connection states churn — ICE moves through several before it
  /// settles — and every one of those would otherwise rebuild the widget that
  /// draws a single microphone icon.
  void _publish(VoiceChatState next) {
    if (_disposed || _stateController.isClosed) return;
    if (next == _state) return;
    _state = next;
    _stateController.add(next);
  }
}

/// One peer connection, plus the candidates that arrived too early for it.
class _PeerLink {
  _PeerLink({required this.peer, required this.connection});

  final VoicePeer peer;
  final RTCPeerConnection connection;

  MediaStream? remoteStream;

  /// Candidates received before the remote description was set.
  final List<RTCIceCandidate> _pending = <RTCIceCandidate>[];

  bool _remoteReady = false;

  /// Adds a candidate now, or holds it until the description arrives.
  Future<void> addOrQueue(RTCIceCandidate candidate) async {
    if (!_remoteReady) {
      _pending.add(candidate);
      return;
    }
    await _add(candidate);
  }

  /// Applies everything that was held back. Called once the description lands.
  Future<void> flushCandidates() async {
    _remoteReady = true;
    final List<RTCIceCandidate> queued = <RTCIceCandidate>[..._pending];
    _pending.clear();
    for (final RTCIceCandidate candidate in queued) {
      await _add(candidate);
    }
  }

  Future<void> _add(RTCIceCandidate candidate) async {
    try {
      await connection.addCandidate(candidate);
    } catch (error, stackTrace) {
      // One rejected candidate costs one network path, not the call: ICE tries
      // every other pair it has.
      AppLogger.w(
        'VoiceChatService: candidate rejected for ${peer.userId}',
        error,
        stackTrace,
      );
    }
  }
}

/// The drawer refusal as `s:voice:error` spells it.
///
/// The server sends two spellings of the same refusal: an `AppErrorCode` on an
/// ack, which `Failure.fromJson` parses into
/// [AppErrorCode.drawerVoiceDisabled], and this REST-flavoured `ErrorCode` on
/// the out-of-band event, which is the name the brief's security test looks
/// for. Both are handled, so neither wire shape can leave a drawer's
/// microphone open.
const String _drawerRefusedWireCode = 'DRAWER_VOICE_DISABLED';
