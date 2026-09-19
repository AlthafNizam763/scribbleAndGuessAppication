import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Logging out, and deleting the account.
///
/// ## Why these two live together, away from everything else
///
/// They are the only controls in Settings a mis-tap cannot be undone from, and
/// both end the session. Grouping them at the bottom, behind their own
/// heading, is what stops "Log out" sitting one row under a volume switch.
///
/// ## The teardown is the same for both, and the order matters
///
/// 1. **Drop the socket.** It was authenticated as the player who is leaving,
///    and the server keys presence and room membership off that identity.
///    Leaving it up keeps them "online" under an account this device no longer
///    holds a credential for, and the next sign-in opens a second connection
///    beside it.
/// 2. **Forget the credentials and the cache**, which `AuthService.signOut`
///    owns — token first, so a failure part-way still leaves a device that
///    cannot authenticate.
/// 3. **Leave by `go`, not `push`.** `goNamed` replaces the navigation stack
///    rather than adding to it, so there is no authenticated screen behind the
///    sign-in gate for the back gesture to reach. The router's redirect guard
///    is the second line of defence, not the first — relying on it alone would
///    mean the player briefly sees the screen they just left.
class AccountActionsSection extends ConsumerStatefulWidget {
  const AccountActionsSection({super.key});

  @override
  ConsumerState<AccountActionsSection> createState() =>
      _AccountActionsSectionState();
}

class _AccountActionsSectionState extends ConsumerState<AccountActionsSection> {
  bool _busy = false;

  /// Everything that has to stop being true when a session ends.
  ///
  /// Shared by both paths so they cannot drift: whatever deletion needs to
  /// tear down, sign-out needs too, and a step added to one belongs in both.
  Future<void> _endSession() async {
    await ref.read(connectivityProvider).disconnect();
    await ref.read(authServiceProvider).signOut();
  }

  /// [isGuest] is passed in rather than read here.
  ///
  /// It only chooses which warning the dialog carries — a guest has no way
  /// back into the account they are leaving — and reading a derived provider
  /// inside a callback drags its whole dependency chain into a code path that
  /// wanted one boolean. Watched in `build`, where it belongs.
  Future<void> _signOut({required bool isGuest}) async {
    final bool yes = await confirm(
      context,
      title: 'Log out of STUPID GAMES?',
      message: isGuest
          ? context.l10n.settingsSignOutGuestBody
          : context.l10n.settingsSignOutBody,
      confirmLabel: 'LOG OUT',
      destructive: true,
    );
    if (!yes || !mounted) return;

    setState(() => _busy = true);
    await _endSession();
    if (!mounted) return;

    // Straight to the gate rather than letting the redirect catch it: this is
    // a deliberate exit and the player should see it happen, not watch the
    // screen they left flash past first.
    context.goNamed(AppRoutes.login);
  }

  /// Deletes the account, behind two confirmations.
  ///
  /// Two, not one, and the second asks for the word rather than offering a
  /// button. A single destructive dialog is dismissed by muscle memory; typing
  /// DELETE cannot be. The guest path skips neither — a guest who deletes has
  /// the same amount to lose, they simply have no way to get it back.
  Future<void> _deleteAccount() async {
    final bool intends = await confirm(
      context,
      title: 'Delete your account?',
      message:
          'This removes your profile, your friends, your stats and every '
          'achievement you have earned. It cannot be undone, and we cannot '
          'get any of it back for you.',
      confirmLabel: 'CONTINUE',
      destructive: true,
    );
    if (!intends || !mounted) return;

    final bool confirmed = await _confirmByTyping();
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);

    // The server call first, and its failure returned before anything local is
    // cleared: signing out of an account that still exists would leave nothing
    // to retry the deletion with.
    final Result<void> result =
        await ref.read(authServiceProvider).deleteAccount();

    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        // The account is gone. The socket goes too — it is authenticated as
        // something that no longer exists — and then the gate, by `go`.
        await ref.read(connectivityProvider).disconnect();
        if (!mounted) return;
        notify(context, 'Your account has been deleted.');
        context.goNamed(AppRoutes.login);
      case Err<void>(:final Failure failure):
        setState(() => _busy = false);
        notify(context, failure.message, isError: true);
    }
  }

  /// The second gate: type DELETE, exactly.
  Future<bool> _confirmByTyping() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      // Not dismissible by a tap outside, so the dialog is answered rather
      // than escaped from in either direction.
      barrierDismissible: false,
      builder: (BuildContext context) => const _ConfirmByTypingDialog(),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isGuest = ref.watch(isAnonymousProvider);

    return AppSection(
      title: 'Account actions',
      children: <Widget>[
        AppButton(
          label: 'LOG OUT',
          icon: Icons.logout_rounded,
          expand: true,
          busy: _busy,
          onPressed: _busy ? null : () => _signOut(isGuest: isGuest),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'DELETE ACCOUNT',
          icon: Icons.delete_forever_outlined,
          variant: AppButtonVariant.danger,
          expand: true,
          onPressed: _busy ? null : _deleteAccount,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Deleting is permanent. Logging out is not — your account and '
          'everything on it stays exactly as it is.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Asks the player to type DELETE before the account goes.
///
/// Stateful so the confirm button can enable itself as the word is typed: a
/// button that stays live and then refuses would be the same dismissable
/// dialog this exists to avoid.
///
/// The controller belongs to this widget rather than to the caller. Owned
/// outside, it has to be disposed when `showDialog`'s future completes — which
/// is the moment the *pop* starts, not the moment the route is gone, so the
/// field rebuilds one more frame against a dead controller on the way out.
class _ConfirmByTypingDialog extends StatefulWidget {
  const _ConfirmByTypingDialog();

  /// The word, uppercase. Compared case-insensitively — this is a speed bump
  /// against a reflex, not a test.
  static const String word = 'DELETE';

  @override
  State<_ConfirmByTypingDialog> createState() => _ConfirmByTypingDialogState();
}

class _ConfirmByTypingDialogState extends State<_ConfirmByTypingDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches =>
      _controller.text.trim().toUpperCase() == _ConfirmByTypingDialog.word;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: const Text('Type DELETE to confirm'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'This is the last step. Your account and everything on it will be '
            'gone for good.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'DELETE'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          style: TextButton.styleFrom(foregroundColor: colors.danger),
          child: const Text('DELETE ACCOUNT'),
        ),
      ],
    );
  }
}
