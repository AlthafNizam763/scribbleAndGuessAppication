import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/games/ludo_state.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';

/// Ludo, as the board is allowed to ask for it.
///
/// Two verbs, and neither of them decides anything. **The dice are the
/// server's**: [roll] asks for one and is told what came up. A client that
/// generated its own number and reported it would be a client that rolled
/// sixes all afternoon, which is why there is no local random anywhere in this
/// game except the faces that flicker past during the tumble animation — and
/// those are discarded the moment the real value lands.
class LudoController {
  const LudoController(this._ref);

  final Ref _ref;

  /// Asks the server for a roll.
  ///
  /// Refused if there is already one on the table, which is the server's rule
  /// and not this class's: a player must spend a roll before asking for
  /// another.
  Future<Result<void>> roll() => _ref
      .read(platformSessionProvider.notifier)
      .act(SocketEvents.clientLudoRoll);

  /// Moves one of this player's four counters with the roll on the table.
  ///
  /// Which counters may move is decided on the server. The board only lights
  /// up the ones it believes are legal so a player is not offered four taps
  /// and refused three — see `LudoState.movableTokens`, which is explicitly a
  /// courtesy rather than a rule.
  Future<Result<void>> move(int tokenIndex) => _ref
      .read(platformSessionProvider.notifier)
      .act(
        SocketEvents.clientLudoMove,
        <String, dynamic>{'tokenIndex': tokenIndex},
      );
}

final Provider<LudoController> ludoControllerProvider =
    Provider<LudoController>(LudoController.new);

/// The board, parsed from whatever projection arrived last.
final Provider<LudoState> ludoStateProvider = Provider<LudoState>(
  (Ref ref) {
    final Map<String, dynamic>? projection =
        ref.watch(platformSessionProvider).match?.state;
    if (projection == null) return LudoState.empty;
    return LudoState.fromJson(projection);
  },
);

/// Whether it is the local player's turn.
final Provider<bool> ludoIsMyTurnProvider = Provider<bool>(
  (Ref ref) =>
      ref.watch(ludoStateProvider).isTurnOf(ref.watch(platformSelfIdProvider)),
);

/// Which of the local player's counters the roll could move.
final Provider<List<int>> ludoMovableProvider = Provider<List<int>>(
  (Ref ref) => ref
      .watch(ludoStateProvider)
      .movableTokens(ref.watch(platformSelfIdProvider)),
);
