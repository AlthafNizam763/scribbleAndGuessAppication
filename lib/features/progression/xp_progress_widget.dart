import 'package:flutter/material.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The level badge and XP bar.
///
/// ## Drawn in the sketchbook language, not Material's
///
/// A flat fill inside a hard ink border, like every other container in the
/// app — no elevation, no tonal surface, no gradient. The bar is a rectangle
/// inside a rectangle, which is what a hand-drawn progress bar would be.
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
    final SketchColors colors = context.sketch;
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
                    color: colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              const Spacer(),
            Text(
              level.progressLabel,
              style: text.labelSmall?.copyWith(color: colors.inkSoft),
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
  final SketchColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accentYellow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: colors.ink, width: AppSpacing.border),
      ),
      child: Text(
        '$level',
        style: TextStyle(
          color: colors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The bar itself.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.animate, required this.colors});

  final double fraction;
  final bool animate;
  final SketchColors colors;

  static const double _height = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: colors.paper,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: colors.ink, width: AppSpacing.border),
      ),
      child: ClipRRect(
        // One pixel in from the border, so the fill sits inside the ink line
        // rather than painting over it.
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm - 1),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth * fraction.clamp(0, 1);

            if (!animate) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(width: width, color: colors.accentGreen),
              );
            }

            return AnimatedContainer(
              duration: AppMotion.slow,
              curve: AppMotion.standard,
              width: width,
              color: colors.accentGreen,
            );
          },
        ),
      ),
    );
  }
}
