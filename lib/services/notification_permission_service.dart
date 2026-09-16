import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';

/// Whether this device has agreed to be interrupted.
///
/// A thin wrapper over `FirebaseMessaging.requestPermission`, kept separate
/// from [FcmService] for one reason: permission and registration fail
/// independently and have completely different remedies. A device that was
/// denied permission has a token and can be sent to — the message simply is
/// not drawn — and a device that was granted permission may still have no
/// token because the network was down. Conflating them produces the classic
/// bug where a player who said yes is never registered because something else
/// in the same method threw.
enum NotificationPermission {
  /// The player said yes. Notifications are drawn.
  granted,

  /// iOS only: allowed, but quietly — no banner, no sound.
  provisional,

  /// The player said no, or an Android 13+ prompt was dismissed.
  denied,

  /// The platform could not be asked at all.
  unknown;

  /// Whether a notification would actually be shown.
  bool get isVisible =>
      this == NotificationPermission.granted ||
      this == NotificationPermission.provisional;
}

/// Asks for, and reports, notification permission.
class NotificationPermissionService {
  /// Creates the service over [messaging].
  NotificationPermissionService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  /// Asks the platform, showing the system prompt if it has not been shown.
  ///
  /// ## Why this is safe to call on every launch
  ///
  /// Both platforms show the prompt at most once per install and answer from
  /// the stored decision afterwards, so repeated calls are a cheap read rather
  /// than a player being pestered. That is what lets the startup path call it
  /// unconditionally instead of tracking "have we asked yet" in preferences,
  /// which would go wrong the first time somebody cleared app data.
  ///
  /// On Android 12 and below there is no runtime permission at all and this
  /// returns [NotificationPermission.granted] without prompting.
  ///
  /// Never throws: a device with no Play Services, or an emulator with none,
  /// reports [NotificationPermission.unknown] and the rest of the app carries
  /// on. Push is an enhancement, and a game that refused to start without it
  /// would be a worse game.
  Future<NotificationPermission> request() async {
    try {
      final NotificationSettings settings = await _messaging.requestPermission(
        // Everything else defaults to false or to the platform's own default.
        // Only what the game actually uses is asked for: a banner with a sound,
        // and a badge on the icon.
        badge: true,
        sound: true,
      );

      final NotificationPermission status = _map(settings.authorizationStatus);

      AppLogger.i('[FCM] permissionStatus=${status.name}');
      return status;
    } on Object catch (error, stack) {
      AppLogger.w('[FCM] permission request failed', error, stack);
      return NotificationPermission.unknown;
    }
  }

  /// What the platform currently thinks, without prompting.
  Future<NotificationPermission> current() async {
    try {
      final NotificationSettings settings =
          await _messaging.getNotificationSettings();
      return _map(settings.authorizationStatus);
    } on Object catch (error, stack) {
      AppLogger.w('[FCM] reading permission failed', error, stack);
      return NotificationPermission.unknown;
    }
  }

  static NotificationPermission _map(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized => NotificationPermission.granted,
        AuthorizationStatus.provisional => NotificationPermission.provisional,
        // `deniedPermanently` is Android's "don't ask again". Folded into the
        // same answer as a plain denial on purpose: nothing in this app
        // behaves differently between the two — neither can be re-prompted
        // from here, and both mean the notification will not be drawn.
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently =>
          NotificationPermission.denied,
        AuthorizationStatus.notDetermined => NotificationPermission.unknown,
      };
}
