import 'package:flutter/material.dart';
import 'package:scribble_guess/core/config/app_brand_config.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The common frame for the sign-in and registration screens.
///
/// One widget rather than two nearly-identical builds, because the two screens
/// are the same page with a different form in it — and because the thing most
/// likely to go wrong on both is the same thing: a keyboard covering the
/// submit button on a short screen. That is solved once here, by letting the
/// content scroll and pinning nothing to the bottom.
class AuthShell extends StatelessWidget {
  const AuthShell({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  final String title;
  final String subtitle;

  /// The form fields and actions, laid out in a column.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return AppScaffold(
      child: ListView(
        // Lets a tap outside a field dismiss the keyboard, and keeps the
        // submit button reachable once the keyboard is up.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: <Widget>[
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: BrandLogo(
              markSize: 72,
              caption: AppBrandConfig.current.tagline,
              captionColor: colors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(title, style: text.displaySmall?.copyWith(color: colors.text)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: text.bodyLarge?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xl),
          ...children,
          // Breathing room under the last action, so it is never flush against
          // the bottom inset on a short screen.
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// A labelled text field, in the shape both auth forms use.
class AuthField extends StatelessWidget {
  const AuthField({
    required this.label,
    required this.controller,
    required this.validator,
    this.hint,
    this.keyboardType,
    this.autofillHints,
    this.obscure = false,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.trailing,
    super.key,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool obscure;
  final bool autofocus;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: text.labelSmall?.copyWith(color: colors.textFaint),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboardType,
            autofillHints: autofillHints,
            obscureText: obscure,
            autofocus: autofocus,
            textInputAction: textInputAction,
            onFieldSubmitted: (_) => onSubmitted?.call(),
            decoration: InputDecoration(hintText: hint, suffixIcon: trailing),
          ),
        ],
      ),
    );
  }
}
