import 'package:flutter/material.dart';
import 'package:scribble_guess/theme/theme.dart';

/// A bordered panel on paper: the app's one container shape.
class SketchCard extends StatelessWidget {
  const SketchCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color,
    this.borderColor,
    this.onTap,
    this.selected = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  /// Thickens the border, for cards acting as a choice in a group.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final Color border = borderColor ?? (selected ? colors.ink : colors.inkFaint);

    final Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? colors.paperDim,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: border,
          width: selected ? AppSpacing.border + 1 : AppSpacing.border,
        ),
      ),
      child: child,
    );

    if (onTap == null) {
      return body;
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}

/// A titled group of related controls.
class SketchSection extends StatelessWidget {
  const SketchSection({
    required this.title,
    required this.children,
    this.trailing,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: text.labelSmall?.copyWith(color: colors.inkSoft),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        SketchCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
