import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/voice_peer.dart';
import 'package:scribble_guess/providers/games/platform_voice_provider.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The two-client voice checklist, run against a live connection.
///
/// ## Why this exists
///
/// WebRTC cannot be verified from a unit test. The signalling can — and is,
/// in `platformClientFlow.test.ts` — but whether two phones actually hear each
/// other depends on microphones, NAT traversal and ICE, none of which exist in
/// a headless runner. The only honest verification is two devices in a room,
/// and the only thing code can contribute is to make that session *legible*:
/// to show, live, which of the nine steps have happened and which have not.
///
/// So this is not a test and does not pretend to be one. It is an instrument.
/// Every row reads real state off the running [VoiceChatService] — the peer
/// map, each peer's `RTCPeerConnectionState`, the mute flags, the audio levels
/// — and turns it into a checklist somebody holding two phones can tick off.
///
/// ## How to use it
///
/// Open the same match on two devices, open this panel on both, and join
/// voice. A row goes green when its condition is genuinely true on *this*
/// device. Both devices should reach "audio flowing"; if one does and the
/// other does not, the asymmetry is the bug and the row that stops is where.
///
/// ## What it cannot tell you
///
/// Whether the audio is *audible*. A track can be live, unmuted and carrying
/// silence — a muted hardware microphone, a device that routed to an earpiece,
/// a permission granted but disconnected. The last step is always a person
/// saying something and the other person hearing it, and no panel replaces
/// that.
class VoiceDiagnosticsPanel extends ConsumerStatefulWidget {
  const VoiceDiagnosticsPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<VoiceDiagnosticsPanel> createState() =>
      _VoiceDiagnosticsPanelState();
}

class _VoiceDiagnosticsPanelState extends ConsumerState<VoiceDiagnosticsPanel> {
  /// The last two steps are *transitions*, not states.
  ///
  /// "Leave removes the peer" and "a reconnect rebuilds the mesh" are both
  /// true for an instant and false again immediately after, so reading the
  /// current peer map cannot show them — by the time somebody looks at the
  /// panel the peer is simply gone, which looks identical to never having
  /// arrived. These two latch when they happen and stay lit, which is what
  /// makes them tickable on a checklist.
  int _peakPeers = 0;
  bool _sawDeparture = false;
  bool _sawRebuild = false;

  /// Whether the mesh has been empty since a peer was last seen, so a peer
  /// arriving after a gap is a rebuild rather than a first connection.
  bool _wasEmptied = false;

  void _observe(VoiceChatState voice) {
    final int now = voice.peers.length;

    if (now > _peakPeers) _peakPeers = now;
    if (_peakPeers > 0 && now == 0 && !_sawDeparture) {
      _sawDeparture = true;
      _wasEmptied = true;
    } else if (now > 0 && _wasEmptied && !_sawRebuild) {
      _sawRebuild = true;
      _wasEmptied = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final VoiceChatState voice = ref.watch(platformVoiceProvider);
    _observe(voice);
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final List<VoicePeer> peers = voice.peers.values.toList(growable: false);
    final bool anyConnected =
        peers.any((VoicePeer p) => p.state == VoicePeerState.connected);
    final bool anySpeaking = peers.any((VoicePeer p) => p.speaking);

    final List<_Check> checks = <_Check>[
      _Check(
        'Microphone open',
        // The blocker is the device's answer, not ours: a declined permission
        // and a device with no capture hardware look different here.
        done: voice.blocker == VoiceBlocker.none && voice.isJoined,
        detail: switch (voice.blocker) {
          VoiceBlocker.permissionDenied => 'Permission refused',
          VoiceBlocker.microphoneUnavailable => 'No capture device',
          VoiceBlocker.failed => 'Failed to open',
          VoiceBlocker.none => voice.isJoined ? 'Open' : 'Not joined',
        },
      ),
      _Check(
        'Server admitted us',
        done: voice.isJoined,
        // A refusal here is the rule doing its job — a ghost, a drinker out of
        // glasses, a drawer holding the pen — and the reason says which.
        detail: voice.isJoined
            ? 'In the mesh'
            : (voice.error ?? 'Refused or not asked'),
      ),
      _Check(
        'Peer discovered',
        done: peers.isNotEmpty,
        detail: peers.isEmpty
            ? 'Nobody else has joined'
            : '${peers.length} peer${peers.length == 1 ? '' : 's'}',
      ),
      _Check(
        'Offer / answer exchanged',
        // Leaving `connecting` at all means the description round trip
        // completed: a peer that never got an answer stays there.
        done: peers.any((VoicePeer p) => p.state != VoicePeerState.connecting),
        detail: _describeStates(peers),
      ),
      _Check(
        'ICE connected',
        done: anyConnected,
        detail: anyConnected
            ? 'At least one peer connected'
            : 'No candidate pair succeeded yet',
      ),
      _Check(
        'Audio flowing',
        // Level polling reads WebRTC's own statistics, so this is true only
        // when samples are genuinely arriving from the far end.
        done: anySpeaking,
        detail: anySpeaking
            ? 'Remote audio detected'
            : 'Ask the other device to talk',
      ),
      _Check(
        'Mute propagates',
        done: peers.any((VoicePeer p) => p.muted),
        detail: 'Mute on the other device and watch this row',
      ),
      _Check(
        'Leave removes the peer',
        done: _sawDeparture,
        detail: _sawDeparture
            ? 'The mesh emptied cleanly'
            : 'Have the other device leave voice',
      ),
      _Check(
        'Reconnect rebuilds the mesh',
        done: _sawRebuild,
        detail: _sawRebuild
            ? 'A peer came back without a tap'
            : 'Flight-mode the other device for ten seconds',
      ),
    ];

    return Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        child: Container(
          width: (metrics.size.width * 0.46).clamp(260.0, 360.0),
          margin: EdgeInsets.all(metrics.gutter * 0.5),
          padding: EdgeInsets.all(metrics.gutter * 0.75),
          decoration: BoxDecoration(
            color: skin.surface.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: skin.edge),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.biotech_rounded, size: 16, color: skin.accent),
                  SizedBox(width: metrics.gutter * 0.4),
                  Expanded(
                    child: Text(
                      'VOICE CHECK',
                      style: text.labelMedium?.copyWith(
                        color: skin.inkMuted,
                        fontFamily: skin.display,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: Icon(Icons.close_rounded, size: 18, color: skin.inkMuted),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              SizedBox(height: metrics.gutter * 0.3),
              for (final _Check check in checks) _CheckRow(check: check),
              SizedBox(height: metrics.gutter * 0.4),
              Text(
                'Two devices, same match. A green row is true on this device '
                'only — compare both.',
                style: text.labelSmall?.copyWith(color: skin.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _describeStates(List<VoicePeer> peers) {
    if (peers.isEmpty) return '—';
    final int connecting =
        peers.where((VoicePeer p) => p.state == VoicePeerState.connecting).length;
    final int connected =
        peers.where((VoicePeer p) => p.state == VoicePeerState.connected).length;
    final int failed =
        peers.where((VoicePeer p) => p.state == VoicePeerState.failed).length;
    return '$connected up · $connecting pending · $failed failed';
  }
}

@immutable
class _Check {
  const _Check(this.label, {required this.done, required this.detail});

  final String label;
  final bool done;
  final String detail;
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final _Check check;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            check.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 15,
            color: check.done ? skin.success : skin.inkMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  check.label,
                  style: text.labelMedium?.copyWith(
                    color: check.done ? skin.ink : skin.inkMuted,
                    fontWeight: check.done ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  check.detail,
                  style: text.labelSmall?.copyWith(color: skin.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
