import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/app_card.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/player_avatar.dart';

/// The pieces the leaderboard, friends and profile screens share.
///
/// All of them are drawn from the one vocabulary — the surface step, the
/// hairline, the accent palette — and none introduces a new one. A leaderboard
/// row is an [AppCard] with a rank in front of it, not a new kind of surface,
/// which is what keeps three screens from looking like a different app bolted
/// on.

/// A player's name, avatar and an optional line of detail.
///
/// The row shape every list here uses, so a friend, a search result and a
/// blocked player are recognisably the same object in three places.
class PlayerTile extends StatelessWidget {
  /// Creates a player tile.
  const PlayerTile({
    required this.card,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.highlight = false,
    this.avatarSize = 40,
    super.key,
  });

  /// Who this row is.
  final UserCard card;

  /// A line under the name: a score, a locality, when they were added.
  final String? subtitle;

  /// Buttons or a score, pinned to the right.
  final Widget? trailing;

  /// Drawn before the avatar. The leaderboard puts its rank numeral here.
  final Widget? leading;

  /// Opens the player's profile, when there is one to open.
  final VoidCallback? onTap;

  /// Draws the row as the local player's.
  final bool highlight;

  /// Diameter of the avatar.
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      button: onTap != null,
      label: subtitle == null ? card.name : '${card.name}, $subtitle',
      child: AppCard(
        onTap: onTap,
        selected: highlight,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            ?leading,
            PlayerAvatar(
              avatarId: card.avatarId,
              colorIndex: card.avatarColorIndex,
              size: avatarSize,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    card.name.isEmpty ? '...' : card.name,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: colors.text),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The rank numeral in front of a leaderboard row.
///
/// The top three get a washed disc in an accent and, for first, a trophy;
/// everybody else gets a quiet numeral. Deliberately restrained — a cup on
/// first place is a wink, a podium rendered in gradients would be a different
/// app.
class RankBadge extends StatelessWidget {
  /// Creates a rank badge.
  const RankBadge({required this.rank, super.key});

  /// The 1-based rank.
  final int rank;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    final Color tone = switch (rank) {
      1 => colors.accentYellow,
      2 => colors.textMuted,
      3 => colors.accentOrange,
      _ => colors.textFaint,
    };

    final bool podium = rank >= 1 && rank <= 3;

    return Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: podium ? colors.wash(tone) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: podium
            ? Border.all(
                color: colors.washBorder(tone),
                width: AppSpacing.hairline,
              )
            : null,
      ),
      child: rank == 1
          ? Icon(Icons.emoji_events_rounded, size: 18, color: tone)
          : Text(
              // A rank the server could not compute shows a dash, not a zero.
              rank > 0 ? '$rank' : '—',
              style: AppTypography.numeric(tone, size: 15),
            ),
    );
  }
}

/// A small arrow showing how far a player moved since the last ranking.
///
/// Renders nothing at all when there is no history to compare against, which
/// is currently always: the backend records no ranking snapshots, and an arrow
/// drawn from no history would be a claim the server never made.
class RankChange extends StatelessWidget {
  /// Creates a rank-change indicator.
  const RankChange({required this.change, super.key});

  /// Places gained, or null when unknown.
  final int? change;

  @override
  Widget build(BuildContext context) {
    final int? delta = change;
    if (delta == null || delta == 0) return const SizedBox.shrink();

    final AppPalette colors = context.palette;
    final bool up = delta > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 18,
          color: up ? colors.success : colors.danger,
        ),
        Text(
          '${delta.abs()}',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: up ? colors.success : colors.danger),
        ),
      ],
    );
  }
}

/// A labelled number, used under a leaderboard row and on a profile.
class StatCell extends StatelessWidget {
  /// Creates a stat cell.
  const StatCell({required this.label, required this.value, super.key});

  /// What the number is.
  final String label;

  /// The number, already formatted.
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(value, style: AppTypography.numeric(colors.text, size: 17)),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            style: text.labelSmall?.copyWith(color: colors.textFaint),
          ),
        ],
      ),
    );
  }
}

/// The four-across stats strip shown under a leaderboard row.
class StatsStrip extends StatelessWidget {
  /// Creates a stats strip.
  const StatsStrip({required this.stats, super.key});

  /// The record to show.
  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return Column(
      children: <Widget>[
        const SizedBox(height: AppSpacing.sm),
        Divider(color: colors.border, height: 1),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            StatCell(
              label: context.l10n.leaderboardGames,
              value: '${stats.gamesPlayed}',
            ),
            StatCell(
              label: context.l10n.leaderboardWins,
              value: '${stats.gamesWon}',
            ),
            StatCell(
              label: context.l10n.leaderboardWinRate,
              value: stats.winRateLabel,
            ),
            StatCell(
              label: context.l10n.leaderboardBestRound,
              value: '${stats.bestRoundScore}',
            ),
          ],
        ),
      ],
    );
  }
}

/// A count worn on a button, for pending friend requests.
///
/// Draws nothing when the count is zero: a badge showing "0" is noise that
/// looks like a bug.
class CountBadge extends StatelessWidget {
  /// Wraps [child] with a badge showing [count].
  const CountBadge({required this.count, required this.child, super.key});

  /// How many. Zero draws nothing.
  final int count;

  /// What the badge sits on.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;

    final AppPalette colors = context.palette;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        Positioned(
          top: -4,
          right: -4,
          child: Semantics(
            label: '$count waiting',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                // Ringed in the page colour rather than the card's, so the
                // badge reads as sitting on top of whatever it is pinned to.
                border: Border.all(
                  color: colors.bg,
                  width: AppSpacing.borderThick,
                ),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
