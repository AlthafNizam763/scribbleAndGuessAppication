import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/providers/location_provider.dart';
import 'package:scribble_guess/services/location_service.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The one path from "I want my town filled in" to a saved locality.
///
/// ## Why it is a function and not part of the section widget
///
/// Two screens start it — the profile section and the Settings row — and a
/// permission flow that exists twice is a permission flow where one copy
/// eventually forgets to explain itself first. Everything the player sees
/// between the tap and the result lives here, so both entry points are
/// literally the same flow.
///
/// ## The explanation comes before the system prompt
///
/// [askToUseLocation] runs before [LocationService.detect] is ever called, and
/// a no stops the flow without the system dialog appearing at all. That
/// ordering is the point: the OS prompt is a yes/no with no room to say what
/// the location is for or what is kept, and burning the one permission prompt
/// a player gets on an unexplained question is how apps end up permanently
/// denied.
///
/// It is skipped only where there is nothing left to explain -- permission
/// already stands, so no prompt will appear and the tap just reads a fix.

/// Shows what location would be used for, and returns whether to go ahead.
///
/// Dismissing by tapping away counts as no.
Future<bool> askToUseLocation(BuildContext context) => confirm(
      context,
      title: context.l10n.locationNoticeTitle,
      message: context.l10n.locationNoticeBody,
      confirmLabel: context.l10n.locationNoticeAllow,
      cancelLabel: context.l10n.locationNoticeNotNow,
    );

/// Explains, detects, saves, and tells the player what happened.
///
/// Returns true only when a town was actually written. Every other path —
/// declined, switched off, unsupported, no signal — returns false having left
/// the stored locality untouched and the app working. [onTypeInstead] is
/// offered on those paths so the player is never left at a dead end; it is
/// called after the message is shown, and is what reveals the manual fields on
/// the profile or navigates to them from Settings.
Future<bool> runLocationUpdate(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onTypeInstead,
}) async {
  // The explanation is owed before the system prompt, not before every tap.
  // Once permission stands there is nothing left to ask for, so this goes
  // straight to the fix -- see `LocationService.hasPermission`.
  if (!await ref.read(locationServiceProvider).hasPermission()) {
    if (!context.mounted) {
      return false;
    }
    if (!await askToUseLocation(context)) {
      return false;
    }
  }
  if (!context.mounted) {
    return false;
  }

  final LocationOutcome outcome =
      await ref.read(localityProvider.notifier).detectAndSave();

  if (!context.mounted) {
    return false;
  }

  switch (outcome) {
    case LocationFound():
      notify(context, context.l10n.locationSaved);
      return true;

    // A first refusal. Nothing to explain that the player did not just decide,
    // so this is a one-line acknowledgement rather than another dialog.
    case LocationDenied(permanently: false):
      notify(context, context.l10n.locationDeniedHint);

    // A permanent one. Tapping the button again would now do nothing visible,
    // which is worth a dialog, because only system settings can change it.
    case LocationDenied(permanently: true):
      await _offerSettings(
        context,
        title: context.l10n.locationBlockedTitle,
        body: context.l10n.locationBlockedBody,
        open: () => ref.read(locationServiceProvider).openPermissionSettings(),
      );

    // Location is off for the whole device, so the app's own permission page
    // is the wrong destination — this one opens the location switch itself.
    case LocationOff():
      await _offerSettings(
        context,
        title: context.l10n.locationOffTitle,
        body: context.l10n.locationOffBody,
        open: () =>
            ref.read(locationServiceProvider).openDeviceLocationSettings(),
      );

    case LocationUnsupported():
      notify(context, context.l10n.locationUnsupported);

    case LocationNotFound():
      notify(context, context.l10n.locationNotFound, isError: true);

    // The failure's own message is preferred where it has one: a timeout and
    // an offline phone are different problems with different fixes, and the
    // player can act on the difference.
    case LocationFailed(:final Failure failure):
      notify(
        context,
        failure.isRetryable ? failure.userMessage : context.l10n.locationFailed,
        isError: true,
      );
  }

  onTypeInstead?.call();
  return false;
}

/// A two-button prompt whose confirm opens a system settings page.
///
/// Deliberately not a snackbar with an action: these two cases leave the app
/// entirely to be fixed, and that is worth stopping the player for.
Future<void> _offerSettings(
  BuildContext context, {
  required String title,
  required String body,
  required Future<void> Function() open,
}) async {
  final bool go = await confirm(
    context,
    title: title,
    message: body,
    confirmLabel: context.l10n.locationOpenSettings,
    cancelLabel: context.l10n.cancel,
  );

  if (go) {
    await open();
  }
}
