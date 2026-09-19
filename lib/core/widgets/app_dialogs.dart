import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/app_button.dart';
import 'package:scribble_guess/theme/theme.dart';

/// Asks a yes/no question and resolves to the player's answer.
///
/// Returns `false` when the dialog is dismissed by tapping away, so a
/// destructive action never proceeds by accident.
///
/// The question gets a tinted glyph above it — the primary for an ordinary
/// choice, red for a destructive one — so the weight of the decision is
/// legible before the words are read.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  IconData? icon,
}) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final AppPalette palette = dialogContext.palette;
      final Color accent = destructive ? palette.danger : palette.primary;

      return AlertDialog(
        icon: Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            color: palette.wash(accent),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(
            icon ??
                (destructive
                    ? Icons.warning_amber_rounded
                    : Icons.help_outline_rounded),
            color: accent,
            size: 26,
          ),
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(
          dialogContext.l10n.fromEnglish(message),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: cancelLabel ?? dialogContext.l10n.cancel,
                  expand: true,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppButton(
                  label: confirmLabel ?? dialogContext.l10n.ok,
                  expand: true,
                  variant: destructive
                      ? AppButtonVariant.danger
                      : AppButtonVariant.primary,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ),
            ],
          ),
        ],
      );
    },
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
///
/// The toast is the same dark chip in both themes and carries a status dot, so
/// success and failure are distinguishable at a glance without the whole bar
/// turning red and shouting.
void notify(BuildContext context, String message, {bool isError = false}) {
  final AppPalette palette =
      Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context)
    ..clearSnackBars();

  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: <Widget>[
          Container(
            height: 22,
            width: 22,
            decoration: BoxDecoration(
              color: (isError ? palette.danger : palette.success).withValues(
                alpha: 0.18,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs - 2),
            ),
            child: Icon(
              isError
                  ? Icons.priority_high_rounded
                  : Icons.check_rounded,
              size: 14,
              color: isError ? palette.danger : palette.success,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(context.l10n.fromEnglish(message))),
        ],
      ),
      duration: Duration(seconds: isError ? 4 : 2),
    ),
  );
}

/// Presents [child] as the app's modal sheet: a rounded surface with a handle,
/// a title row and the keyboard inset already accounted for.
///
/// A single entry point so every sheet in the app has the same corner radius,
/// the same padding and the same way of being dismissed.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget child,
  String? title,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    builder: (BuildContext sheetContext) {
      final AppPalette palette = sheetContext.palette;
      final TextTheme text = Theme.of(sheetContext).textTheme;

      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom:
                MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (title != null) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(title, style: text.titleLarge),
                    ),
                    AppIconButton(
                      icon: Icons.close_rounded,
                      tooltip: MaterialLocalizations.of(
                        sheetContext,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      size: 38,
                    ),
                  ],
                ),
                Divider(color: palette.border, height: AppSpacing.xl),
              ],
              Flexible(child: child),
            ],
          ),
        ),
      );
    },
  );
}
