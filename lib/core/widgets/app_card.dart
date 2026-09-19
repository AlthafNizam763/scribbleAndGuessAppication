import 'package:flutter/material.dart';
import 'package:scribble_guess/core/widgets/app_button.dart';
import 'package:scribble_guess/theme/theme.dart';

/// A panel: the app's one container shape.
///
/// A card is a surface step plus a hairline — never a shadow stack, never a
/// gradient, never a blur. On the light theme the surface is white on an
/// off-white page; on the dark theme it is one notch above near-black. Both
/// read as "raised" without anything being thrown underneath it, which is why
/// a screen full of these stays calm instead of looking quilted.
///
/// Give it [onTap] and it becomes pressable, with the same shrink every
/// button uses.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color,
    this.borderColor,
    this.onTap,
    this.selected = false,
    this.radius = AppSpacing.radiusLg,
    this.tone,
    this.elevated = false,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Overrides the fill. Defaults to the palette surface.
  final Color? color;

  /// Overrides the hairline.
  final Color? borderColor;

  final VoidCallback? onTap;

  /// Draws the card in its [tone], for a card acting as a choice in a group.
  final bool selected;

  final double radius;

  /// The accent a [selected] card is drawn in. Defaults to the primary.
  final Color? tone;

  /// Casts the one soft shadow the system allows. For a card that floats over
  /// content rather than sitting in a list.
  final bool elevated;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color accent = tone ?? palette.primary;

    final Color fill =
        color ?? (selected ? palette.wash(accent) : palette.surface);
    final Color edge = borderColor ??
        (selected ? palette.washBorder(accent) : palette.border);

    final Widget body = AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.instant),
      curve: AppMotion.standard,
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: edge,
          width: selected ? AppSpacing.border : AppSpacing.hairline,
        ),
        boxShadow: elevated
            ? AppElevation.lifted(palette.shadow)
            : AppElevation.none,
      ),
      child: child,
    );

    if (onTap == null) {
      return semanticLabel == null
          ? body
          : Semantics(container: true, label: semanticLabel, child: body);
    }
    return PressableScale(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: body,
    );
  }
}

/// A titled group of related rows, the shape every settings-like screen is
/// built from.
///
/// The title is an eyebrow — small, heavy, tracked wide and outside the card —
/// so the card itself stays a clean stack of rows rather than carrying a
/// heading that competes with them.
class AppSection extends StatelessWidget {
  const AppSection({
    required this.title,
    required this.children,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    super.key,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: text.labelSmall?.copyWith(color: palette.textFaint),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        AppCard(padding: padding, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        )),
      ],
    );
  }
}

/// A heading for a stretch of a screen: a bold title over a muted line.
///
/// The type pairing does the work here — Space Grotesk tight and heavy on the
/// title, Plus Jakarta Sans small and quiet underneath — which is what makes a
/// scrolling page read as chapters rather than as a list of lists.
class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: text.headlineSmall?.copyWith(color: palette.text),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(color: palette.textMuted),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A small tinted pill: a status, a count, a category.
///
/// The one place a colour other than the primary is allowed to fill something,
/// because that is exactly its job — to say *which kind* at a glance. It
/// tints itself from [tone] rather than taking a fill and a foreground, so a
/// game colour arriving from the server still produces a legible badge.
class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.label,
    this.tone,
    this.icon,
    this.solid = false,
    super.key,
  });

  final String label;

  /// Defaults to the primary.
  final Color? tone;
  final IconData? icon;

  /// Fills with [tone] instead of washing it. For a badge that has to win.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = tone ?? palette.primary;
    final Color ink = solid ? palette.onFill(accent) : accent;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? AppSpacing.sm + 2 : AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: solid ? accent : palette.wash(accent),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: solid
            ? null
            : Border.all(
                color: palette.washBorder(accent),
                width: AppSpacing.hairline,
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: ink),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: text.labelSmall?.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

/// A row of one label against one value, the atom of every stats block.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Tints the glyph and the number. Defaults to the primary.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = tone ?? palette.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.numeric(palette.text, size: 22),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelSmall?.copyWith(color: palette.textFaint),
        ),
      ],
    );
  }
}
