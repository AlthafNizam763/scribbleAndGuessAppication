import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/validators.dart';
import 'package:scribble_guess/data/api/auth_api.dart';
import 'package:scribble_guess/features/auth/auth_shell.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The sign-in gate.
///
/// Reached when the splash screen finds no resumable session, and the only
/// route an unauthenticated player can sit on besides registration. Guest play
/// is still offered here — it is a deliberate, tapped choice now rather than
/// something that happened silently at launch.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _busy = false;
  bool _obscured = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    final Result<AuthSession> result =
        await ref.read(authServiceProvider).signInWithEmail(
              email: _email.text.trim(),
              password: _password.text,
            );
    if (!mounted) return;
    setState(() => _busy = false);

    _route(result);
  }

  Future<void> _guest() async {
    if (_busy) return;

    setState(() => _busy = true);
    final Result<AuthSession> result =
        await ref.read(authServiceProvider).continueAsGuest();
    if (!mounted) return;
    setState(() => _busy = false);

    _route(result);
  }

  /// Sends a successful sign-in onward, or reports why it failed.
  ///
  /// A player with no saved profile goes to make one; everyone else lands on
  /// the hub. `goNamed` rather than `pushNamed`, so the gate is replaced
  /// rather than left underneath for a back gesture to return to.
  void _route(Result<AuthSession> result) {
    switch (result) {
      case Ok<AuthSession>():
        context.goNamed(
          ref.read(hasProfileProvider) ? AppRoutes.home : AppRoutes.editProfile,
        );
      case Err<AuthSession>(:final Failure failure):
        notify(context, failure.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppText l10n = context.l10n;

    return Form(
      key: _form,
      child: AuthShell(
        title: l10n.loginTitle,
        subtitle: l10n.loginSubtitle,
        children: <Widget>[
          AutofillGroup(
            child: Column(
              children: <Widget>[
                AuthField(
                  label: l10n.authEmailLabel,
                  hint: l10n.authEmailHint,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  autofocus: true,
                  validator: (String? value) => _translate(Validators.email(value)),
                ),
                AuthField(
                  label: l10n.authPasswordLabel,
                  hint: l10n.authPasswordHint,
                  controller: _password,
                  obscure: _obscured,
                  autofillHints: const <String>[AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: _signIn,
                  validator: (String? value) => _translate(Validators.password(value)),
                  trailing: _RevealButton(
                    obscured: _obscured,
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
              ],
            ),
          ),
          AppButton.primary(
            label: l10n.loginAction,
            icon: Icons.login_rounded,
            busy: _busy,
            onPressed: _busy ? null : _signIn,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: l10n.loginCreateAccount,
            icon: Icons.person_add_alt_1_outlined,
            expand: true,
            onPressed: _busy ? null : () => context.pushNamed(AppRoutes.register),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _Divider(),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: l10n.loginAsGuest,
            icon: Icons.sports_esports_outlined,
            expand: true,
            onPressed: _busy ? null : _guest,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.loginGuestNote,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }

  /// `Validators` has no context, so its message is English until it reaches
  /// a widget. This is that widget — the same arrangement the profile screen
  /// uses.
  String? _translate(String? problem) =>
      problem == null ? null : context.l10n.fromEnglish(problem);
}

/// Toggles a password field between hidden and visible.
class _RevealButton extends StatelessWidget {
  const _RevealButton({required this.obscured, required this.onPressed});

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        tooltip: obscured ? 'Show password' : 'Hide password',
        onPressed: onPressed,
      );
}

/// A hairline with the word "or" set into it.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    return Row(
      children: <Widget>[
        Expanded(child: Divider(color: colors.textMuted.withValues(alpha: 0.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'or',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textMuted),
          ),
        ),
        Expanded(child: Divider(color: colors.textMuted.withValues(alpha: 0.3))),
      ],
    );
  }
}
