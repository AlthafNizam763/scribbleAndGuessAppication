import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/features/games/common/game_hud.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/voice_diagnostics.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/models/voice_peer.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/providers/games/platform_voice_provider.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The microphone control, for every platform game.
///
/// ## One control, three games
///
/// Written once against [GameSkin], so a card table and a spaceship get the
/// same button in different pigments. The brief asks for exactly this and for
/// the same reason it asks for one chat panel: three microphone buttons would
/// be three sets of permission handling, three teardown paths and three places
/// for a live microphone to be left open.
///
/// ## What the button can and cannot say
///
/// It can say "you are in voice", "you are muted" and "the server will not let
/// you talk right now". It cannot *grant* voice — every join is a request the
/// server answers, and a refusal comes back with a reason the bar shows. On
/// ORBITAL-7 that reason changes during a match: the button is off while
/// the crew is working and lights up when a meeting is called.
class GameVoiceBar extends ConsumerStatefulWidget {
  const GameVoiceBar({this.compact = false, super.key});

  /// Renders the single button without the participant strip beside it.
  final bool compact;

  @override
  ConsumerState<GameVoiceBar> createState() => _GameVoiceBarState();
}

class _GameVoiceBarState extends ConsumerState<GameVoiceBar> {
  bool _diagnostics = false;

  @override
  Widget build(BuildContext context) {
    final VoiceChatState voice = ref.watch(platformVoiceProvider);
    final GameMetrics metrics = context.metrics;

    // Long-press opens the two-device checklist. Long-press rather than a
    // visible control because it is an instrument for whoever is testing a
    // call, not a feature — a player who never holds the button never learns
    // it is there, which is the intention.
    final Widget button = GestureDetector(
      onLongPress: () => setState(() => _diagnostics = !_diagnostics),
      child: _MicButton(voice: voice),
    );

    if (_diagnostics) {
      return Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          button,
          Positioned.fill(
            child: VoiceDiagnosticsPanel(
              onClose: () => setState(() => _diagnostics = false),
            ),
          ),
        ],
      );
    }

    if (widget.compact) return button;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (voice.isJoined) ...<Widget>[
          const VoiceParticipantStrip(),
          SizedBox(width: metrics.gutter * 0.4),
        ],
        button,
      ],
    );
  }
}

class _MicButton extends ConsumerWidget {
  const _MicButton({required this.voice});

  final VoiceChatState voice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool blocked = voice.blocker != VoiceBlocker.none;

    // Three states, and they are genuinely different actions: join, mute, and
    // "the device will not give us a microphone".
    final (IconData icon, String tooltip) = switch ((voice.isJoined, voice.isMuted, blocked)) {
      (_, _, true) => (Icons.mic_off_outlined, 'Microphone unavailable'),
      (false, _, _) => (Icons.headset_mic_outlined, 'Join voice'),
      (true, true, _) => (Icons.mic_off_rounded, 'Unmute'),
      (true, false, _) => (Icons.mic_rounded, 'Mute'),
    };

    return GameIconButton(
      icon: icon,
      tooltip: tooltip,
      active: voice.isJoined && !voice.isMuted && !blocked,
      onPressed: blocked
          ? null
          : () async {
              final PlatformVoiceNotifier notifier =
                  ref.read(platformVoiceProvider.notifier);
              if (!voice.isJoined) {
                await notifier.join();
              } else {
                await notifier.toggleMute();
              }
            },
    );
  }
}

/// Who else is in the mesh, and who is talking.
///
/// Deliberately tiny: it lives in the HUD over a live game, so it shows a dot
/// per peer rather than a list of names. Somebody wanting names opens the
/// player list, which has room for them.
class VoiceParticipantStrip extends ConsumerWidget {
  const VoiceParticipantStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VoiceChatState voice = ref.watch(platformVoiceProvider);
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;

    if (voice.peers.isEmpty) {
      return Text(
        'alone',
        style: TextStyle(
          color: skin.inkMuted,
          fontSize: 10 * metrics.scale,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gutter * 0.5,
        vertical: metrics.gutter * 0.3,
      ),
      decoration: BoxDecoration(
        color: skin.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: skin.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final VoicePeer peer in voice.peers.values)
            Padding(
              padding: EdgeInsets.only(right: 3 * metrics.scale),
              child: _PeerDot(peer: peer),
            ),
        ],
      ),
    );
  }
}

class _PeerDot extends StatelessWidget {
  const _PeerDot({required this.peer});

  final VoicePeer peer;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;

    final Color tint = switch (peer.state) {
      VoicePeerState.connected =>
        peer.muted ? skin.inkMuted : (peer.speaking ? skin.success : skin.ink),
      VoicePeerState.connecting => skin.inkMuted,
      VoicePeerState.failed => skin.danger,
    };

    return AnimatedContainer(
      duration: AppMotion.fast,
      width: (peer.speaking ? 10 : 7) * metrics.scale,
      height: (peer.speaking ? 10 : 7) * metrics.scale,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
    );
  }
}

/// The full roster: who is at the table, who is in voice, who is talking.
///
/// The brief's `GamePlayerList` and `VoiceParticipantList` in one widget,
/// because they are one list with two columns of state — splitting them would
/// mean two scroll views of the same people side by side.
class GamePlayerList extends ConsumerWidget {
  const GamePlayerList({this.highlightId = '', super.key});

  /// A seat to mark — whoever is on turn, usually.
  final String highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlatformRoom? room = ref.watch(platformSessionProvider).room;
    final VoiceChatState voice = ref.watch(platformVoiceProvider);
    final String selfId = ref.watch(platformSelfIdProvider);
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    if (room == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(metrics.gutter * 0.6),
      decoration: BoxDecoration(
        color: skin.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: skin.edge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final PlatformSeat seat in room.seats)
            Padding(
              padding: EdgeInsets.only(bottom: metrics.gutter * 0.35),
              child: Row(
                children: <Widget>[
                  PlayerAvatar(
                    avatarId: seat.avatarId,
                    colorIndex: seat.avatarColorIndex,
                    size: 22 * metrics.scale,
                    dimmed: !seat.connected,
                  ),
                  SizedBox(width: metrics.gutter * 0.4),
                  Flexible(
                    child: Text(
                      seat.playerId == selfId ? 'You' : seat.username,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                        color: seat.playerId == highlightId ? skin.accent : skin.ink,
                        fontWeight: seat.playerId == highlightId
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.gutter * 0.3),
                  // A bot has no microphone, and saying so is clearer than an
                  // empty space where a mic icon would be.
                  if (seat.isBot)
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 12 * metrics.scale,
                      color: skin.inkMuted,
                    )
                  else
                    _VoiceMark(
                      peer: voice.peers[seat.playerId],
                      isSelf: seat.playerId == selfId,
                      selfJoined: voice.isJoined,
                      selfMuted: voice.isMuted,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceMark extends StatelessWidget {
  const _VoiceMark({
    required this.peer,
    required this.isSelf,
    required this.selfJoined,
    required this.selfMuted,
  });

  final VoicePeer? peer;
  final bool isSelf;
  final bool selfJoined;
  final bool selfMuted;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final double size = 13 * metrics.scale;

    if (isSelf) {
      if (!selfJoined) {
        return Icon(Icons.headset_off_outlined, size: size, color: skin.inkMuted);
      }
      return Icon(
        selfMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
        size: size,
        color: selfMuted ? skin.inkMuted : skin.success,
      );
    }

    if (peer == null) {
      // In the room but not in voice. Common and unremarkable.
      return Icon(Icons.headset_off_outlined, size: size, color: skin.inkMuted);
    }

    return Icon(
      peer!.muted
          ? Icons.mic_off_rounded
          : peer!.speaking
              ? Icons.graphic_eq_rounded
              : Icons.mic_rounded,
      size: size,
      color: switch (peer!.state) {
        VoicePeerState.failed => skin.danger,
        VoicePeerState.connecting => skin.inkMuted,
        VoicePeerState.connected =>
          peer!.speaking ? skin.success : skin.inkMuted,
      },
    );
  }
}
