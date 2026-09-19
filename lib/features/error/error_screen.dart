import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// A dead end with an explanation and a way back to the menu.
///
/// Used for the failures that end a session outright — the room closed, you
/// were kicked, the connection is gone — where dropping the player onto the
/// menu with no word about what happened would be baffling.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({this.failure, this.title, super.key});

  /// What went wrong. Falls back to a generic message when absent, which is
  /// what an unrecognised deep link produces.
  final Failure? failure;

  /// Overrides the heading, for failures that deserve their own wording.
  final String? title;

  /// The heading for a given code, so the screen names the problem rather than
  /// leading with a generic apology.
  static String titleFor(AppText l10n, AppErrorCode? code) => switch (code) {
        AppErrorCode.roomNotFound => l10n.errorRoomNotFoundTitle,
        AppErrorCode.roomFull => l10n.errorRoomFullTitle,
        AppErrorCode.connectionLost ||
        AppErrorCode.network ||
        AppErrorCode.timeout =>
          l10n.errorConnectionTitle,
        AppErrorCode.kicked => l10n.moderationYouWereKicked,
        AppErrorCode.banned => l10n.moderationYouWereBanned,
        _ => l10n.errorUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final String heading = title ?? titleFor(context.l10n, failure?.code);
    // The message arrives in English from `Failure`, which has no context to
    // localise against; this is the render site, so this is where it happens.
    final String detail = failure == null
        ? context.l10n.errorUnknown
        : context.l10n.fromEnglish(failure!.message);

    return AppScaffold(
      showBack: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: colors.wash(colors.danger),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              ),
              child: Icon(
                Icons.sentiment_dissatisfied_rounded,
                size: 38,
                color: colors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              heading,
              textAlign: TextAlign.center,
              style: text.headlineMedium?.copyWith(color: colors.text),
            ),
            if (detail != heading) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.textMuted),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: context.l10n.resultsBackHome,
              icon: Icons.home_rounded,
              variant: AppButtonVariant.primary,
              onPressed: () => context.goNamed(AppRoutes.home),
            ),
          ],
        ),
      ),
    );
  }
}
