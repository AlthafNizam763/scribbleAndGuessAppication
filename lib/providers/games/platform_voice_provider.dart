import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/voice_peer.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/services/voice/voice_dialect.dart';
import 'package:scribble_guess/services/voice_chat_service.dart';

/// Voice chat for whichever platform game is open.
///
/// ## Why this is a second service instance and not a second implementation
///
/// It is the *same* [VoiceChatService]. All that differs is the
/// [VoiceDialect] it is handed — six event names and an envelope naming the
/// room — because the microphone handling, the mesh construction, the
/// offer/answer race resolution, the level polling and the teardown are
/// identical and there was never a reason to write them twice.
///
/// A separate instance rather than a shared one because the two can be alive
/// at the same time: a player who was in a Scribble room a moment ago may
/// still have that service holding a microphone. Each listens only for its own
/// dialect's events, so neither hears the other's signalling.
final Provider<VoiceChatService> platformVoiceServiceProvider =
    Provider<VoiceChatService>(
  (Ref ref) {
    final GameId gameId =
        ref.watch(platformSessionProvider).gameId ?? GameId.kazhutha;

    final VoiceChatService service = VoiceChatService(
      gateway: ref.watch(gatewayProvider),
      selfId: ref.watch(selfIdProvider),
      dialect: VoiceDialect.platform(
        gameId: gameId,
        // Read at send time rather than captured, so a frame sent after a room
        // change carries the room it is actually for.
        roomId: () => ref.read(platformSessionProvider).room?.roomId ?? '',
      ),
    );

    // Disposal is the whole reason this is a provider rather than a field on
    // a screen: a player who leaves a match must stop holding a microphone and
    // stop signalling, and a screen that was popped cannot be relied on to say
    // so.
    ref.onDispose(service.dispose);
    return service;
  },
);

/// The live voice state for the platform game.
class PlatformVoiceNotifier extends Notifier<VoiceChatState> {
  @override
  VoiceChatState build() {
    final VoiceChatService service = ref.watch(platformVoiceServiceProvider);

    final StreamSubscription<VoiceChatState> subscription =
        service.stateStream.listen((VoiceChatState next) => state = next);
    ref.onDispose(subscription.cancel);

    /// Hangs up when the player leaves the room.
    ///
    /// The service above is rebuilt — and therefore disposed — when the *game*
    /// changes, which covers moving from one game to another. It does not
    /// cover leaving a Kazhutha table and going back to the lobby, because the
    /// game id falls back to the same value and nothing rebuilds. Without
    /// this, that player walks out of the match still holding an open
    /// microphone and a mesh of peer connections.
    ///
    /// Watching the room id rather than the session covers every way out:
    /// leaving, being dropped, a rematch that moved the room, and a match
    /// that ended and closed it.
    ref.listen<String>(
      platformSessionProvider.select(
        (PlatformSession session) => session.room?.roomId ?? '',
      ),
      (String? previous, String next) {
        final bool left = previous != null && previous.isNotEmpty && next != previous;
        if (left) unawaited(service.applyRole(VoiceRole.disabled));
      },
    );

    return service.state;
  }

  /// Asks the server for a place in the mesh.
  ///
  /// The client does not decide whether it gets one. Space Mystery refuses
  /// outside a meeting and refuses the dead outright, Bluff Bar refuses a
  /// player who has run out of glasses — and each refusal comes back as a
  /// message the bar can show rather than a silent failure.
  Future<void> join() async {
    final VoiceChatService service = ref.read(platformVoiceServiceProvider);
    await service.applyRole(VoiceRole.guesser);
  }

  Future<void> leave() async {
    final VoiceChatService service = ref.read(platformVoiceServiceProvider);
    await service.applyRole(VoiceRole.disabled);
  }

  Future<void> toggleMute() async {
    final VoiceChatService service = ref.read(platformVoiceServiceProvider);
    await service.setMuted(!state.isMuted);
  }

  /// Opens or closes voice, whichever is the opposite of now.
  Future<void> toggle() => state.isJoined ? leave() : join();
}

final NotifierProvider<PlatformVoiceNotifier, VoiceChatState>
    platformVoiceProvider =
    NotifierProvider<PlatformVoiceNotifier, VoiceChatState>(
  PlatformVoiceNotifier.new,
);
