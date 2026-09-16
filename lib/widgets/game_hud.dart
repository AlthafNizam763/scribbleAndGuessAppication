import 'package:flutter/material.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The word under guess, shown as spaced glyphs.
///
/// The drawer sees the whole word; guessers see blanks that fill in as hints
/// land. Rendering per-character (rather than as one string) keeps the letter
/// positions stable as blanks are replaced, so the word does not jiggle.
class WordMaskDisplay extends StatelessWidget {
  const WordMaskDisplay({
    required this.text,
    this.revealed = false,
    super.key,
  });

  /// Either the masked form (`_ _ a _`) or the plain word.
  final String text;

  /// Whether [text] is the real word, which is drawn in full ink.
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme theme = Theme.of(context).textTheme;

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String char in text.characters)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                char,
                style: theme.headlineSmall?.copyWith(
                  color: char == '_' ? colors.inkFaint : colors.ink,
                  letterSpacing: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The turn countdown, as a draining bar with the seconds beside it.
///
/// Turns red in the last stretch, which is the only cue a player glancing up
/// mid-drawing will actually register.
class TurnTimerBar extends StatelessWidget {
  const TurnTimerBar({
    required this.secondsRemaining,
    required this.totalSeconds,
    super.key,
  });

  final int secondsRemaining;
  final int totalSeconds;

  /// The fraction of the turn left, below which the bar reads as urgent.
  static const double urgentFraction = 0.2;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    final double fraction = totalSeconds <= 0
        ? 0
        : (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    final bool urgent = fraction <= urgentFraction;
    final Color tint = urgent ? colors.danger : colors.ink;

    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: colors.paperShade,
                border: Border.all(color: colors.inkFaint, width: 1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  color: tint,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Semantics(
          liveRegion: urgent,
          child: Text(
            '$secondsRemaining',
            style: text.titleMedium?.copyWith(color: tint),
          ),
        ),
      ],
    );
  }
}

/// A small ink-on-paper pill, for round counts and role labels.
class SketchBadge extends StatelessWidget {
  const SketchBadge({
    required this.label,
    this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = color ?? colors.inkSoft;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: tint, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: text.labelSmall?.copyWith(color: tint),
          ),
        ],
      ),
    );
  }
}
