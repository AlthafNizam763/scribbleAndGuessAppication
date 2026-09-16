import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/voice_peer.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/providers/session_providers.dart';
import 'package:scribble_guess/services/voice_chat_service.dart';

/// The voice engine, created once and kept for the life of the app.
///
/// Created alongside the socket rather than with the game screen: the service
/// listens to the gateway's inbound stream, and a service that only existed
/// while the canvas was on screen would miss the `s:voice:state` push that
/// arrives with the very first room state.
final Provider<VoiceChatService> voiceChatServiceProvider =
    Provider<VoiceChatService>((Ref ref) {
  final VoiceChatService service = VoiceChatService(
    gateway: ref.watch(gatewayProvider),
    selfId: ref.watch(selfIdProvider),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Which voice role the authoritative game state implies for this player.
///
/// Derived, never stored. The server decides who draws; this only translates
/// that decision into the three cases voice cares about, and it does so from
/// the same [GameState] the canvas and the word display read — so the pen, the
/// word mask and the microphone can never disagree about whose turn it is.
///
/// The phases listed here mirror `VOICE_PHASES` in the backend's
/// `voice.service.ts`. They have to: a client that asked to join outside one
/// would simply be refused.
final Provider<VoiceRole> voiceRoleProvider = Provider<VoiceRole>((Ref ref) {
  final GameState game = ref.watch(gameProvider);
  final String selfId = ref.watch(selfIdProvider);

  final bool voicePhase = switch (game.phase) {
    GamePhase.wordSelection || GamePhase.drawing || GamePhase.roundEnd => true,
    _ => false,
  };

  if (!voicePhase || selfId.isEmpty) return VoiceRole.disabled;
  return game.isDrawer(selfId) ? VoiceRole.drawer : VoiceRole.guesser;
});

/// Voice state, and the thing that keeps it in step with the game.
///
/// ## Why the role is pushed rather than pulled
///
/// The rule — the drawer is silent — has to take effect the instant the pen
/// moves, and the pen moves because of a server broadcast, not because of
/// anything the player did. So this notifier watches [voiceRoleProvider] and
/// hands every change to the service, which opens or closes the microphone and
/// the peer connections accordingly.
///
/// That covers every case the brief lists without any of them needing their
/// own code path: a game starting, a round starting, the drawer changing, the
/// next round, a reconnect and a game reset are all just a new [GameState],
/// and a new [GameState] is a new role.
///
/// ## Why the server is still the authority
///
/// Nothing here is a permission check. If this notifier were deleted the rule
/// would still hold, because `voice.service.ts` refuses `c:voice:*` from the
/// drawer outright. This exists so a *correct* client behaves correctly and
/// promptly — it stops the microphone rather than having its packets refused.
class VoiceChatNotifier extends Notifier<VoiceChatState> {
  StreamSubscription<VoiceChatState>? _subscription;

  @override
  VoiceChatState build() {
    final VoiceChatService service = ref.watch(voiceChatServiceProvider);

    _subscription = service.stateStream.listen(
      (VoiceChatState next) => state = next,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.w('VoiceChatNotifier: state stream error', error, stackTrace);
      },
    );

    // Watched, not read: this is the whole mechanism. Riverpod re-runs the
    // listener on every role change, and the service does the rest.
    ref.listen<VoiceRole>(
      voiceRoleProvider,
      (VoiceRole? previous, VoiceRole next) {
        if (previous == next) return;
        unawaited(service.applyRole(next));
      },
      fireImmediately: true,
    );

    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _subscription = null;
    });

    return service.state;
  }

  /// Mutes or unmutes the local microphone.
  Future<void> setMuted(bool muted) =>
      ref.read(voiceChatServiceProvider).setMuted(muted);

  /// Flips the microphone.
  Future<void> toggleMute() => setMuted(!state.isMuted);

  /// Retries after a refused or failed microphone.
  ///
  /// The player may have granted the permission in system settings since,
  /// which nothing pushes back to the app, so the only way to find out is to
  /// ask again.
  Future<void> retry() async {
    final VoiceChatService service = ref.read(voiceChatServiceProvider);
    if (ref.read(voiceRoleProvider) != VoiceRole.guesser) return;
    await service.enable();
  }
}

final NotifierProvider<VoiceChatNotifier, VoiceChatState> voiceChatProvider =
    NotifierProvider<VoiceChatNotifier, VoiceChatState>(VoiceChatNotifier.new);

/// Whether a given player is audibly speaking right now.
///
/// Exposed per player so a scoreboard row can bind to one peer instead of to
/// the whole mesh, which is what stops every row rebuilding when any one
/// person starts talking.
final ProviderFamily<bool, String> voiceSpeakingProvider =
    Provider.family<bool, String>((Ref ref, String playerId) {
  final VoiceChatState voice = ref.watch(voiceChatProvider);
  return voice.peers[playerId]?.speaking ?? false;
});
