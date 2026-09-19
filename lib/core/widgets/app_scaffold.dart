import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/responsive.dart';
import 'package:scribble_guess/core/widgets/app_button.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The standard page shell: the page background, a left-aligned title, and a
/// content column that stops widening on tablets.
///
/// The title is left-aligned rather than centred, and set in the display face,
/// because a centred Material title with a back arrow beside it is the single
/// most recognisable "this is a default Flutter app" tell there is.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.showBack = true,
    this.onBack,
    this.bottom,
    this.banner,
    this.padded = true,
    this.constrained = true,
    this.floatingBottom = true,
    super.key,
  });

  final Widget child;
  final String? title;

  /// A quiet line under the title, for context the title cannot carry.
  final String? subtitle;

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

  /// Whether [bottom] sits on its own surface with a hairline above it.
  ///
  /// On by default: a primary action pinned to the bottom of a scrolling list
  /// needs to be visibly separate from the last row, or it reads as part of it.
  final bool floatingBottom;

  bool get _hasBar => title != null || leading != null || actions != null;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
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
      backgroundColor: palette.bg,
      appBar: !_hasBar
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leadingWidth: showBack && canPop && leading == null
                  ? AppSpacing.lg + 44 + AppSpacing.xs
                  : null,
              leading: leading ??
                  (showBack && canPop
                      ? Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.lg),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: AppIconButton(
                              icon: Icons.arrow_back_rounded,
                              tooltip: MaterialLocalizations.of(context)
                                  .backButtonTooltip,
                              onPressed: onBack ??
                                  () => Navigator.of(context).maybePop(),
                            ),
                          ),
                        )
                      : null),
              title: title == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                      ],
                    ),
              actions: actions == null
                  ? null
                  : <Widget>[
                      ...actions!,
                      const SizedBox(width: AppSpacing.lg),
                    ],
            ),
      body: SafeArea(
        top: !_hasBar,
        child: Column(
          children: <Widget>[
            ?banner,
            Expanded(child: content),
            if (bottom != null)
              _BottomBar(
                padded: padded,
                constrained: constrained,
                floating: floatingBottom,
                child: bottom!,
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.child,
    required this.padded,
    required this.constrained,
    required this.floating,
  });

  final Widget child;
  final bool padded;
  final bool constrained;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    Widget body = Padding(
      padding: EdgeInsets.fromLTRB(
        padded ? AppSpacing.lg : 0,
        AppSpacing.md,
        padded ? AppSpacing.lg : 0,
        AppSpacing.lg,
      ),
      child: constrained
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.maxContentWidth,
                ),
                child: child,
              ),
            )
          : child,
    );

    if (floating) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          color: palette.bg,
          border: Border(
            top: BorderSide(
              color: palette.border,
              width: AppSpacing.hairline,
            ),
          ),
        ),
        child: body,
      );
    }
    return body;
  }
}

/// A centred message for empty lists and dead ends.
///
/// The glyph sits in a washed circle rather than floating grey on the page:
/// an empty state is still a designed screen, and a lone 44pt icon in the
/// middle of nothing is the look of a screen nobody got to.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.message,
    this.title,
    this.icon = Icons.inbox_rounded,
    this.tone,
    this.action,
    super.key,
  });

  /// What to say. Translated at render by the same route `notify` uses, so an
  /// English `Failure.message` handed straight to this widget is localised.
  final String message;

  /// An optional heading above [message], for a state worth naming.
  final String? title;

  final IconData icon;

  /// Tints the glyph. Defaults to the primary.
  final Color? tone;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = tone ?? palette.primary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 68,
              width: 68,
              decoration: BoxDecoration(
                color: palette.wash(accent),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Icon(icon, size: 30, color: accent),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (title != null) ...<Widget>[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(color: palette.text),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(
              context.l10n.fromEnglish(message),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: palette.textMuted),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The app's loading state: a spinner with something to read under it.
///
/// A bare spinner on a blank page tells a player nothing about whether the app
/// is working or stuck, which is the whole reason the line exists.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
            ),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.l10n.fromEnglish(message!),
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The app's error state: what went wrong, and the way to try again.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.message,
    this.onRetry,
    this.retryLabel,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.cloud_off_rounded,
      tone: context.palette.danger,
      title: 'Something broke',
      message: message,
      action: onRetry == null
          ? null
          : AppButton(
              label: retryLabel ?? context.l10n.retry,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
    );
  }
}

/// An inert placeholder block, sized like the row it stands in for.
///
/// Placeholders rather than a spinner wherever a list is about to arrive: a
/// spinner collapses the layout to nothing and then shoves everything back
/// down a moment later, which is far more distracting than a still grey box.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    required this.height,
    this.width,
    this.radius = AppSpacing.radiusLg,
    this.semanticLabel,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget box = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: context.palette.surfaceSunken,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return semanticLabel == null
        ? box
        : Semantics(label: semanticLabel, child: box);
  }
}

/// Page padding that adapts to the screen size, for scroll views.
EdgeInsets pagePadding(BuildContext context) => EdgeInsets.symmetric(
  vertical: AppSpacing.lg,
  horizontal: context.isCompact ? 0 : AppSpacing.sm,
);
