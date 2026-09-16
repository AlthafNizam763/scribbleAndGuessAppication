import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/app/app.dart';
import 'package:scribble_guess/app/app_config.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/providers/providers.dart';
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
/// any more. It is initialised opportunistically for analytics and crash
/// reporting where it happens to be configured, and its absence is a missing
/// dashboard rather than a broken game.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
