import 'package:flutter/material.dart';
import 'package:scribble_guess/core/widgets/tap_feedback.dart';
import 'package:scribble_guess/theme/theme.dart';

/// How much visual weight a [SketchButton] carries.
enum SketchButtonVariant {
  /// Filled with ink. One per screen, for the thing the player came to do.
  primary,

  /// Outlined on paper. The default for everything else.
  secondary,

  /// Outlined in red, for destructive choices.
  danger,

  /// Borderless, for tertiary actions that should not compete.
  ghost,
}

/// A hand-drawn button: a flat face with a hard offset shadow that presses in
/// when touched.
///
/// The app defines no `ElevatedButton` theme, because Material's elevation and
/// splash fight the paper metaphor. This is the button the whole app uses.
class SketchButton extends StatefulWidget {
  const SketchButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = SketchButtonVariant.secondary,
    this.expand = false,
    this.busy = false,
    super.key,
  });

  /// A full-width primary button, the common shape for a screen's main action.
  const SketchButton.primary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.busy = false,
    super.key,
  }) : variant = SketchButtonVariant.primary;

  final String label;
  final IconData? icon;

  /// `null` disables the button.
  final VoidCallback? onPressed;
  final SketchButtonVariant variant;
  final bool expand;

  /// Swaps the label for a spinner and blocks input.
  final bool busy;

  @override
  State<SketchButton> createState() => _SketchButtonState();
}

class _SketchButtonState extends State<SketchButton> {
  static const double _shadowOffset = 3;

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
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    final (Color face, Color border, Color ink) = switch (widget.variant) {
      SketchButtonVariant.primary => (colors.ink, colors.ink, colors.paper),
      SketchButtonVariant.secondary => (colors.paper, colors.ink, colors.ink),
      SketchButtonVariant.danger => (colors.paper, colors.danger, colors.danger),
      SketchButtonVariant.ghost => (
          Colors.transparent,
          Colors.transparent,
          colors.inkSoft,
        ),
    };

    // Disabled buttons keep their shape but lose their contrast, so the layout
    // never shifts as a form becomes valid.
    final double opacity = _enabled ? 1 : 0.38;
    final bool hasShadow =
        widget.variant != SketchButtonVariant.ghost && _enabled;
    final double dropped = _pressed ? _shadowOffset : 0;

    final Widget content = widget.busy
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(ink),
            ),
          )
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                Icon(widget.icon, size: 20, color: ink),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(color: ink),
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
        child: Padding(
          // Reserve the shadow's travel so pressing never nudges neighbours.
          padding: const EdgeInsets.only(
            right: _shadowOffset,
            bottom: _shadowOffset,
          ),
          child: Transform.translate(
            offset: Offset(dropped, dropped),
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: widget.expand ? double.infinity : null,
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTapTarget,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: face,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: border,
                    width: AppSpacing.border,
                  ),
                  boxShadow: hasShadow && !_pressed
                      ? <BoxShadow>[
                          BoxShadow(
                            color: border,
                            offset: const Offset(_shadowOffset, _shadowOffset),
                          ),
                        ]
                      : null,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
