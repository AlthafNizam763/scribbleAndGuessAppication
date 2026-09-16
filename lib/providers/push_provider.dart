import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/models/push_message.dart';
import 'package:scribble_guess/providers/notifications_provider.dart';
import 'package:scribble_guess/services/fcm_service.dart';
import 'package:scribble_guess/services/notification_permission_service.dart';
import 'package:scribble_guess/services/notification_service.dart';

/// Push notifications.
///
/// Three small services rather than one, because they fail independently and
/// for different reasons: the channel can fail to be created on a device with
/// notifications disabled system-wide, permission can be refused while
/// everything else works, and the token can be unavailable on a handset with
/// no Play Services. Keeping them apart is what lets a device that was denied
/// permission still register — see the note in [FcmService.start] for why that
/// matters.

/// Draws notifications and owns the Android channel.
final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((Ref ref) => NotificationService());

/// Asks for, and reports, notification permission.
final Provider<NotificationPermissionService> notificationPermissionProvider =
    Provider<NotificationPermissionService>(
  (Ref ref) => NotificationPermissionService(),
);

/// FCM: the token, the listeners, and the tap stream.
///
/// Held for the life of the app. Rebuilt if the REST origin changes, because
/// the token has to be registered with whichever backend the rest of the app
/// is talking to — registering a device with a server that will never send to
/// it is the silent half of the "notifications stopped working" bug.
final Provider<FcmService> fcmServiceProvider = Provider<FcmService>((Ref ref) {
  final FcmService service = FcmService(
    api: ref.watch(notificationsApiProvider),
    notifications: ref.watch(notificationServiceProvider),
    permissions: ref.watch(notificationPermissionProvider),
  );

  ref.onDispose(service.dispose);
  return service;
});

/// Every notification tap, as a destination.
///
/// A [StreamProvider] over [FcmService.taps]. The cold-start tap does *not*
/// come through here — it is resolved before any widget exists to listen —
/// and is collected from [FcmService.pendingTap] instead. See
/// `PushNavigationListener` in `app/push_navigation.dart`, which handles both.
final StreamProvider<PushMessage> pushTapProvider = StreamProvider<PushMessage>(
  (Ref ref) => ref.watch(fcmServiceProvider).taps,
);
