import 'package:flutter/material.dart';
import 'package:scribble_guess/core/constants/game_defaults.dart';
import 'package:scribble_guess/core/widgets/app_button.dart';
import 'package:scribble_guess/core/widgets/tap_feedback.dart';
import 'package:scribble_guess/theme/theme.dart';

/// A labelled row with a value and minus/plus buttons.
///
/// Used for every numeric room rule. The buttons disable at the ends of
/// [range] rather than clamping silently, so the limit is visible; and the
/// value sits in its own sunken well, which is what makes the row read as a
/// control rather than as a sentence with two icons after it.
class AppStepperTile extends StatelessWidget {
  const AppStepperTile({
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
    final AppPalette palette = context.palette;
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
                color: enabled ? palette.text : palette.textFaint,
                fontWeight: AppTypography.medium,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: palette.surfaceSunken,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(
                color: palette.border,
                width: AppSpacing.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _StepButton(
                  icon: Icons.remove_rounded,
                  onPressed: canDecrease
                      ? () => onChanged(range.coerce(value - step))
                      : null,
                  semanticLabel: 'Decrease $label',
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 52),
                  alignment: Alignment.center,
                  child: Text(
                    '$value$suffix',
                    style: AppTypography.numeric(
                      enabled ? palette.text : palette.textFaint,
                      size: 16,
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  onPressed: canIncrease
                      ? () => onChanged(range.coerce(value + step))
                      : null,
                  semanticLabel: 'Increase $label',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => _enabled ? setState(() => _pressed = true) : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _enabled
            ? () {
                TapFeedback.press(context);
                widget.onPressed!();
              }
            : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? AppMotion.pressScaleOf(context) : 1,
          duration: AppMotion.duration(context, AppMotion.instant),
          child: Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: _enabled ? palette.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs + 1),
              border: _enabled
                  ? Border.all(
                      color: palette.border,
                      width: AppSpacing.hairline,
                    )
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: 17,
              color: _enabled ? palette.text : palette.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled switch row, with an optional explanation under the label.
class AppToggleTile extends StatelessWidget {
  const AppToggleTile({
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
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: text.bodyLarge?.copyWith(
                    color: enabled ? palette.text : palette.textFaint,
                    fontWeight: AppTypography.medium,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
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
class AppChipGroup<T> extends StatelessWidget {
  const AppChipGroup({
    required this.options,
    required this.labelOf,
    required this.isSelected,
    required this.onToggle,
    this.toneOf,
    super.key,
  });

  final List<T> options;
  final String Function(T value) labelOf;
  final bool Function(T value) isSelected;
  final ValueChanged<T> onToggle;

  /// Gives each option its own accent when selected, for a group where the
  /// options mean different kinds of thing rather than degrees of one.
  final Color Function(T value)? toneOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final T option in options)
          AppChip(
            label: labelOf(option),
            selected: isSelected(option),
            tone: toneOf?.call(option),
            onTap: () => onToggle(option),
          ),
      ],
    );
  }
}

/// A single selectable pill.
///
/// Selected is a filled accent with white text; unselected is a sunken chip
/// with a hairline. Both are the same size, so a group does not reflow as the
/// choice moves along it.
class AppChip extends StatelessWidget {
  const AppChip({
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.tone,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// The accent worn when selected. Defaults to the primary.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = tone ?? palette.primary;
    final Color ink = selected ? palette.onFill(accent) : palette.textMuted;

    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: Semantics(
        selected: selected,
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.instant),
          curve: AppMotion.standard,
          height: AppSpacing.controlHeightSm,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
          decoration: BoxDecoration(
            color: selected ? accent : palette.surfaceSunken,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: selected ? accent : palette.border,
              width: AppSpacing.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 15, color: ink),
                const SizedBox(width: AppSpacing.xs + 2),
              ],
              Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: ink,
                  fontWeight: selected
                      ? AppTypography.bold
                      : AppTypography.semibold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal bar of progress, in the tertiary aqua by default.
///
/// Distinct from Material's indicator only in that it is a token rather than a
/// widget with five arguments at every call site: one height, one radius, one
/// track colour everywhere in the app.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    required this.value,
    this.tone,
    this.height = 8,
    this.semanticLabel,
    super.key,
  });

  /// 0..1. Values outside that range are clamped.
  final double value;

  /// Defaults to the tertiary, because progress is something earned.
  final Color? tone;

  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color accent = tone ?? palette.tertiary;

    return Semantics(
      label: semanticLabel,
      value: '${(value.clamp(0, 1) * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: SizedBox(
          height: height,
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            backgroundColor: palette.surfaceActive,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ),
    );
  }
}

/// The app's tab strip: a segmented control, not an underline.
///
/// Material's default tab bar — a row of labels with a 2pt rule sliding under
/// them — is one of the most recognisable stock-Flutter shapes there is. This
/// is a sunken track with a raised pill in it instead, which is the shape a
/// modern mobile product uses and which reads far better on a dark surface,
/// where a thin coloured underline all but disappears.
///
/// The pill itself comes from `TabBarThemeData` in [AppTheme], so a tab bar
/// built directly with [TabBar] still looks right; this widget adds the track
/// and the inset around it.
class AppSegmentedTabs extends StatelessWidget {
  const AppSegmentedTabs({
    required this.controller,
    required this.tabs,
    this.margin = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    super.key,
  });

  final TabController controller;
  final List<Widget> tabs;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: palette.border, width: AppSpacing.hairline),
      ),
      child: TabBar(
        controller: controller,
        tabs: tabs,
        splashFactory: NoSplash.splashFactory,
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
    );
  }
}
