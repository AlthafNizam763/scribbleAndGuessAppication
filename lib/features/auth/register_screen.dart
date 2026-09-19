import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/validators.dart';
import 'package:scribble_guess/data/api/auth_api.dart';
import 'package:scribble_guess/features/auth/auth_shell.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/services/auth_service.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Account creation, and the guest upgrade path.
///
/// The screen serves two arrivals and adapts to which one it is. Somebody who
/// is not signed in supplies a name along with their credentials. Somebody who
/// has been playing as a guest supplies only credentials: the server attaches
/// them to the account they already have, so their score, friends and
/// achievements carry over instead of being stranded on an orphaned row. The
/// name field is hidden in that case because the name already exists — showing
/// it would imply it could be changed here, and the server would ignore it.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _busy = false;
  bool _obscured = true;

  /// Whether this is a guest securing the account they already play on.
  ///
  /// Read once, in [initState], rather than watched: the value flips as a
  /// direct result of submitting this form, and a field vanishing underneath
  /// somebody mid-submit would be its own bug.
  late final bool _upgrading;

  @override
  void initState() {
    super.initState();
    // Read from the service for the same reason the router's redirect does:
    // it is the session itself, not a value derived from a stream that may
    // not have been delivered yet.
    final AuthService auth = ref.read(authServiceProvider);
    _upgrading = auth.currentUserId != null && auth.isAnonymous;
    if (!_upgrading) {
      // Carry over whatever name the device already knows, so a player who
      // set one up before signing in does not type it twice.
      _name.text = ref.read(profileProvider)?.name ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;

    final PlayerProfile? profile = ref.read(profileProvider);

    setState(() => _busy = true);
    final Result<AuthSession> result =
        await ref.read(authServiceProvider).registerWithEmail(
              email: _email.text.trim(),
              password: _password.text,
              username: _upgrading ? null : _name.text.trim(),
              avatarId: _upgrading ? null : profile?.avatarId,
              avatarColorIndex: _upgrading ? null : profile?.avatarColorIndex,
            );
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<AuthSession>():
        if (_upgrading) notify(context, context.l10n.authUpgraded);
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
        title: l10n.registerTitle,
        subtitle: _upgrading
            ? l10n.registerUpgradeSubtitle
            : l10n.registerSubtitle,
        children: <Widget>[
          AutofillGroup(
            child: Column(
              children: <Widget>[
                if (!_upgrading)
                  AuthField(
                    label: l10n.profileNameLabel,
                    hint: l10n.profileNameHint,
                    controller: _name,
                    autofillHints: const <String>[AutofillHints.nickname],
                    autofocus: true,
                    validator: (String? value) =>
                        _translate(Validators.username(value)),
                  ),
                AuthField(
                  label: l10n.authEmailLabel,
                  hint: l10n.authEmailHint,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  autofocus: _upgrading,
                  validator: (String? value) => _translate(Validators.email(value)),
                ),
                AuthField(
                  label: l10n.authPasswordLabel,
                  hint: l10n.authPasswordNewHint,
                  controller: _password,
                  obscure: _obscured,
                  autofillHints: const <String>[AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: _submit,
                  validator: (String? value) =>
                      _translate(Validators.newPassword(value)),
                  trailing: IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: _obscured ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
              ],
            ),
          ),
          AppButton.primary(
            label: l10n.registerAction,
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
          if (!_upgrading) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: l10n.registerHaveAccount,
              expand: true,
              onPressed: _busy ? null : () => context.pop(),
            ),
          ],
        ],
      ),
    );
  }

  String? _translate(String? problem) =>
      problem == null ? null : context.l10n.fromEnglish(problem);
}
