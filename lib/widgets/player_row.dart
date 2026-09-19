import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/game_hud.dart';
import 'package:scribble_guess/widgets/player_avatar.dart';

/// One player in a lobby or scoreboard list.
class PlayerRow extends StatelessWidget {
  const PlayerRow({
    required this.player,
    this.isSelf = false,
    this.showScore = false,
    this.rank,
    this.trailing,
    this.onTap,
    super.key,
  });

  final Player player;

  /// Marks the local player, who gets a highlighted row.
  final bool isSelf;

  /// Whether to show the running score on the right.
  final bool showScore;

  /// 1-based standing, shown ahead of the avatar when given.
  final int? rank;

  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isSelf ? colors.primaryWash : colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: isSelf ? colors.washBorder(colors.primary) : colors.border,
          width: isSelf ? AppSpacing.border : AppSpacing.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Row(
          children: <Widget>[
            if (rank != null) ...<Widget>[
              SizedBox(
                width: 26,
                child: Text(
                  '$rank',
                  style: AppTypography.numeric(colors.textFaint, size: 15),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            PlayerAvatar.ofPlayer(player, size: 38),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    player.name.isEmpty ? '...' : player.name,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: colors.text),
                  ),
                  if (_badges(context, colors).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: 4,
                        children: _badges(context, colors),
                      ),
                    ),
                ],
              ),
            ),
            if (showScore) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.wash(colors.tertiary),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                ),
                child: Text(
                  '${player.score}',
                  style: AppTypography.numeric(colors.tertiary, size: 15),
                ),
              ),
            ],
            ?trailing,
          ],
        ),
      ),
    );
  }

  List<Widget> _badges(BuildContext context, AppPalette colors) => <Widget>[
        // First, and deliberately so. A player looking at a seat needs to know
        // whether they are up against a person before they need to know
        // anything else about it, and a badge that can be pushed off the end
        // of a wrap by four others is a badge that sometimes is not there.
        if (player.isBot)
          HudBadge(
            label: player.botDifficulty == null
                ? context.l10n.tournamentAiPlayer
                : '${context.l10n.tournamentAiPlayer} · ${player.botDifficulty}',
            icon: Icons.smart_toy_outlined,
            color: colors.accentPurple,
          ),
        if (player.isDrawing)
          HudBadge(
            label: context.l10n.gameYouDraw.toUpperCase(),
            icon: Icons.brush,
            color: colors.accentBlue,
          ),
        if (player.isHost)
          HudBadge(
            label: context.l10n.lobbyHostBadge,
            icon: Icons.star,
            color: colors.accentYellow,
          ),
        if (player.isReady && !player.isDrawing)
          HudBadge(
            label: context.l10n.lobbyReadyBadge,
            icon: Icons.check,
            color: colors.success,
          ),
        if (player.hasGuessed)
          HudBadge(
            label: context.l10n.gameYouGuessedIt,
            icon: Icons.lightbulb,
            color: colors.success,
          ),
        if (player.isMuted)
          HudBadge(
            label: context.l10n.chatMuted,
            icon: Icons.volume_off,
            color: colors.warning,
          ),
        if (player.connection != PlayerConnection.connected)
          HudBadge(
            label: player.connection.label,
            icon: Icons.wifi_off,
            color: colors.danger,
          ),
      ];
}
