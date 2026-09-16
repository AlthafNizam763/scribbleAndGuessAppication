import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/app/app.dart';
import 'package:scribble_guess/app/app_config.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/services/fcm_service.dart';
import 'package:scribble_guess/services/firebase_service.dart';
import 'package:scribble_guess/services/local_profile_repository.dart';
import 'package:scribble_guess/services/local_settings_repository.dart';
import 'package:scribble_guess/services/preferences_store.dart';

/// Starts the app.
///
/// The order of work here is deliberate. Local preferences are read first,
/// because the theme of the very first frame depends on them and flashing the
/// wrong one looks broken. Nothing else is awaited: the session is established
/// by the splash screen, which already has a place to show progress and a
/// retry button if the network is down (§6).
///
/// ## Why Firebase no longer gates startup
///
/// This used to refuse to run without a configured Firebase project, because
/// Firestore was the game's authority. The Node backend now owns the game —
/// rooms, rounds, scoring, the lot — so Firebase is not on the critical path
/// any more. It is initialised opportunistically for analytics, crash
/// reporting and push, and its absence is a missing dashboard and no
/// notifications rather than a broken game.
///
/// ## Why Firebase *is* awaited, when nothing else is
///
/// Because messaging cannot be set up without it, and the background message
/// handler has to be registered before the first frame — a message that
/// arrives while the app is backgrounded is delivered to the plugin, which
/// looks up the handler that was registered at startup and drops the message
/// if there is not one. Registering it later means losing exactly the
/// notifications this is all for.
///
/// It is a handful of milliseconds of local work, it cannot reach the network,
/// and a failure returns false rather than throwing, so the cost of awaiting
/// it is a frame rather than a round trip.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bool firebaseReady = await FirebaseService.initialize();

  if (firebaseReady) {
    // Must be registered before the app runs; see above. Points at a
    // top-level function because Flutter runs it in its own isolate, which
    // has none of this one's state.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } else {
    AppLogger.w(
      'Firebase is not configured: push notifications are disabled. '
      'Run `flutterfire configure`, or add android/app/google-services.json.',
    );
  }

  final PreferencesStore store = await PreferencesStore.open();
  final AppSettings settings = await LocalSettingsRepository(store).load();
  final PlayerProfile? profile = await LocalProfileRepository(store).load();

  AppLogger.i('Starting ${AppConfig.current}');

  runApp(
    ProviderScope(
      overrides: <Override>[
        preferencesStoreProvider.overrideWithValue(store),
        bootstrapSettingsProvider.overrideWithValue(settings),
        bootstrapProfileProvider.overrideWithValue(profile),
      ],
      child: const ScribbleGuessApp(),
    ),
  );
}
