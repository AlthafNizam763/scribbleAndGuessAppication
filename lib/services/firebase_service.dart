import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:scribble_guess/app/app_config.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/firebase_options.dart';

/// Brings Firebase up, once, before the first frame.
///
/// Ordering matters here and is not arbitrary:
///
/// 1. `Firebase.initializeApp` — nothing else works before it.
/// 2. Crashlytics handlers — installed as early as possible, so a crash during
///    the rest of the bootstrap is still reported.
/// 3. Emulators — pointed at *before* any request is made, because the SDKs
///    cache their endpoint after the first call.
/// 4. App Check — activated before the first authenticated request, or that
///    request goes out unattested.
abstract final class FirebaseService {
  static bool _initialized = false;

  /// Whether [initialize] has completed successfully.
  static bool get isReady => _initialized;

  /// Initialises every Firebase product the app uses.
  ///
  /// Returns `false` when configuration is missing, rather than throwing: the
  /// app can still show a useful "not configured" screen, which is far better
  /// than a white screen and a console stack trace.
  static Future<bool> initialize() async {
    if (_initialized) return true;

    final AppConfig config = AppConfig.current;

    final FirebaseOptions? options = _platformOptions;
    if (options == null) {
      AppLogger.e(
        'Firebase is not configured. Run `flutterfire configure`, or pass the '
        'FIREBASE_* --dart-define values. See README.md.',
      );
      return false;
    }

    try {
      await Firebase.initializeApp(options: options);
    } on Object catch (error, stack) {
      AppLogger.e('Firebase.initializeApp failed', error, stack);
      return false;
    }

    await _installCrashHandlers(config);
    if (config.useEmulators) {
      await _useEmulators(config);
    }
    await _activateAppCheck(config);

    _initialized = true;
    AppLogger.i('Firebase ready (${config.flavor.name})');
    return true;
  }

  /// The generated options for this platform, or `null` when Firebase was
  /// never configured for it.
  ///
  /// The question is answered here rather than in `firebase_options.dart`
  /// because `flutterfire configure` rewrites that file wholesale — anything
  /// added to it is lost on the next run.
  static FirebaseOptions? get _platformOptions {
    final FirebaseOptions options;
    try {
      options = DefaultFirebaseOptions.currentPlatform;
    } on UnsupportedError {
      // No configuration was generated for this platform at all.
      return null;
    }
    // A build with neither generated values nor --dart-define leaves these
    // empty, which `initializeApp` would only report as an opaque failure.
    if (options.apiKey.isEmpty ||
        options.appId.isEmpty ||
        options.projectId.isEmpty) {
      return null;
    }
    return options;
  }

  /// Routes Flutter and platform errors into Crashlytics (§63).
  static Future<void> _installCrashHandlers(AppConfig config) async {
    if (!config.enableCrashlytics) {
      // In debug the console is more useful than a remote dashboard.
      FlutterError.onError = FlutterError.presentError;
      return;
    }

    final FirebaseCrashlytics crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(true);

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      crashlytics.recordFlutterFatalError(details);
    };

    // Errors from outside the Flutter zone (platform channels, isolates).
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Points every SDK at the local emulator suite (§68).
  static Future<void> _useEmulators(AppConfig config) async {
    final String host = config.emulatorHost;
    try {
      await FirebaseAuth.instance.useAuthEmulator(host, EmulatorPorts.auth);
      FirebaseFirestore.instance.useFirestoreEmulator(
        host,
        EmulatorPorts.firestore,
      );
      FirebaseFunctions.instance.useFunctionsEmulator(
        host,
        EmulatorPorts.functions,
      );
      await FirebaseStorage.instance.useStorageEmulator(
        host,
        EmulatorPorts.storage,
      );
      AppLogger.i('Using Firebase emulators at $host');
    } on Object catch (error, stack) {
      AppLogger.e('Failed to attach to emulators', error, stack);
    }
  }

  /// Activates App Check (§64).
  ///
  /// Skipped against the emulator, where there is no attestation provider and
  /// nothing to protect. Failure is logged, never fatal: App Check going down
  /// should not take the game with it.
  static Future<void> _activateAppCheck(AppConfig config) async {
    if (!config.enableAppCheck) return;
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: config.flavor.isProduction
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
        // App Attest is only available from iOS 14; the fallback provider uses
        // DeviceCheck on anything older instead of failing attestation
        // outright, which would lock those devices out of the game.
        providerApple: config.flavor.isProduction
            ? const AppleAppAttestWithDeviceCheckFallbackProvider()
            : const AppleDebugProvider(),
        providerWeb: _webRecaptchaProvider(),
      );
    } on Object catch (error, stack) {
      AppLogger.e('App Check activation failed', error, stack);
    }
  }

  /// The reCAPTCHA provider for web, when a site key was supplied.
  static ReCaptchaV3Provider? _webRecaptchaProvider() {
    const String siteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');
    if (!kIsWeb || siteKey.isEmpty) return null;
    return ReCaptchaV3Provider(siteKey);
  }

  /// Analytics, or `null` when telemetry is disabled for this flavor (§62).
  static FirebaseAnalytics? get analytics =>
      AppConfig.current.enableAnalytics ? FirebaseAnalytics.instance : null;
}
