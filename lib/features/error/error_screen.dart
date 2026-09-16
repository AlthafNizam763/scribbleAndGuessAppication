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
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final String heading = title ?? titleFor(context.l10n, failure?.code);
    // The message arrives in English from `Failure`, which has no context to
    // localise against; this is the render site, so this is where it happens.
    final String detail = failure == null
        ? context.l10n.errorUnknown
        : context.l10n.fromEnglish(failure!.message);

    return SketchScaffold(
      showBack: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.sentiment_dissatisfied, size: 64, color: colors.inkFaint),
            const SizedBox(height: AppSpacing.lg),
            Text(
              heading,
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(color: colors.ink),
            ),
            if (detail != heading) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.inkSoft),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SketchButton(
              label: context.l10n.resultsBackHome,
              icon: Icons.home_outlined,
              variant: SketchButtonVariant.primary,
              onPressed: () => context.goNamed(AppRoutes.home),
            ),
          ],
        ),
      ),
    );
  }
}
