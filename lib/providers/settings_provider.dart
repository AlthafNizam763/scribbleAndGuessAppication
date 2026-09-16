import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/app/app_config.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/repositories/settings_repository.dart';

/// App preferences, held in memory and written through to disk on change.
///
/// Writes are optimistic: the UI updates immediately and the disk write is
/// awaited in the background. A failed write is not surfaced, because a toggle
/// that visibly refuses to move is worse than one that silently forgets.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(bootstrapSettingsProvider);

  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  Future<Result<void>> _write(AppSettings next) {
    state = next;
    return _repository.save(next);
  }

  Future<Result<void>> setSoundEnabled(bool value) =>
      _write(state.copyWith(soundEnabled: value));

  Future<Result<void>> setHapticsEnabled(bool value) =>
      _write(state.copyWith(hapticsEnabled: value));

  Future<Result<void>> setReducedMotion(bool value) =>
      _write(state.copyWith(reducedMotion: value));

  Future<Result<void>> setThemeMode(SketchThemeMode mode) =>
      _write(state.copyWith(themeMode: mode));

  /// Switches the interface language.
  ///
  /// Takes effect immediately and app-wide: [localeProvider] feeds
  /// `MaterialApp.locale`, and Arabic additionally flips the whole layout
  /// through the framework's own `Directionality`. Nothing is sent to the
  /// server, and no room setting changes.
  Future<Result<void>> setLanguage(AppLanguage language) =>
      _write(state.copyWith(language: language));

  Future<Result<void>> setServerUrl(String url) =>
      _write(state.copyWith(serverUrl: url.trim()));

  /// Restores every preference to its shipped default.
  Future<Result<void>> resetAll() => _write(AppSettings.defaults);
}

final NotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// The origin the REST API is reached at.
///
/// Resolution happens here and only here, so the two transports cannot end up
/// pointing at different backends. The player's override wins if they set one;
/// otherwise the build's configured backend, which is the deployment.
///
/// Both transports have to agree: the JWT the socket presents at its handshake
/// is the one this origin issued, and a different backend signs with a
/// different secret and would refuse it.
final Provider<String> apiBaseUrlProvider = Provider<String>((Ref ref) {
  final String override = ref
      .watch(settingsProvider.select((AppSettings s) => s.serverUrl))
      .trim();
  return override.isNotEmpty ? override : AppConfig.current.apiBaseUrl;
});

/// The origin the Socket.IO connection is opened against.
///
/// In production this is *not* [apiBaseUrlProvider]. The REST API is deployed
/// serverless and cannot hold a websocket open, so Socket.IO runs on its own
/// always-on host and `AppConfig.drawingSocketUrl` points there. Both
/// deployments share a `JWT_SECRET`, so the token one issues authenticates
/// against the other and the split is invisible to the player.
///
/// The player's override deliberately applies to *both* transports. It exists
/// for one purpose — pointing the app at a laptop on the same wifi, which is
/// the only practical way to play from two physical phones — and a local
/// `server.ts` really does serve REST and the websocket on a single port.
/// Splitting the override in two would ask a developer to type an address
/// twice to describe one machine.
///
/// The origin only, with no `/socket.io` suffix: the client appends that path
/// itself.
final Provider<String> socketUrlProvider = Provider<String>((Ref ref) {
  final String override = ref
      .watch(settingsProvider.select((AppSettings s) => s.serverUrl))
      .trim();
  return override.isNotEmpty ? override : AppConfig.current.drawingSocketUrl;
});

/// The [ThemeMode] implied by the player's choice.
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>((Ref ref) {
  final SketchThemeMode mode =
      ref.watch(settingsProvider.select((AppSettings s) => s.themeMode));
  return switch (mode) {
    SketchThemeMode.light => ThemeMode.light,
    SketchThemeMode.dark => ThemeMode.dark,
    SketchThemeMode.system => ThemeMode.system,
  };
});

/// Whether animations should be suppressed, honouring both the app setting and
/// the platform accessibility flag.
final Provider<bool> reducedMotionProvider = Provider<bool>(
  (Ref ref) => ref.watch(
    settingsProvider.select((AppSettings s) => s.reducedMotion),
  ),
);

/// The interface language the player chose.
final Provider<AppLanguage> appLanguageProvider = Provider<AppLanguage>(
  (Ref ref) => ref.watch(
    settingsProvider.select((AppSettings s) => s.language),
  ),
);

/// The [Locale] handed to `MaterialApp`.
///
/// Derived rather than stored, so there is one source of truth for "what
/// language is this app in" and no way for the setting and the locale to
/// disagree. Text direction is deliberately *not* derived here: Flutter's
/// `GlobalWidgetsLocalizations` already reports Arabic as right-to-left, and
/// duplicating that decision is how the two end up out of step for the next
/// RTL language somebody adds.
final Provider<Locale> localeProvider = Provider<Locale>(
  (Ref ref) => ref.watch(appLanguageProvider).locale,
);
