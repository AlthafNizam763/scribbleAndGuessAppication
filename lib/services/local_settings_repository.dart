import 'package:scribble_guess/core/constants/storage_keys.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/repositories/settings_repository.dart';
import 'package:scribble_guess/services/preferences_store.dart';

/// Stores app preferences on the device.
///
/// Missing or unreadable settings fall back to [AppSettings.defaults] rather
/// than failing, so a bad write can never lock the player out of the app.
class LocalSettingsRepository implements SettingsRepository {
  const LocalSettingsRepository(this._store);

  final PreferencesStore _store;

  @override
  Future<AppSettings> load() async {
    final Map<String, dynamic>? json = _store.readObject(StorageKeys.settings);
    return json == null ? AppSettings.defaults : AppSettings.fromJson(json);
  }

  @override
  Future<Result<void>> save(AppSettings settings) =>
      _store.writeJson(StorageKeys.settings, settings.toJson());
}
