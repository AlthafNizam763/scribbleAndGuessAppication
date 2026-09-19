import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/features/games/common/bot_chip.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/rematch_bar.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/sound_provider.dart';
import 'package:scribble_guess/services/sound_service.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The reveal: who was what, and why it ended.
///
/// ## Roles appear here and nowhere earlier
///
/// This is the first moment the server sends anybody else's role, and it is
/// the point of the whole match — the thing every player has been trying to
/// work out. It is read from the server's own result document rather than
/// from anything the client accumulated, because the client was never told.
class SpaceMysteryResultOverlay extends ConsumerStatefulWidget {
  const SpaceMysteryResultOverlay({
    required this.state,
    required this.room,
    required this.selfId,
    super.key,
  });

  final SpaceMysteryState state;
  final PlatformRoom? room;
  final String selfId;

  @override
  ConsumerState<SpaceMysteryResultOverlay> createState() =>
      _SpaceMysteryResultOverlayState();
}

class _SpaceMysteryResultOverlayState
    extends ConsumerState<SpaceMysteryResultOverlay> {
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

    final Map<String, dynamic> result = widget.state.result ?? <String, dynamic>{};
    final bool traitorsWon = asString(result['winnerTeam']) == 'traitors';
    final List<String> winners = asStringList(result['winnerIds']);
    final bool iWon = winners.contains(widget.selfId);

    final Map<String, dynamic> roles = asMap(result['roles']);

    final String reason = switch (asString(result['reason'])) {
      'traitors_ejected' => 'Every traitor was thrown out of an airlock.',
      'station_repaired' => 'The crew finished the repairs.',
      'traitors_outnumber_crew' => 'The traitors took the ship.',
      'reactor_breach' => 'The reactor went unattended.',
      _ => 'The match is over.',
    };

    return Positioned.fill(
      child: ColoredBox(
        color: skin.backdrop.last.withValues(alpha: 0.96),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(metrics.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    traitorsWon
                        ? Icons.visibility_off_rounded
                        : Icons.rocket_launch_rounded,
                    size: 40 * metrics.scale,
                    color: traitorsWon ? skin.danger : skin.success,
                  ),
                  SizedBox(height: metrics.gutter * 0.5),
                  Text(
                    traitorsWon ? 'Traitors win' : 'Crew wins',
                    style: text.headlineSmall?.copyWith(
                      color: traitorsWon ? skin.danger : skin.success,
                      fontFamily: skin.display,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: metrics.gutter * 0.2),
                  Text(reason, style: text.bodySmall?.copyWith(color: skin.inkMuted)),
                  SizedBox(height: metrics.gutter * 0.3),
                  Text(
                    iWon ? 'You were on the winning side.' : 'You lost this one.',
                    style: text.labelLarge?.copyWith(
                      color: iWon ? skin.accent : skin.inkMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  SizedBox(height: metrics.gutter * 1.2),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: EdgeInsets.all(metrics.gutter),
                    decoration: BoxDecoration(
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      border: Border.all(color: skin.edge),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'WHO WAS WHO',
                          style: text.labelSmall?.copyWith(
                            color: skin.inkMuted,
                            fontFamily: skin.display,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        SizedBox(height: metrics.gutter * 0.6),
                        Wrap(
                          spacing: metrics.gutter * 0.5,
                          runSpacing: metrics.gutter * 0.5,
                          children: <Widget>[
                            for (final MapEntry<String, dynamic> entry in roles.entries)
                              _RoleCard(
                                player: widget.room?.seatOf(entry.key),
                                isTraitor: asString(entry.value) == 'traitor',
                                isSelf: entry.key == widget.selfId,
                              ),
                          ],
                        ),
                        SizedBox(height: metrics.gutter * 0.8),
                        Text(
                          'Repairs finished: ${asInt(result['tasksCompleted'])}'
                          ' of ${asInt(result['tasksTotal'])}',
                          style: text.bodySmall?.copyWith(color: skin.inkMuted),
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
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.player,
    required this.isTraitor,
    required this.isSelf,
  });

  final PlatformSeat? player;
  final bool isTraitor;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tone = isTraitor ? skin.danger : skin.accent;

    return Container(
      width: 130 * metrics.scale,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gutter * 0.5,
        vertical: metrics.gutter * 0.4,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: tone.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: <Widget>[
          if (player != null)
            PlayerAvatar(
              avatarId: player!.avatarId,
              colorIndex: player!.avatarColorIndex,
              size: 24 * metrics.scale,
            ),
          SizedBox(width: metrics.gutter * 0.4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  isSelf ? 'You' : (player?.username ?? 'Somebody'),
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: <Widget>[
                    Text(
                      isTraitor ? 'Traitor' : 'Crew',
                      style: text.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (player?.isBot ?? false) ...<Widget>[
                      SizedBox(width: metrics.gutter * 0.25),
                      BotChip(difficulty: player!.botDifficulty),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
