import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/app_card.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/player_score.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/player_avatar.dart';

/// The finished match, drawn as a card worth sharing.
///
/// ## Why this is a widget and not an image the server builds
///
/// It is rasterised in-process by the same `RenderRepaintBoundary` path the
/// replay share uses, so the picture somebody shares is literally the screen
/// they were looking at. A server-rendered card would need its own renderer,
/// its own fonts and its own copy of the design system — three things
/// that would drift from the app the moment either changed.
///
/// ## What it deliberately does not carry
///
/// No player ids, no room code beyond the one the players already saw, and
/// nothing about anybody's account. A shared card travels further than the
/// room it came from, so it carries names and scores and stops there.
class GameResultShareCard extends StatelessWidget {
  /// Creates a result card.
  const GameResultShareCard({
    required this.result,
    this.xpEarned = 0,
    super.key,
  });

  /// The finished match.
  final GameResult result;

  /// XP the local player earned, or zero when there was none.
  ///
  /// Only ever the *local* player's: a card showing everybody's XP would be
  /// publishing progression a viewer has no business seeing.
  final int xpEarned;

  /// Looks up a player in the standings by id.
  PlayerScore? _find(String? playerId) {
    if (playerId == null) return null;
    for (final PlayerScore score in result.standings) {
      if (score.playerId == playerId) return score;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final PlayerScore? winner = result.winner;

    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.appName,
            style: text.labelSmall?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            winner == null ? context.l10n.resultsFinalTitle : '${winner.name} wins!',
            style: text.headlineSmall?.copyWith(color: colors.text),
          ),
          Text(
            context.l10n.resultSubtitle(result.gameMode.label, result.totalRounds),
            style: text.bodySmall?.copyWith(color: colors.textMuted),
          ),

          const SizedBox(height: AppSpacing.lg),

          // The standings, capped. A card is a picture, and a twelve-player
          // match rendered in full would be unreadable at the size anybody
          // actually views it — so the podium is shown and the rest counted.
          for (final PlayerScore score in result.standings.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _StandingRow(score: score, colors: colors, text: text),
            ),

          if (result.standings.length > 5)
            Text(
              '+${result.standings.length - 5} more',
              style: text.labelSmall?.copyWith(color: colors.textFaint),
            ),

          if (!result.awards.isEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.resultAwards.toUpperCase(),
              style: text.labelSmall?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Award(
              label: context.l10n.resultTopScorer,
              player: _find(result.awards.topScorerId),
              colors: colors,
              text: text,
            ),
            _Award(
              label: context.l10n.resultBestDrawer,
              player: _find(result.awards.bestDrawerId),
              colors: colors,
              text: text,
            ),
            _Award(
              label: context.l10n.resultBestGuesser,
              player: _find(result.awards.bestGuesserId),
              colors: colors,
              text: text,
            ),
            _Award(
              label: context.l10n.resultFastestGuesser,
              player: _find(result.awards.fastestGuesserId),
              colors: colors,
              text: text,
            ),
          ],

          if (xpEarned > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.progressionXpEarned(xpEarned),
              style: text.titleSmall?.copyWith(
                color: colors.accentGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of the standings on the card.
class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.score,
    required this.colors,
    required this.text,
  });

  final PlayerScore score;
  final AppPalette colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 22,
          child: Text(
            '${score.rank}',
            style: text.labelMedium?.copyWith(
              color: colors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        PlayerAvatar(
          avatarId: score.avatarId,
          colorIndex: score.avatarColorIndex,
          size: 26,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            score.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(color: colors.text),
          ),
        ),
        Text(
          '${score.score}',
          style: text.bodyMedium?.copyWith(
            color: colors.text,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// One highlight. Renders nothing when nobody qualified.
class _Award extends StatelessWidget {
  const _Award({
    required this.label,
    required this.player,
    required this.colors,
    required this.text,
  });

  final String label;
  final PlayerScore? player;
  final AppPalette colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    // A match where nobody drew has no best drawer, and a dash would be worse
    // than an absence — so the row simply is not there.
    if (player == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: text.labelSmall?.copyWith(color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              player!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
