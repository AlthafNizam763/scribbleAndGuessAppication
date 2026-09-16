import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/sketch_button.dart';
import 'package:scribble_guess/theme/theme.dart';

/// Asks a yes/no question and resolves to the player's answer.
///
/// Returns `false` when the dialog is dismissed by tapping away, so a
/// destructive action never proceeds by accident.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(context.l10n.fromEnglish(message)),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      actions: <Widget>[
        SketchButton(
          label: cancelLabel ?? context.l10n.cancel,
          variant: SketchButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        SketchButton(
          label: confirmLabel ?? context.l10n.ok,
          variant: destructive
              ? SketchButtonVariant.danger
              : SketchButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Shows a transient message at the bottom of the screen.
///
/// [message] is translated on the way through. Most callers pass a
/// `Failure.message`, which is built deep in the app where there is no
/// `BuildContext` to localise against, so it travels as English and is turned
/// into the player's language here — at the one place every such message
/// passes through. Text that is not in the catalogue, such as a message the
/// server wrote, is shown unchanged.
void notify(BuildContext context, String message, {bool isError = false}) {
  final SketchColors colors = Theme.of(context).extension<SketchColors>() ??
      SketchColors.light;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context)
    ..clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(context.l10n.fromEnglish(message)),
      backgroundColor: isError ? colors.danger : null,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: isError ? 4 : 2),
    ),
  );
}
