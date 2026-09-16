import 'dart:convert';

import 'package:scribble_guess/core/constants/storage_keys.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A thin JSON layer over [SharedPreferences].
///
/// Every local repository funnels through here so that decoding failures,
/// schema drift and storage errors are handled once rather than in each
/// repository. A corrupt value is dropped rather than thrown: a broken
/// leaderboard should never stop the app from opening.
class PreferencesStore {
  const PreferencesStore(this._prefs);

  static const Failure _writeFailed = Failure(
    AppErrorCode.storage,
    'Could not write to local storage.',
  );

  final SharedPreferences _prefs;

  /// Opens the store and stamps the schema version on first run.
  static Future<PreferencesStore> open() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PreferencesStore store = PreferencesStore(prefs);
    await store._migrate();
    return store;
  }

  /// Reads a JSON object, or `null` when absent or unreadable.
  Map<String, dynamic>? readObject(String key) {
    final Object? decoded = _decode(key);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Reads a JSON array, or an empty list when absent or unreadable.
  List<Map<String, dynamic>> readObjectList(String key) {
    final Object? decoded = _decode(key);
    if (decoded is! List<dynamic>) {
      return const <Map<String, dynamic>>[];
    }
    return <Map<String, dynamic>>[
      for (final dynamic raw in decoded)
        if (raw is Map<String, dynamic>) raw,
    ];
  }

  /// Reads a plain string, or `null` when absent or empty.
  String? readString(String key) {
    final String? value = _prefs.getString(key);
    return value == null || value.isEmpty ? null : value;
  }

  /// Encodes [value] as JSON and stores it under [key].
  Future<Result<void>> writeJson(String key, Object value) async {
    try {
      final bool written = await _prefs.setString(key, jsonEncode(value));
      return written ? const Ok<void>(null) : const Err<void>(_writeFailed);
    } on Object catch (error, stackTrace) {
      AppLogger.e('PreferencesStore.writeJson($key)', error, stackTrace);
      return const Err<void>(_writeFailed);
    }
  }

  /// Stores a plain string under [key].
  Future<Result<void>> writeString(String key, String value) async {
    try {
      final bool written = await _prefs.setString(key, value);
      return written ? const Ok<void>(null) : const Err<void>(_writeFailed);
    } on Object catch (error, stackTrace) {
      AppLogger.e('PreferencesStore.writeString($key)', error, stackTrace);
      return const Err<void>(_writeFailed);
    }
  }

  /// Removes a single key.
  Future<Result<void>> remove(String key) async {
    try {
      await _prefs.remove(key);
      return const Ok<void>(null);
    } on Object catch (error, stackTrace) {
      AppLogger.e('PreferencesStore.remove($key)', error, stackTrace);
      return const Err<void>(_writeFailed);
    }
  }

  /// Clears every key this app owns, leaving other packages' keys alone.
  Future<Result<void>> clearAll() async {
    try {
      for (final String key in StorageKeys.all) {
        await _prefs.remove(key);
      }
      await _prefs.setInt(
        StorageKeys.schemaVersion,
        StorageKeys.currentSchemaVersion,
      );
      return const Ok<void>(null);
    } on Object catch (error, stackTrace) {
      AppLogger.e('PreferencesStore.clearAll', error, stackTrace);
      return const Err<void>(_writeFailed);
    }
  }

  Object? _decode(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(raw);
    } on FormatException catch (error) {
      AppLogger.w('Dropping unreadable value at $key: $error');
      unawaitedRemove(key);
      return null;
    }
  }

  /// Fire-and-forget cleanup of a value that failed to decode.
  void unawaitedRemove(String key) {
    _prefs.remove(key).ignore();
  }

  Future<void> _migrate() async {
    final int stored = _prefs.getInt(StorageKeys.schemaVersion) ?? 0;
    if (stored == StorageKeys.currentSchemaVersion) {
      return;
    }
    if (stored > StorageKeys.currentSchemaVersion) {
      // Storage written by a newer build. Start clean rather than guess.
      AppLogger.w('Storage schema v$stored is newer than this build.');
      await clearAll();
      return;
    }
    if (stored < 2) {
      await _dropLegacyServerUrl();
    }
    await _prefs.setInt(
      StorageKeys.schemaVersion,
      StorageKeys.currentSchemaVersion,
    );
  }

  /// Clears a stored server address that is only there because v1 wrote it.
  ///
  /// v1 shipped `http://localhost:3000` as the *default* value of
  /// `AppSettings.serverUrl`, so every install has it on disk whether or not
  /// the player ever opened the settings screen. That value overrides the
  /// build's configured backend, so an upgraded device would keep trying to
  /// reach a loopback address nothing is listening on.
  ///
  /// Only that exact string is removed, and only once. A player who genuinely
  /// wants to point at `localhost:3000` — anyone running the backend on the
  /// same machine — can still type it and it will stick.
  Future<void> _dropLegacyServerUrl() async {
    final Map<String, dynamic>? settings = readObject(StorageKeys.settings);
    if (settings == null) return;
    if (settings['serverUrl'] != StorageKeys.legacyDefaultServerUrl) return;

    settings.remove('serverUrl');
    AppLogger.i('Migrating settings to v2: dropped the v1 localhost default.');
    await writeJson(StorageKeys.settings, settings);
  }
}
