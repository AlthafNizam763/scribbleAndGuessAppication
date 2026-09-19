import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/features/games/common/bot_chip.dart';
import 'package:scribble_guess/features/games/common/game_audio.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/rematch_bar.dart';
import 'package:scribble_guess/features/games/ludo/widgets/ludo_board.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/games/ludo_state.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Who got all four counters home first.
///
/// Ranked by counters home and then by how far the rest have travelled, which
/// is the only ordering Ludo has — there is no score, and second place is
/// genuinely "closest to finishing". The winner comes from the server's own
/// result document; nothing here recomputes it from the board.
class LudoResultOverlay extends ConsumerStatefulWidget {
  const LudoResultOverlay({
    required this.state,
    required this.room,
    required this.selfId,
    super.key,
  });

  final LudoState state;
  final PlatformRoom? room;
  final String selfId;

  @override
  ConsumerState<LudoResultOverlay> createState() => _LudoResultOverlayState();
}

class _LudoResultOverlayState extends ConsumerState<LudoResultOverlay> {
  @override
  void initState() {
    super.initState();
    final String winner = asString(widget.state.result?['winnerId']);
    ref
        .read(gameAudioProvider(GameId.ludo))
        .finished(won: winner.isNotEmpty && winner == widget.selfId);
  }

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final String winnerId = asString(widget.state.result?['winnerId']);
    final bool iWon = winnerId.isNotEmpty && winnerId == widget.selfId;

    // Counters home first, then total distance travelled. A player with three
    // home beats one with two, and two players with two are separated by how
    // far their remaining counters have come.
    final List<String> standings = <String>[...widget.state.order]..sort(
        (String a, String b) {
          final LudoSeatState? left = widget.state.seatState(a);
          final LudoSeatState? right = widget.state.seatState(b);
          final int byHome = (right?.finished ?? 0).compareTo(left?.finished ?? 0);
          if (byHome != 0) return byHome;
          return _distance(right).compareTo(_distance(left));
        },
      );

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.84),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(metrics.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    iWon ? Icons.emoji_events_rounded : Icons.flag_rounded,
                    size: 38 * metrics.scale,
                    color: iWon ? skin.accent : skin.inkMuted,
                  ),
                  SizedBox(height: metrics.gutter * 0.5),
                  Text(
                    iWon ? 'All four home' : '${_nameOf(winnerId)} got home first',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(
                      color: iWon ? skin.accent : skin.ink,
                      fontFamily: skin.display,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  SizedBox(height: metrics.gutter * 1.2),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: EdgeInsets.all(metrics.gutter),
                    decoration: BoxDecoration(
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      border: Border.all(color: skin.edge),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (int place = 0; place < standings.length; place++)
                          _Row(
                            place: place + 1,
                            seat: widget.state.seatOf(standings[place]),
                            counters: widget.state.seatState(standings[place]),
                            player: widget.room?.seatOf(standings[place]),
                            isSelf: standings[place] == widget.selfId,
                          ),
                      ],
                    ),
                  ),

                  SizedBox(height: metrics.gutter * 1.2),
                  const RematchBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How far a seat's counters have travelled in total. The tie-breaker.
  static int _distance(LudoSeatState? seat) {
    if (seat == null) return 0;
    return seat.positions.fold(
      0,
      (int total, int position) =>
          total + (position == LudoGeometry.inYard ? 0 : position),
    );
  }

  String _nameOf(String playerId) {
    if (playerId.isEmpty) return 'Nobody';
    if (playerId == widget.selfId) return 'You';
    return widget.room?.seatOf(playerId)?.username ?? 'Somebody';
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.place,
    required this.seat,
    required this.counters,
    required this.player,
    required this.isSelf,
  });

  final int place;
  final int seat;
  final LudoSeatState? counters;
  final PlatformSeat? player;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = ludoSeatColours[(seat < 0 ? 0 : seat) % 4];

    return Padding(
      padding: EdgeInsets.only(bottom: metrics.gutter * 0.5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 22 * metrics.scale,
            child: Text(
              '$place',
              style: text.labelLarge?.copyWith(
                color: place == 1 ? skin.accent : skin.inkMuted,
                fontFamily: skin.display,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 12 * metrics.scale,
            height: 12 * metrics.scale,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          ),
          SizedBox(width: metrics.gutter * 0.4),
          if (player != null) ...<Widget>[
            PlayerAvatar(
              avatarId: player!.avatarId,
              colorIndex: player!.avatarColorIndex,
              size: 24 * metrics.scale,
            ),
            SizedBox(width: metrics.gutter * 0.4),
          ],
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    isSelf ? 'You' : (player?.username ?? 'Somebody'),
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: skin.ink,
                      fontWeight: isSelf ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                if (player?.isBot ?? false) ...<Widget>[
                  SizedBox(width: metrics.gutter * 0.3),
                  BotChip(difficulty: player!.botDifficulty),
                ],
              ],
            ),
          ),
          Text(
            '${counters?.finished ?? 0}/4 home',
            style: text.labelSmall?.copyWith(color: skin.inkMuted),
          ),
        ],
      ),
    );
  }
}
