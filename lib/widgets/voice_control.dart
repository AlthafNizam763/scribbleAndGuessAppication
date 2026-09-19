import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/responsive.dart';
import 'package:scribble_guess/core/widgets/app_dialogs.dart';
import 'package:scribble_guess/core/widgets/tap_feedback.dart';
import 'package:scribble_guess/models/voice_peer.dart';
import 'package:scribble_guess/providers/voice_chat_provider.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The whole of voice chat's interface: one button, or one line of text.
///
/// Sized and drawn to sit inside the existing game header without changing it
/// — the same hand-drawn outline, the same ink, the same badge proportions as
/// the round counter beside it. Voice is a small convenience in a drawing
/// game, and a panel for it would say otherwise.
///
/// Three states, and they are mutually exclusive by construction:
///
/// - the drawer sees a status and no control at all, because there is nothing
///   for them to control this turn;
/// - a guesser sees a microphone button;
/// - outside a turn there is nothing to show, so nothing is shown.
class VoiceControl extends ConsumerWidget {
  const VoiceControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VoiceChatState voice = ref.watch(voiceChatProvider);

    return switch (voice.role) {
      VoiceRole.drawer => const _DrawerStatus(),
      VoiceRole.guesser => _GuesserControl(voice: voice),
      VoiceRole.disabled => const SizedBox.shrink(),
    };
  }
}

/// What the drawer sees: a statement, not a control.
///
/// Deliberately not a disabled microphone button. A greyed-out button invites
/// a tap and implies the restriction is temporary or negotiable; this turn it
/// is neither, and the player has a canvas to be looking at instead.
class _DrawerStatus extends StatelessWidget {
  const _DrawerStatus();

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = colors.textMuted;

    // The full sentence where there is room for it. On a phone the header
    // caption already reads "You are drawing" two centimetres to the left, so
    // the short form says the same thing without squeezing it.
    final String label =
        context.isCompact ? context.l10n.voiceOff : context.l10n.voiceDrawerStatus;

    return Semantics(
      label: context.l10n.voiceDrawerStatus,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: tint, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.mic_off_outlined, size: 12, color: tint),
            const SizedBox(width: 4),
            Text(label, style: text.labelSmall?.copyWith(color: tint)),
          ],
        ),
      ),
    );
  }
}

/// What a guesser sees: a microphone button, and a hint of who is talking.
class _GuesserControl extends ConsumerWidget {
  const _GuesserControl({required this.voice});

  final VoiceChatState voice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool blocked = voice.blocker != VoiceBlocker.none;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Web only, and invisible. A browser will not play a remote audio
        // track that is not attached to an element in the document, so the
        // renderers have to be mounted somewhere; a native build has an empty
        // map here and pays nothing.
        if (kIsWeb) const _RemoteAudioSinks(),

        if (voice.livePeers.any((VoicePeer peer) => peer.speaking))
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: _SpeakingDot(),
          ),

        _MicButton(
          muted: voice.isMuted,
          blocked: blocked,
          connecting: voice.isConnecting,
          onPressed: () => blocked
              ? _explainBlocker(context, ref, voice.blocker)
              : ref.read(voiceChatProvider.notifier).toggleMute(),
        ),
      ],
    );
  }

  /// Explains why the microphone is unusable, and offers to try again.
  ///
  /// A player who grants the permission in system settings generates no event
  /// the app can hear, so asking again is the only way to find out — which is
  /// why this offers a retry rather than only an apology.
  Future<void> _explainBlocker(
    BuildContext context,
    WidgetRef ref,
    VoiceBlocker blocker,
  ) async {
    final String message = switch (blocker) {
      VoiceBlocker.permissionDenied => context.l10n.voicePermissionBody,
      VoiceBlocker.microphoneUnavailable => context.l10n.voiceNoMicrophone,
      _ => context.l10n.voiceFailed,
    };

    final bool retry = await confirm(
      context,
      title: context.l10n.voiceNoPermission,
      message: message,
      confirmLabel: context.l10n.retry,
      cancelLabel: context.l10n.cancel,
    );

    if (retry) await ref.read(voiceChatProvider.notifier).retry();
  }
}

/// The microphone button.
///
/// Same 36pt square and 1.5pt outline as the stepper buttons in the room
/// settings, so it reads as part of the same kit rather than as a control
/// borrowed from a calling app.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.muted,
    required this.blocked,
    required this.connecting,
    required this.onPressed,
  });

  final bool muted;
  final bool blocked;
  final bool connecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    final (IconData icon, Color tint) = switch ((blocked, muted)) {
      (true, _) => (Icons.mic_off_outlined, colors.textFaint),
      (_, true) => (Icons.mic_off, colors.danger),
      _ => (Icons.mic, colors.accentGreen),
    };

    final String label = switch ((blocked, muted)) {
      (true, _) => context.l10n.voiceNoPermission,
      (_, true) => context.l10n.voiceUnmute,
      _ => context.l10n.voiceMute,
    };

    return Semantics(
      button: true,
      toggled: !muted && !blocked,
      label: label,
      child: Tooltip(
        message: connecting ? context.l10n.voiceConnecting : label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            TapFeedback.press(context);
            onPressed();
          },
          child: Container(
            height: 36,
            width: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: muted || blocked ? 0 : 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: tint, width: 1.5),
            ),
            child: Icon(icon, size: 18, color: tint),
          ),
        ),
      ),
    );
  }
}

/// A small mark that somebody is talking.
///
/// Deliberately anonymous. Naming the speaker would mean a row of avatars in a
/// header that is already carrying a round counter, a word and a countdown,
/// and the players can hear who it is.
class _SpeakingDot extends StatelessWidget {
  const _SpeakingDot();

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return Semantics(
      label: context.l10n.voiceSomeoneSpeaking,
      child: Icon(
        Icons.graphic_eq,
        size: 16,
        color: colors.accentGreen,
      ),
    );
  }
}

/// Invisible media elements that make remote audio audible in a browser.
///
/// One pixel and fully transparent, because it has to be laid out and painted
/// to exist in the document, but has nothing to show: these are audio-only
/// streams. Never built on a native platform.
class _RemoteAudioSinks extends ConsumerWidget {
  const _RemoteAudioSinks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched so the sinks appear as tracks arrive: the service republishes
    // its state when a renderer is attached, for exactly this reason.
    ref.watch(voiceChatProvider);
    final Map<String, RTCVideoRenderer> renderers =
        ref.read(voiceChatServiceProvider).remoteRenderers;

    if (renderers.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 1,
      width: 1,
      child: Opacity(
        opacity: 0,
        child: Stack(
          children: <Widget>[
            for (final RTCVideoRenderer renderer in renderers.values)
              RTCVideoView(renderer),
          ],
        ),
      ),
    );
  }
}
