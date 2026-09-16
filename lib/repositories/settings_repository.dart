import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/app_settings.dart';

/// Persistence seam for device-local app preferences.
///
/// Holds [AppSettings]: sound, haptics, reduced motion, theme mode, server URL
/// and preferred language. These are client-side only and never leave the
/// device — they must not be confused with `RoomSettings`, which govern a
/// match and are owned by the server.
///
/// Backed by `shared_preferences` in the shipped implementation, so failures
/// are storage rather than network shaped.
abstract interface class SettingsRepository {
  /// Reads the stored settings, falling back to `AppSettings.defaults`.
  ///
  /// Never returns a [Result] and never throws: a missing key, an unknown
  /// enum name or a corrupt record falls back field by field, so the app can
  /// always boot with a usable configuration.
  Future<AppSettings> load();

  /// Writes [settings] as the new device configuration.
  ///
  /// `AppSettings.serverUrl` should be a valid absolute `http`/`https` origin;
  /// an implementation rejects anything else with [AppErrorCode.validation]
  /// rather than persisting an unusable endpoint. Fails with
  /// [AppErrorCode.storage] when the write itself fails.
  Future<Result<void>> save(AppSettings settings);
}
