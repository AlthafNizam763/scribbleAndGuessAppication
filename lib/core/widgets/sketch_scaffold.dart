import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/responsive.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The standard page shell: paper background, optional hand-lettered title,
/// and a content column that stops widening on tablets.
class SketchScaffold extends StatelessWidget {
  const SketchScaffold({
    required this.child,
    this.title,
    this.actions,
    this.leading,
    this.showBack = true,
    this.onBack,
    this.bottom,
    this.banner,
    this.padded = true,
    this.constrained = true,
    super.key,
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;

  /// Whether to draw the default back arrow when the route can pop.
  final bool showBack;

  /// Intercepts the back arrow, for screens that must confirm before leaving.
  final VoidCallback? onBack;

  /// Pinned below the content, outside the scroll area.
  final Widget? bottom;

  /// Pinned above the content, for connection notices.
  final Widget? banner;

  /// Whether to inset [child] by the standard page padding.
  final bool padded;

  /// Whether to cap the content width on wide screens.
  final bool constrained;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final bool canPop = Navigator.of(context).canPop();

    Widget content = child;
    if (padded) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: content,
      );
    }
    if (constrained) {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.maxContentWidth,
          ),
          child: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.paper,
      appBar: title == null && leading == null && actions == null
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: leading ??
                  (showBack && canPop
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onPressed:
                              onBack ?? () => Navigator.of(context).maybePop(),
                        )
                      : null),
              title: title == null ? null : Text(title!),
              actions: actions,
            ),
      body: SafeArea(
        top: title == null && leading == null && actions == null,
        child: Column(
          children: <Widget>[
            ?banner,
            Expanded(child: content),
            if (bottom != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padded ? AppSpacing.lg : 0,
                  AppSpacing.sm,
                  padded ? AppSpacing.lg : 0,
                  AppSpacing.lg,
                ),
                child: constrained
                    ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppSpacing.maxContentWidth,
                          ),
                          child: bottom,
                        ),
                      )
                    : bottom,
              ),
          ],
        ),
      ),
    );
  }
}

/// A centred message for empty lists and dead ends.
class SketchEmptyState extends StatelessWidget {
  const SketchEmptyState({
    required this.message,
    this.icon = Icons.edit_outlined,
    this.action,
    super.key,
  });

  /// What to say. Translated at render by the same route `notify` uses, so an
  /// English `Failure.message` handed straight to this widget is localised.
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: colors.inkFaint),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.fromEnglish(message),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.inkSoft),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Page padding that adapts to the screen size, for scroll views.
EdgeInsets pagePadding(BuildContext context) => EdgeInsets.symmetric(
      vertical: AppSpacing.lg,
      horizontal: context.isCompact ? 0 : AppSpacing.sm,
    );
