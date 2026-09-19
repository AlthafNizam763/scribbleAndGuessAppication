import 'package:flutter/material.dart';
import 'package:scribble_guess/core/widgets/app_card.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/theme/theme.dart';

/// One achievement, locked or unlocked.
///
/// ## What distinguishes the two states
///
/// An unlocked card is washed in the trophy gold and carries a filled medal; a
/// locked one is a plain card with a dimmed outline medal. No shadow and no
/// lock overlay — the same restraint the unread notification row uses, and for
/// the same reason: the system has one wash and one keyline to spend, and
/// spending more would make a list of twelve cards shout.
///
/// A locked card still shows its reward, because the screen is a list of
/// things to aim at rather than only a trophy case.
class AchievementCard extends StatelessWidget {
  /// Creates a card.
  const AchievementCard({required this.achievement, super.key});

  /// The entry to draw.
  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final bool unlocked = achievement.unlocked;

    return AppCard(
      selected: unlocked,
      tone: colors.accentYellow,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Medal(unlocked: unlocked, colors: colors),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        achievement.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          color: unlocked ? colors.text : colors.textMuted,
                          fontWeight: unlocked ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '+${achievement.xpReward} XP',
                      style: text.labelSmall?.copyWith(
                        color: unlocked ? colors.accentGreen : colors.textFaint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  achievement.description,
                  style: text.bodySmall?.copyWith(color: colors.textMuted),
                ),

                // The bar is drawn only where it says something. "1 of 1" is
                // not progress, it is a yes-or-no the medal already answers.
                if (achievement.showProgress && !unlocked) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  _ProgressRow(achievement: achievement, colors: colors, text: text),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The medal square on the left of a card.
class _Medal extends StatelessWidget {
  const _Medal({required this.unlocked, required this.colors});

  final bool unlocked;
  final AppPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: unlocked ? colors.wash(colors.accentYellow) : colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
          color: unlocked
              ? colors.washBorder(colors.accentYellow)
              : colors.border,
          width: AppSpacing.hairline,
        ),
      ),
      child: Icon(
        unlocked ? Icons.workspace_premium : Icons.workspace_premium_outlined,
        size: 22,
        color: unlocked ? colors.accentYellow : colors.textFaint,
      ),
    );
  }
}

/// The counter line and bar under a locked, countable achievement.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.achievement,
    required this.colors,
    required this.text,
  });

  final Achievement achievement;
  final AppPalette colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: colors.surfaceActive,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: constraints.maxWidth * achievement.fraction,
                  color: colors.tertiary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          achievement.progressLabel,
          style: text.labelSmall?.copyWith(color: colors.textFaint),
        ),
      ],
    );
  }
}
