import 'package:flutter/material.dart';
import 'package:scribble_guess/core/widgets/tap_feedback.dart';
import 'package:scribble_guess/theme/theme.dart';

/// How much visual weight an [AppButton] carries.
enum AppButtonVariant {
  /// Filled with the primary violet and lit with its own glow. One per screen,
  /// for the thing the player came to do.
  primary,

  /// A filled surface chip with a hairline. The default for everything else,
  /// and the one that sits next to a primary without fighting it.
  secondary,

  /// A keyline on nothing. For a second choice inside a coloured region, or
  /// anywhere a filled chip would read as a card.
  outline,

  /// Borderless. Tertiary actions — Cancel, Skip, Not now — that should be
  /// reachable without competing.
  ghost,

  /// Filled red. Reserved for the irreversible: leave, kick, delete.
  danger,
}

/// How tall an [AppButton] is.
enum AppButtonSize {
  /// 52pt. Screen actions, form submits, the bottom of a sheet.
  regular,

  /// 40pt. Inline actions inside a dense row — Join, Add, Retry.
  compact,
}

/// The button of STUPID GAMES.
///
/// There is no `ElevatedButton` theme in this app, because Material's
/// elevation, ripple and pill-by-default fight the design: a ripple lands a
/// frame after the finger and reads as a second reaction to one tap. This
/// presses instead — the whole control shrinks to [AppMotion.pressScale] and
/// its fill deepens — which is immediate, physical, and the same gesture the
/// cards and chips use, so the entire app answers a touch the same way.
///
/// Every variant keeps the same height, radius and label weight; only the fill
/// changes. That is what lets a row of mixed buttons look composed rather than
/// assembled.
class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.secondary,
    this.size = AppButtonSize.regular,
    this.expand = false,
    this.busy = false,
    this.tone,
    super.key,
  });

  /// A full-width primary button, the common shape for a screen's main action.
  const AppButton.primary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = AppButtonSize.regular,
    this.expand = true,
    this.busy = false,
    this.tone,
    super.key,
  }) : variant = AppButtonVariant.primary;

  final String label;
  final IconData? icon;

  /// `null` disables the button.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool expand;

  /// Swaps the label for a spinner and blocks input.
  final bool busy;

  /// Overrides the accent a [AppButtonVariant.primary] or
  /// [AppButtonVariant.outline] button is drawn in.
  ///
  /// For the one case where a button belongs to something that already has a
  /// colour — a game's own Play button — rather than to the app. Everywhere
  /// else, leave it null and let the button be violet.
  final Color? tone;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  /// Sounds the press, then runs the callback.
  ///
  /// In this order so the click lands with the finger rather than after
  /// whatever the button went on to do — a press that navigates would
  /// otherwise click from the next screen.
  void _press() {
    TapFeedback.press(context);
    widget.onPressed?.call();
  }

  void _setPressed(bool value) {
    if (_pressed == value || !_enabled) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = widget.tone ?? palette.primary;

    final bool compact = widget.size == AppButtonSize.compact;
    final double height = compact
        ? AppSpacing.controlHeightSm
        : AppSpacing.controlHeight;
    final double radius = compact
        ? AppSpacing.radiusSm
        : AppSpacing.radiusMd;
    final double gap = compact ? AppSpacing.xs + 2 : AppSpacing.sm;
    final double iconSize = compact ? 17 : 19;

    final _ButtonSkin skin = _skinFor(palette, accent);

    // Disabled buttons keep their shape and lose their contrast, so a form
    // never reflows as it becomes valid.
    final Color face = _enabled
        ? (_pressed ? skin.facePressed : skin.face)
        : skin.faceDisabled;
    final Color edge = _enabled ? skin.edge : palette.border;
    final Color ink = _enabled ? skin.ink : palette.textFaint;

    final Widget content = widget.busy
        ? SizedBox(
            height: iconSize,
            width: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(ink),
            ),
          )
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                Icon(widget.icon, size: iconSize, color: ink),
                SizedBox(width: gap),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: (compact ? text.labelMedium : text.labelLarge)
                      ?.copyWith(color: ink, fontWeight: AppTypography.bold),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: _enabled ? _press : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? AppMotion.pressScaleOf(context) : 1,
          duration: AppMotion.duration(context, AppMotion.instant),
          curve: AppMotion.standard,
          child: AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.instant),
            curve: AppMotion.standard,
            width: widget.expand ? double.infinity : null,
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.md + 2 : AppSpacing.xl,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: face,
              borderRadius: BorderRadius.circular(radius),
              border: edge == Colors.transparent
                  ? null
                  : Border.all(color: edge, width: AppSpacing.hairline),
              // Only the primary glows, only while it is at rest, and only
              // when it can actually be pressed. A glow on a disabled control
              // is a promise the control cannot keep.
              boxShadow: skin.glows && _enabled && !_pressed
                  ? AppElevation.glow(accent)
                  : AppElevation.none,
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  _ButtonSkin _skinFor(AppPalette palette, Color accent) {
    switch (widget.variant) {
      case AppButtonVariant.primary:
        return _ButtonSkin(
          face: accent,
          facePressed: Color.lerp(accent, palette.shadow, 0.18)!,
          faceDisabled: palette.surfaceActive,
          edge: Colors.transparent,
          ink: palette.onFill(accent),
          glows: true,
        );
      case AppButtonVariant.secondary:
        return _ButtonSkin(
          face: palette.surface,
          facePressed: palette.surfaceActive,
          faceDisabled: palette.surfaceSunken,
          edge: palette.border,
          ink: palette.text,
          glows: false,
        );
      case AppButtonVariant.outline:
        return _ButtonSkin(
          face: Colors.transparent,
          facePressed: palette.wash(accent),
          faceDisabled: Colors.transparent,
          edge: palette.washBorder(accent),
          ink: accent,
          glows: false,
        );
      case AppButtonVariant.ghost:
        return _ButtonSkin(
          face: Colors.transparent,
          facePressed: palette.surfaceActive,
          faceDisabled: Colors.transparent,
          edge: Colors.transparent,
          ink: palette.textMuted,
          glows: false,
        );
      case AppButtonVariant.danger:
        return _ButtonSkin(
          face: palette.danger,
          facePressed: Color.lerp(palette.danger, palette.shadow, 0.18)!,
          faceDisabled: palette.surfaceActive,
          edge: Colors.transparent,
          ink: Colors.white,
          glows: false,
        );
    }
  }
}

/// The resolved colours of one button state.
@immutable
class _ButtonSkin {
  const _ButtonSkin({
    required this.face,
    required this.facePressed,
    required this.faceDisabled,
    required this.edge,
    required this.ink,
    required this.glows,
  });

  final Color face;
  final Color facePressed;
  final Color faceDisabled;
  final Color edge;
  final Color ink;
  final bool glows;
}

/// A square icon button with the same press as [AppButton].
///
/// Used for app-bar actions, toolbar tools and anywhere a label would not fit.
/// It is a real surface rather than a bare glyph, because a bare glyph on a
/// dark page is very hard to aim at and gives nothing back when hit.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.selected = false,
    this.tone,
    this.filled = false,
    this.size = 44,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Also used as the semantic label, so every icon button is reachable by
  /// name whether or not the tooltip is ever shown.
  final String tooltip;

  /// Draws the button in its accent, for a tool that is currently active.
  final bool selected;

  /// The accent used when [selected] or [filled]. Defaults to the primary.
  final Color? tone;

  /// Fills the button with [tone] permanently, for a single strong action.
  final bool filled;

  final double size;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed == value || !_enabled) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color accent = widget.tone ?? palette.primary;

    final (Color face, Color edge, Color ink) = switch ((
      widget.filled,
      widget.selected,
      _enabled,
    )) {
      (_, _, false) => (
        palette.surfaceSunken,
        palette.border,
        palette.textFaint,
      ),
      (true, _, _) => (accent, Colors.transparent, palette.onFill(accent)),
      (false, true, _) => (
        palette.wash(accent),
        palette.washBorder(accent),
        accent,
      ),
      (false, false, _) => (
        _pressed ? palette.surfaceActive : palette.surface,
        palette.border,
        palette.text,
      ),
    };

    return Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
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
            curve: AppMotion.standard,
            child: AnimatedContainer(
              duration: AppMotion.duration(context, AppMotion.instant),
              curve: AppMotion.standard,
              height: widget.size,
              width: widget.size,
              decoration: BoxDecoration(
                color: face,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: edge == Colors.transparent
                    ? null
                    : Border.all(color: edge, width: AppSpacing.hairline),
              ),
              child: Icon(widget.icon, size: widget.size * 0.45, color: ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] so it shrinks when touched, exactly as a button does.
///
/// For anything tappable that draws its own surface — a game card, an avatar,
/// a list row. Keeping the press in one widget is what makes the whole app
/// feel like it answers a finger the same way.
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed == value || !_enabled) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return widget.child;
    }
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap == null
            ? null
            : () {
                TapFeedback.press(context);
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? AppMotion.pressScaleOf(context) : 1,
          duration: AppMotion.duration(context, AppMotion.instant),
          curve: AppMotion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}
