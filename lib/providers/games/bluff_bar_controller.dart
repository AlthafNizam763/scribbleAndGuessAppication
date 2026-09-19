import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/games/bluff_bar_state.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';

/// Bluff Bar, as the table is allowed to ask for it.
///
/// A typed command surface over the shared [PlatformSessionNotifier]. It owns
/// no state and enforces nothing: whether a claim is legal, whether a call is
/// allowed and who ends up drinking are all decided once, on the server.
class BluffBarController {
  const BluffBarController(this._ref);

  final Ref _ref;

  /// Puts cards face down, claiming they are all the table rank.
  ///
  /// [cardIds] are instance ids, not faces — the shoe holds duplicates, so
  /// "the ace of spades" is ambiguous and `b07` is not.
  ///
  /// The claim is *always* that they are the table rank. There is no honest
  /// mode and no lying mode, because at a real table there is no such
  /// declaration: you put cards down and say what they are, and the only
  /// question is whether anybody believes you.
  Future<Result<void>> declare({
    required List<String> cardIds,
    BarReaction? reaction,
  }) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientBluffDeclare,
      <String, dynamic>{
        'cardIds': cardIds,
        if (reaction != null) 'reaction': reaction.wire,
      },
    );
  }

  /// Calls the standing claim a lie, and pays for it if it was not.
  Future<Result<void>> challenge({BarReaction? reaction}) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientBluffChallenge,
      <String, dynamic>{if (reaction != null) 'reaction': reaction.wire},
    );
  }

  /// Table talk. Legal at any moment from anybody still at the table.
  Future<Result<void>> react(BarReaction reaction) {
    return _ref.read(platformSessionProvider.notifier).act(
      SocketEvents.clientBluffReact,
      <String, dynamic>{'reaction': reaction.wire},
    );
  }
}

final Provider<BluffBarController> bluffBarControllerProvider =
    Provider<BluffBarController>(BluffBarController.new);

/// The table, parsed from whatever projection arrived last.
final Provider<BluffBarState> bluffBarStateProvider = Provider<BluffBarState>(
  (Ref ref) {
    final Map<String, dynamic>? projection =
        ref.watch(platformSessionProvider).match?.state;
    if (projection == null) return BluffBarState.empty;
    return BluffBarState.fromJson(projection);
  },
);

/// Whether it is the local player's move.
final Provider<bool> bluffBarIsMyTurnProvider = Provider<bool>(
  (Ref ref) => ref
      .watch(bluffBarStateProvider)
      .isTurnOf(ref.watch(platformSelfIdProvider)),
);

/// The local player's own seat, for the tray and the nerve meter.
final Provider<BarSeat?> bluffBarMySeatProvider = Provider<BarSeat?>(
  (Ref ref) =>
      ref.watch(bluffBarStateProvider).seatOf(ref.watch(platformSelfIdProvider)),
);
