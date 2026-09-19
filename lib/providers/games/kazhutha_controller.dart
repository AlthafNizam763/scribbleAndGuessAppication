import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/games/kazhutha_state.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';

/// Kazhutha, as the screen is allowed to ask for it.
///
/// ## What a "socket controller" is here
///
/// A typed command surface, and nothing else. It owns no state, holds no
/// subscription and parses no payload — [PlatformSessionNotifier] does all of
/// that for every platform game at once. What this adds is the vocabulary:
/// a screen calls `draw`, not `act('game:action', {'type': 'draw_card', ...})`,
/// so the call site reads as the game it is playing.
///
/// ## It refuses nothing
///
/// Deliberately. Every method here sends and reports what the server said. The
/// legality of a draw — whose turn it is, whether that seat still holds cards,
/// whether the index is real — is decided in one place, and that place is the
/// server. A second opinion here would be a second rules engine, and the two
/// would disagree the first time either changed.
///
/// The screen still greys out an illegal target, because offering a tap that
/// will be refused is bad manners. That is presentation, not enforcement.
class KazhuthaController {
  const KazhuthaController(this._ref);

  final Ref _ref;

  /// Draws one card from [targetPlayerId]'s fan.
  ///
  /// [cardIndex] is a *position*, not a card. The server reshuffles that hand
  /// the instant before the pick, so which position is chosen carries no
  /// information — it exists so that reaching for a card feels like reaching
  /// for a card, and so an agreed "third from the left" cannot hand somebody
  /// the donkey over voice chat.
  Future<Result<void>> draw({
    required String targetPlayerId,
    required int cardIndex,
  }) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientKazhuthaDraw,
      <String, dynamic>{
        'targetPlayerId': targetPlayerId,
        'cardIndex': cardIndex,
      },
    );
  }
}

final Provider<KazhuthaController> kazhuthaControllerProvider =
    Provider<KazhuthaController>(KazhuthaController.new);

/// The table, parsed from whatever projection arrived last.
///
/// Derived rather than stored: there is exactly one source of truth — the
/// session's match state — and a second copy that had to be kept in step with
/// it would eventually not be.
final Provider<KazhuthaState> kazhuthaStateProvider = Provider<KazhuthaState>(
  (Ref ref) {
    final Map<String, dynamic>? projection =
        ref.watch(platformSessionProvider).match?.state;
    if (projection == null) return KazhuthaState.empty;
    return KazhuthaState.fromJson(projection);
  },
);

/// Whether it is the local player's turn to draw.
final Provider<bool> kazhuthaIsMyTurnProvider = Provider<bool>(
  (Ref ref) => ref
      .watch(kazhuthaStateProvider)
      .isTurnOf(ref.watch(platformSelfIdProvider)),
);

/// The local player's own seat, or `null` before the deal.
final Provider<KazhuthaSeat?> kazhuthaMySeatProvider = Provider<KazhuthaSeat?>(
  (Ref ref) =>
      ref.watch(kazhuthaStateProvider).seatOf(ref.watch(platformSelfIdProvider)),
);

/// The most recent refusal, for the table to say out loud.
final Provider<Failure?> kazhuthaErrorProvider = Provider<Failure?>(
  (Ref ref) => ref.watch(platformSessionProvider).lastError,
);
