import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/models/push_message.dart';

/// Draws a notification on this device, and turns a tap back into a route.
///
/// ## What this does and does not do
///
/// It does not decide *when* to notify. Every message it draws came from the
/// server, and the server decides who is told and what it says — see
/// `checkInNotify.service.ts`. This is a renderer.
///
/// ## Why a local-notifications plugin is needed when FCM already draws one
///
/// Because Android deliberately does not draw one while the app is in the
/// foreground. A message that arrives with the app on screen is handed to
/// `FirebaseMessaging.onMessage` and nothing is shown, which is right for a
/// chat app and wrong for a tournament deadline that a player looking at the
/// friends list would otherwise miss entirely. So a foreground message is
/// drawn here by hand.
///
/// The same plugin also creates the notification channel. That is not a
/// nicety: Android silently ignores a `channelId` it has never been told
/// about and delivers on the default channel at default importance, which on
/// a locked phone means no heads-up and no sound. To the player that looks
/// exactly like "the push never arrived", which is the bug this whole change
/// exists to fix — so the channel is created at startup, before any message
/// can reference it.
class NotificationService {
  /// Creates the service.
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The high-importance channel tournament notifications are delivered on.
  ///
  /// The id is shared with the server, which names it on every send. The two
  /// must agree exactly; see the class comment above for what happens if they
  /// do not.
  static const AndroidNotificationChannel tournamentChannel =
      AndroidNotificationChannel(
    'tournament_notifications',
    'Tournament Notifications',
    description:
        'Check-in windows and match calls for tournaments you have joined.',
    // `high` is what produces a heads-up banner and a sound on a locked
    // phone. `defaultImportance` would put the notification in the shade
    // silently, which for a two-minute check-in window is the same as not
    // sending it.
    importance: Importance.high,
  );

  /// The channel room invitations are delivered on.
  ///
  /// Its own channel rather than the tournament one, because a channel is the
  /// unit a player mutes in Android's settings: somebody who does not care
  /// about tournaments should be able to silence those without also silencing
  /// a friend asking them to play. Its id is shared with the server, which
  /// names it on every invitation send — see the class comment for what
  /// happens when the two disagree.
  static const AndroidNotificationChannel roomInvitationChannel =
      AndroidNotificationChannel(
    'room_invitations',
    'Room Invitations',
    description: 'Invitations from friends to join their game room.',
    // High for the same reason as the tournament channel: an invitation
    // expires, so one that sits silently in the shade until tomorrow is the
    // same as one that never arrived.
    importance: Importance.high,
  );

  /// Every channel this app creates, so startup cannot forget one.
  static const List<AndroidNotificationChannel> channels =
      <AndroidNotificationChannel>[tournamentChannel, roomInvitationChannel];

  /// The monochrome status-bar icon, as a drawable name.
  ///
  /// Android tints this itself and ignores every colour in it, so a launcher
  /// icon used here renders as a white square on API 21 and above. The
  /// drawable lives in `android/app/src/main/res/drawable*`.
  static const String androidIcon = 'ic_stat_notification';

  bool _ready = false;

  /// What to do when a drawn notification is tapped.
  ///
  /// Set by [FcmService] rather than by this class, because the destination is
  /// a routing decision and this file knows nothing about the router.
  void Function(PushMessage message)? onTap;

  /// Creates the channel and wires the tap handler. Safe to call twice.
  Future<void> initialize() async {
    if (_ready) return;

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(androidIcon),
          iOS: DarwinInitializationSettings(
            // All three false: `FirebaseMessaging.requestPermission` already
            // asks, and asking twice shows the player two prompts for one
            // decision.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _handleResponse,
      );

      // Android only. On iOS a channel is not a concept and this resolves to
      // null, which is why it is a null-aware call rather than a platform
      // check — one fewer thing to keep in step with the platform list.
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      for (final AndroidNotificationChannel channel in channels) {
        await android?.createNotificationChannel(channel);
      }

      _ready = true;
      AppLogger.i('[FCM] notification channels ready '
          '(${channels.map((AndroidNotificationChannel c) => c.id).join(', ')})');
    } on Object catch (error, stack) {
      // A device with no notification support at all. Logged and survived:
      // the rest of the app does not depend on this.
      AppLogger.w('[FCM] notification channel setup failed', error, stack);
    }
  }

  /// Draws [message] as a notification.
  ///
  /// Called for foreground messages only. A backgrounded or terminated app's
  /// notification is drawn by the system from the `notification` block the
  /// server sends, and calling this then would produce two.
  Future<void> show(RemoteMessage message) async {
    final RemoteNotification? notification = message.notification;
    if (notification == null) return;

    await initialize();

    // The channel the server named, when this build knows it. A channel id the
    // device has never been told about is silently ignored by Android and the
    // notification lands on the default channel at default importance, so the
    // id is resolved against the channels created above rather than passed
    // through from the wire.
    final AndroidNotificationChannel channel = _channelFor(message);

    try {
      await _plugin.show(
        // Derived from the payload rather than incremented, so the same
        // tournament's check-in — or the same invitation — replaces its own
        // notification instead of stacking a second one when a retry lands.
        id: _idFor(message),
        title: notification.title ?? AppConstants.appName,
        body: notification.body ?? '',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: androidIcon,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // The tap payload has to survive a round trip through the platform,
        // which only carries a string — so the data map is encoded here and
        // decoded in `_handleResponse`.
        payload: jsonEncode(message.data),
      );
    } on Object catch (error, stack) {
      AppLogger.w('[FCM] drawing a foreground notification failed', error, stack);
    }
  }

  /// Turns a tapped notification back into a [PushMessage].
  void _handleResponse(NotificationResponse response) {
    final String? payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map) return;

      final PushMessage message = PushMessage.fromData(
        decoded.map((Object? key, Object? value) =>
            MapEntry<String, dynamic>('$key', value)),
      );

      onTap?.call(message);
    } on Object catch (error, stack) {
      // A payload this build cannot read is a notification from a newer
      // server. Swallowed: the player has already been told what happened by
      // the notification they tapped, and crashing on the way to a screen is
      // strictly worse than not opening it.
      AppLogger.w('[FCM] unreadable notification payload', error, stack);
    }
  }

  /// Which channel [message] belongs on.
  ///
  /// Resolved from the payload's `type` rather than from the channel id the
  /// server sent, so a channel this build has never created can never be
  /// named: that is the failure that delivers the notification silently on the
  /// default channel and looks exactly like it never arrived. An unknown type
  /// falls back to the tournament channel, which is the one every build has
  /// had since push existed.
  static AndroidNotificationChannel _channelFor(RemoteMessage message) {
    return switch (PushKind.parse(message.data['type'])) {
      PushKind.roomInvitation => roomInvitationChannel,
      PushKind.tournamentCheckInOpen || PushKind.unknown => tournamentChannel,
    };
  }

  /// A stable notification id for one message.
  ///
  /// Hashed from whatever the message is *about* — the tournament, or the
  /// invitation — so a duplicate delivery lands on the same notification
  /// rather than stacking a second one, while two different invitations stay
  /// two notifications. Falls back to the message id, and then to a fixed
  /// slot: `hashCode` is not stable across runs, but neither is the process
  /// that would need it to be.
  static int _idFor(RemoteMessage message) {
    final String key = (message.data['tournamentId'] as String?) ??
        (message.data['invitationId'] as String?) ??
        message.messageId ??
        'scribble-guess';

    // Positive and inside Android's 32-bit id range.
    return key.hashCode & 0x7fffffff;
  }

  /// Whether the channel has been created. Tests and diagnostics only.
  @visibleForTesting
  bool get isReady => _ready;
}
