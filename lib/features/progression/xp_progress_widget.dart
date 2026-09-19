import 'package:flutter/material.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The level badge and XP bar.
///
/// ## Drawn in the design system, not Material's
///
/// A capsule of the tertiary aqua in a sunken track, and a level badge washed
/// in the same colour — no elevation, no tonal surface, no gradient. Aqua
/// because that is the colour the system reserves for anything earned.
///
/// The number beside it is always the server's: this widget renders a
/// [PlayerLevel] and computes nothing, which is what keeps it agreeing with
/// the level the leaderboard sorts by.
class XpProgressWidget extends StatelessWidget {
  /// Creates an XP bar.
  const XpProgressWidget({
    required this.level,
    this.compact = false,
    this.animate = true,
    super.key,
  });

  /// Where the player stands.
  final PlayerLevel level;

  /// Drops the title line, for tight places like a profile card.
  final bool compact;

  /// Whether the bar eases to its value. Off inside lists, where a rebuild
  /// per scroll frame would restart the animation on every row.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _LevelBadge(level: level.level, colors: colors),
            const SizedBox(width: AppSpacing.sm),
            if (!compact)
              Expanded(
                child: Text(
                  level.title,
                  style: text.titleSmall?.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              const Spacer(),
            Text(
              level.progressLabel,
              style: text.labelSmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _Bar(fraction: level.progress, animate: animate, colors: colors),
      ],
    );
  }
}

/// The square carrying the level number.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.colors});

  final int level;
  final AppPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.wash(colors.tertiary),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: Border.all(
          color: colors.washBorder(colors.tertiary),
          width: AppSpacing.hairline,
        ),
      ),
      child: Text(
        '$level',
        style: AppTypography.numeric(colors.tertiary, size: 13),
      ),
    );
  }
}

/// The bar itself.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.animate, required this.colors});

  final double fraction;
  final bool animate;
  final AppPalette colors;

  static const double _height = 10;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: colors.surfaceActive,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth * fraction.clamp(0, 1);

            if (!animate) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(width: width, color: colors.tertiary),
              );
            }

            return AnimatedContainer(
              duration: AppMotion.slow,
              curve: AppMotion.standard,
              width: width,
              color: colors.tertiary,
            );
          },
        ),
      ),
    );
  }
}
