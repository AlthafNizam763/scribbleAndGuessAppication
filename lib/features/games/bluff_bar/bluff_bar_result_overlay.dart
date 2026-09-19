import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/features/games/bluff_bar/widgets/bluff_bar_table.dart';
import 'package:scribble_guess/features/games/common/bot_chip.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/rematch_bar.dart';
import 'package:scribble_guess/models/games/bluff_bar_state.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/sound_provider.dart';
import 'package:scribble_guess/services/sound_service.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Last one standing at the bar.
///
/// The winner is whoever still has glasses left, so the scoreboard is the
/// trays: how close everybody came, in the one unit the whole match was played
/// in. A points total would be a number nobody had been watching.
class BluffBarResultOverlay extends ConsumerStatefulWidget {
  const BluffBarResultOverlay({
    required this.state,
    required this.room,
    required this.selfId,
    required this.result,
    super.key,
  });

  final BluffBarState state;
  final PlatformRoom? room;
  final String selfId;

  /// The server's own result document. Authoritative; nothing here recomputes
  /// a winner from the seats.
  final Map<String, dynamic>? result;

  @override
  ConsumerState<BluffBarResultOverlay> createState() =>
      _BluffBarResultOverlayState();
}

class _BluffBarResultOverlayState extends ConsumerState<BluffBarResultOverlay> {
  @override
  void initState() {
    super.initState();
    ref.read(soundServiceProvider).play(SoundEffect.gameEnd);
  }


  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final String winnerId = asString(widget.result?['winnerId']);
    final bool iWon = winnerId.isNotEmpty && winnerId == widget.selfId;
    final int rounds = asInt(widget.result?['rounds']);

    // Ranked by what is left on the tray, which is exactly how close each of
    // them came to not being here.
    final List<BarSeat> standings = <BarSeat>[...widget.state.seats]..sort(
        (BarSeat a, BarSeat b) {
          if (a.alive != b.alive) return a.alive ? -1 : 1;
          return b.glassesRemaining.compareTo(a.glassesRemaining);
        },
      );

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.88),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(metrics.gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  iWon ? Icons.local_bar_rounded : Icons.nightlife_rounded,
                  size: 40 * metrics.scale,
                  color: iWon ? skin.accent : skin.inkMuted,
                ),
                SizedBox(height: metrics.gutter * 0.6),
                Text(
                  iWon ? 'Still standing' : '${_nameOf(winnerId)} is still standing',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                    color: iWon ? skin.accent : skin.ink,
                    fontFamily: skin.display,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: metrics.gutter * 0.25),
                Text(
                  rounds > 0
                      ? 'The house closed after $rounds round${rounds == 1 ? '' : 's'}.'
                      : 'The house is closed.',
                  style: text.bodySmall?.copyWith(color: skin.inkMuted),
                ),

                SizedBox(height: metrics.gutter * 1.4),
                Container(
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: EdgeInsets.all(metrics.gutter),
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: skin.edge, width: AppSpacing.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final BarSeat seat in standings)
                        _Row(
                          seat: seat,
                          player: widget.room?.seatOf(seat.playerId),
                          isSelf: seat.playerId == widget.selfId,
                        ),
                    ],
                  ),
                ),

                SizedBox(height: metrics.gutter * 1.2),
                // Rematch, find another, or leave — one widget for all three games,
                // because the offer is the same whichever table it was.
                const RematchBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _nameOf(String playerId) {
    if (playerId.isEmpty) return 'Nobody';
    if (playerId == widget.selfId) return 'You';
    return widget.room?.seatOf(playerId)?.username ?? 'Somebody';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.seat, required this.player, required this.isSelf});

  final BarSeat seat;
  final PlatformSeat? player;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: metrics.gutter * 0.5),
      child: Row(
        children: <Widget>[
          if (player != null) ...<Widget>[
            PlayerAvatar(
              avatarId: player!.avatarId,
              colorIndex: player!.avatarColorIndex,
              size: 26 * metrics.scale,
              dimmed: !seat.alive,
            ),
            SizedBox(width: metrics.gutter * 0.5),
          ],
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    isSelf ? 'You' : (player?.username ?? 'Somebody'),
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: seat.alive ? skin.ink : skin.inkMuted,
                      fontWeight: isSelf ? FontWeight.w800 : FontWeight.w500,
                      decoration: seat.alive ? null : TextDecoration.lineThrough,
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
          if (seat.alive)
            ShotTray(remaining: seat.glassesRemaining, total: 6, compact: true)
          else
            Text(
              'out after ${seat.shotsTaken} shot${seat.shotsTaken == 1 ? '' : 's'}',
              style: text.labelSmall?.copyWith(color: skin.danger),
            ),
        ],
      ),
    );
  }
}
