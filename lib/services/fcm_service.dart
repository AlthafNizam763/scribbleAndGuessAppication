import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/notifications_api.dart';
import 'package:scribble_guess/models/push_message.dart';
import 'package:scribble_guess/services/notification_permission_service.dart';
import 'package:scribble_guess/services/notification_service.dart';

/// Push notifications, end to end on this device.
///
/// ## Why this exists at all, given the socket
///
/// Because a socket needs a running app. The one notification this game
/// genuinely has to deliver — a tournament check-in, which a player loses
/// their place by missing — is by construction addressed to somebody who
/// registered and then closed the app. There is no connection to push down at
/// that moment, and there is no arrangement of Socket.IO that creates one.
///
/// FCM hands the message to the operating system instead, which draws it
/// whether the app is running, backgrounded, terminated, or has not been
/// opened since the phone booted. Everything else stays on the socket.
///
/// ## The four ways a message arrives
///
/// They are genuinely four different code paths and each has to be handled or
/// the notification silently does nothing:
///
/// | App state           | Drawn by | Delivered to                       |
/// |---------------------|----------|------------------------------------|
/// | Foreground          | us       | `onMessage` → [NotificationService]|
/// | Background          | system   | `onMessageOpenedApp`, on tap       |
/// | Terminated          | system   | `getInitialMessage`, on tap        |
/// | Background, no tap  | system   | the background isolate handler      |
///
/// `getInitialMessage` is the one most often forgotten, and it is the one the
/// reported bug is about: it is the *only* way a tap on a notification that
/// launched the app from cold is ever seen.
///
/// ## Registration is idempotent everywhere
///
/// [registerToken] is called after sign-in, at startup, and on every refresh,
/// because those three overlap constantly and none of them can be sure the
/// others ran. The server's endpoint is one upsert keyed on the token, so
/// calling it three times costs three cheap writes and cannot produce three
/// registrations.

/// Handles a message that arrived while the app was in the background.
///
/// Must be a top-level function: Flutter spawns a *separate isolate* to run
/// it, with none of the app's state, so anything captured from a closure or
/// read from a provider would not exist. It also must be annotated, or tree
/// shaking removes it from a release build and background messages stop
/// arriving in exactly the build where that is hardest to notice.
///
/// There is deliberately almost nothing here. The notification itself is drawn
/// by the operating system from the `notification` block the server sends —
/// that is why the server always sends one — so this isolate has no display
/// work to do, and any state it changed would be thrown away when it ends.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The isolate starts with no Firebase app, so it has to make its own before
  // anything in the plugin will work.
  await Firebase.initializeApp();

  if (kDebugMode) {
    AppLogger.i('[FCM] background message ${message.messageId ?? '-'}');
  }
}

/// Wires FCM into the app.
class FcmService {
  /// Creates the service.
  FcmService({
    required NotificationsApi api,
    required NotificationService notifications,
    required NotificationPermissionService permissions,
    FirebaseMessaging? messaging,
  })  : _api = api,
        _notifications = notifications,
        _permissions = permissions,
        _messaging = messaging ?? FirebaseMessaging.instance;

  final NotificationsApi _api;
  final NotificationService _notifications;
  final NotificationPermissionService _permissions;
  final FirebaseMessaging _messaging;

  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<String>? _refresh;

  bool _started = false;

  /// The token this device last registered, or null.
  String? _token;

  /// The token last sent to the server. Diagnostics only — never logged whole.
  String? get token => _token;

  /// Emits whenever a notification should take the player somewhere.
  ///
  /// A stream rather than a callback because the listener is a widget that
  /// mounts after this service starts: a terminated-app launch resolves its
  /// message during startup, before any screen exists to receive it, and a
  /// callback set later would have missed it. The controller replays nothing,
  /// so [pendingRoute] holds that first message until somebody asks.
  Stream<PushMessage> get taps => _taps.stream;
  final StreamController<PushMessage> _taps =
      StreamController<PushMessage>.broadcast();

  /// The message that launched the app, if one did and nobody has taken it.
  ///
  /// Read once by the router's listener and then cleared. This is the whole
  /// answer to "the notification opened the app but landed on the home
  /// screen": the tap arrives before there is a navigator.
  PushMessage? pendingTap;

  /// Brings push up. Safe to call more than once.
  ///
  /// Returns false when this device cannot do push at all — no Firebase
  /// configuration, no Play Services, a platform with no messaging support —
  /// which is a normal state and not an error. The rest of the app is
  /// unaffected either way.
  Future<bool> start() async {
    if (_started) return true;

    if (Firebase.apps.isEmpty) {
      // `main` initialises Firebase before this runs, so an empty list means
      // that failed — a missing `google-services.json`, most often.
      AppLogger.w('[FCM] messaging skipped: Firebase is not initialised');
      return false;
    }

    try {
      await _notifications.initialize();
      _notifications.onTap = _emit;

      final NotificationPermission permission = await _permissions.request();

      // Registration continues even when permission was refused, deliberately.
      // A refused device still has a valid token and the server may still
      // address it; the operating system simply draws nothing. Skipping
      // registration here would mean a player who later turns notifications
      // on in Settings is never reached, because nothing would re-register.
      AppLogger.i('[FCM] permissionStatus=${permission.name}');

      // iOS only, and harmless elsewhere: without this a foreground message
      // arrives with no `notification` block on Apple platforms.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _foreground = FirebaseMessaging.onMessage.listen(_onForeground);
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
      _refresh = _messaging.onTokenRefresh.listen(_onTokenRefresh);

      // The cold-start tap. Resolved before any screen is mounted, so it is
      // held in `pendingTap` rather than pushed at a stream nobody is on yet.
      final RemoteMessage? initial = await _messaging.getInitialMessage();
      if (initial != null) {
        AppLogger.i('[FCM] launched by a notification');
        _emit(PushMessage.fromData(initial.data));
      }

      _started = true;
      return true;
    } on Object catch (error, stack) {
      // Almost always a device with no Google Play Services. Push is an
      // enhancement; a game that would not start without it would be worse
      // than one that starts without notifications.
      AppLogger.w('[FCM] messaging could not start', error, stack);
      return false;
    }
  }

  /// Reads this device's token and sends it to the backend.
  ///
  /// Call after sign-in and at startup. Returns the token on success, or null
  /// when there is none to send — which happens on an emulator without Play
  /// Services and on a device that is offline at launch, and is not an error.
  ///
  /// The registration is what makes a *closed* app reachable, so it is the one
  /// step here that genuinely must happen; everything else in this class only
  /// affects what a running app does with a message.
  Future<String?> registerToken() async {
    try {
      final String? token = await _messaging.getToken();

      if (token == null || token.isEmpty) {
        AppLogger.w('[FCM] tokenRegistered=false (no token available)');
        return null;
      }

      // Awaited, not just returned. `return f()` hands the future back and
      // completes the `try` immediately, so a failure inside `_sendToBackend`
      // lands *outside* this catch and surfaces as an unhandled exception from
      // the splash screen — which is exactly how a broken registration
      // presented itself: a red error in the log, no token on the server, and
      // a `catch` sitting right there that never ran.
      return await _sendToBackend(token, reason: 'startup');
    } on Object catch (error, stack) {
      AppLogger.w('[FCM] registering the device token failed', error, stack);
      return null;
    }
  }

  /// Retires this device on the backend, at sign-out.
  ///
  /// Deletes the *registration*, not the token: the token stays on the device
  /// and the next sign-in re-registers it. Deleting the token itself would
  /// force a round trip to Google on the next launch for no benefit.
  Future<void> unregisterToken() async {
    final String? token = _token ?? await _messaging.getToken();
    if (token == null || token.isEmpty) return;

    final Result<bool> outcome = await _api.unregisterDeviceToken(token);

    AppLogger.i('[FCM] token retired (${outcome is Ok<bool> ? 'ok' : 'failed'})');
    _token = null;
  }

  /// Stops listening. Called when the provider is disposed.
  Future<void> dispose() async {
    await _foreground?.cancel();
    await _opened?.cancel();
    await _refresh?.cancel();
    await _taps.close();
    _started = false;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Draws a message that arrived with the app on screen.
  void _onForeground(RemoteMessage message) {
    AppLogger.i('[FCM] foreground message type='
        '${message.data['type'] ?? '-'}');
    unawaited(_notifications.show(message));
  }

  /// A tap on a notification drawn by the system while the app was backgrounded.
  void _onOpened(RemoteMessage message) {
    AppLogger.i('[FCM] notification opened the app');
    _emit(PushMessage.fromData(message.data));
  }

  /// FCM issued this device a new token.
  ///
  /// Happens on reinstall, on a restore to a new handset, and occasionally on
  /// its own. Registering the new one is what stops notifications quietly
  /// ceasing to arrive weeks later — the failure mode a token refresh causes
  /// if it is not handled, and one that is close to impossible to reproduce
  /// deliberately.
  void _onTokenRefresh(String token) {
    AppLogger.i('[FCM] tokenUpdated=true');
    unawaited(_sendToBackend(token, reason: 'refresh'));
  }

  /// Posts [token] to the backend, remembering it on success.
  Future<String?> _sendToBackend(String token, {required String reason}) async {
    final Result<int> outcome = await _api.registerDeviceToken(
      token: token,
      platform: _platform,
    );

    switch (outcome) {
      case Ok<int>(value: final int devices):
        _token = token;
        AppLogger.i('[FCM] tokenRegistered=true reason=$reason '
            'token=${_mask(token)} devices=$devices');
        return token;
      case Err<int>():
        // Not retried here. The next launch registers again, and the caller
        // that matters — a player about to join a tournament — opens the app
        // to do it.
        AppLogger.w('[FCM] tokenRegistered=false reason=$reason '
            'token=${_mask(token)}');
        return null;
    }
  }

  /// Publishes a tap, holding it if nothing is listening yet.
  void _emit(PushMessage message) {
    if (message.isEmpty) {
      AppLogger.w('[FCM] ignoring a notification with no usable payload');
      return;
    }

    if (_taps.hasListener) {
      _taps.add(message);
      return;
    }

    // Nothing is listening: this is the cold start. Held for the router's
    // listener to collect when it mounts.
    pendingTap = message;
  }

  /// Which platform this build is, in the server's vocabulary.
  static String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  /// Hides all but the tail of a token.
  ///
  /// A registration token is a capability: whoever holds it can deliver a
  /// notification to this handset. Logs are read in more places than the
  /// keystore is, so only enough to tell two devices apart is ever printed.
  static String _mask(String token) =>
      token.length <= 8 ? '***' : '***${token.substring(token.length - 6)}';
}
