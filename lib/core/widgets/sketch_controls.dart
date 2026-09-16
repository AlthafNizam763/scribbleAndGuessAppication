import 'package:flutter/material.dart';
import 'package:scribble_guess/core/constants/game_defaults.dart';
import 'package:scribble_guess/core/widgets/tap_feedback.dart';
import 'package:scribble_guess/theme/theme.dart';

/// A labelled row with a value and minus/plus buttons.
///
/// Used for every numeric room rule. The buttons disable at the ends of
/// [range] rather than clamping silently, so the limit is visible.
class SketchStepperTile extends StatelessWidget {
  const SketchStepperTile({
    required this.label,
    required this.value,
    required this.range,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
    this.enabled = true,
    super.key,
  });

  final String label;
  final int value;
  final IntRange range;
  final int step;

  /// Appended to the number, e.g. `s` for seconds.
  final String suffix;

  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final bool canDecrease = enabled && value - step >= range.min;
    final bool canIncrease = enabled && value + step <= range.max;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.bodyLarge?.copyWith(
                color: enabled ? colors.ink : colors.inkFaint,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.remove,
            onPressed:
                canDecrease ? () => onChanged(range.coerce(value - step)) : null,
            semanticLabel: 'Decrease $label',
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 56),
            alignment: Alignment.center,
            child: Text(
              '$value$suffix',
              style: text.titleMedium?.copyWith(
                color: enabled ? colors.ink : colors.inkFaint,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            onPressed:
                canIncrease ? () => onChanged(range.coerce(value + step)) : null,
            semanticLabel: 'Increase $label',
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final bool enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onPressed == null
            ? null
            : () {
                TapFeedback.press(context);
                onPressed!();
              },
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: enabled ? colors.ink : colors.inkFaint,
              width: AppSpacing.border,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? colors.ink : colors.inkFaint,
          ),
        ),
      ),
    );
  }
}

/// A labelled switch row.
class SketchToggleTile extends StatelessWidget {
  const SketchToggleTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
    super.key,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: text.bodyLarge?.copyWith(
                    color: enabled ? colors.ink : colors.inkFaint,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(color: colors.inkSoft),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Switch(
            value: value,
            // Sounded like a button, because it is one. Flipping the sound
            // toggle back on is also the one place a player is actively
            // listening for proof that it worked.
            onChanged: enabled
                ? (bool next) {
                    TapFeedback.press(context);
                    onChanged(next);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// A wrap of selectable pills, for enums and categories.
class SketchChipGroup<T> extends StatelessWidget {
  const SketchChipGroup({
    required this.options,
    required this.labelOf,
    required this.isSelected,
    required this.onToggle,
    super.key,
  });

  final List<T> options;
  final String Function(T value) labelOf;
  final bool Function(T value) isSelected;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final T option in options)
          SketchChip(
            label: labelOf(option),
            selected: isSelected(option),
            onTap: () => onToggle(option),
          ),
      ],
    );
  }
}

/// A single selectable pill.
class SketchChip extends StatelessWidget {
  const SketchChip({
    required this.label,
    required this.selected,
    this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                TapFeedback.press(context);
                onTap!();
              },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: selected ? colors.ink : colors.inkFaint,
              width: AppSpacing.border,
            ),
          ),
          child: Text(
            label,
            style: text.labelMedium?.copyWith(
              color: selected ? colors.paper : colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
