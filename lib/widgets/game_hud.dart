import 'package:flutter/material.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The word under guess, shown as spaced glyphs.
///
/// The drawer sees the whole word; guessers see blanks that fill in as hints
/// land. Rendering per-character — and giving every character, blank or not,
/// the same fixed-width slot — keeps the letter positions stable as blanks are
/// replaced, so the word does not jiggle each time a hint arrives.
///
/// A blank is an underscore rule rather than a glyph, which is the difference
/// between a word with gaps in it and a word with underscores in it.
class WordMaskDisplay extends StatelessWidget {
  const WordMaskDisplay({
    required this.text,
    this.revealed = false,
    super.key,
  });

  /// Either the masked form (`_ _ a _`) or the plain word.
  final String text;

  /// Whether [text] is the real word, which is drawn at full contrast.
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final String char in text.characters)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: char == ' '
                  ? const SizedBox(width: AppSpacing.md)
                  : SizedBox(
                      width: 22,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            char == '_' ? ' ' : char.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: AppTypography.numeric(
                              revealed ? colors.primary : colors.text,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 5),
                          // The rule under every slot, lit for a letter the
                          // player has and faint for one they do not.
                          Container(
                            height: 2.5,
                            decoration: BoxDecoration(
                              color: char == '_'
                                  ? colors.borderStrong
                                  : (revealed
                                        ? colors.primary
                                        : colors.tertiary),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
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
/// mid-drawing will actually register. The number is tabular so a two-digit
/// countdown does not change width as it falls.
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
    final AppPalette colors = context.palette;

    final double fraction = totalSeconds <= 0
        ? 0
        : (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    final bool urgent = fraction <= urgentFraction;
    final Color tint = urgent ? colors.danger : colors.primary;

    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: Container(
              height: 8,
              color: colors.surfaceActive,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: AnimatedContainer(
                  duration: AppMotion.duration(context, AppMotion.normal),
                  curve: AppMotion.standard,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Semantics(
          liveRegion: urgent,
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.wash(tint),
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
            ),
            child: Text(
              '$secondsRemaining',
              style: AppTypography.numeric(tint, size: 16),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small tinted pill, for round counts, roles and states.
///
/// Washed rather than filled, so a row of three of them beside a player's name
/// reads as metadata instead of as three competing buttons.
class HudBadge extends StatelessWidget {
  const HudBadge({
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
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = color ?? colors.textMuted;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? AppSpacing.sm + 2 : AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colors.wash(tint),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: Border.all(
          color: colors.washBorder(tint),
          width: AppSpacing.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: tint),
            const SizedBox(width: 4),
          ],
          Text(label, style: text.labelSmall?.copyWith(color: tint)),
        ],
      ),
    );
  }
}
