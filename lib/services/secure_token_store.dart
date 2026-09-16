import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:scribble_guess/core/constants/storage_keys.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/services/preferences_store.dart';

/// Where the backend session token lives.
///
/// ## Why not `SharedPreferences`
///
/// The JWT from `POST /api/auth/guest` is a bearer credential: anything
/// holding it *is* the player for the thirty days it is valid, and it is the
/// only proof of the account their score and leaderboard history hang off.
/// `SharedPreferences` is a world-readable XML file on a rooted device and a
/// plain plist on iOS, so this keeps the token in the platform keystore —
/// EncryptedSharedPreferences on Android, the Keychain on iOS and macOS —
/// while ordinary preferences (theme, sound, the server override) stay where
/// they were.
///
/// ## Migration
///
/// Builds before this class wrote the token into preferences. [read] moves any
/// value it finds there into secure storage on the first call and deletes the
/// plaintext copy, so an upgrading player keeps their account without signing
/// in again.
///
/// ## Failure is not fatal
///
/// Keystore access genuinely fails on some devices — a corrupted Android
/// keystore after a restore is the common one, and `flutter_secure_storage`
/// throws rather than returning null. A player must still be able to play, so
/// every operation degrades to the preferences store instead of throwing. That
/// is a weaker guarantee than the keystore, and it is logged, but it is the
/// same guarantee this app shipped with before.
class SecureTokenStore {
  /// Creates a store, falling back to [fallback] when the keystore is unusable.
  SecureTokenStore({
    required PreferencesStore fallback,
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  })  : _fallback = fallback,
        _storage = storage;

  final PreferencesStore _fallback;
  final FlutterSecureStorage _storage;

  /// Set once the plaintext copy has been dealt with, so the migration below
  /// runs at most once per launch rather than on every token read.
  bool _migrated = false;

  /// The stored token, or `null` when this device has no session.
  Future<String?> read() async {
    await _migrateFromPreferences();

    try {
      final String? token = await _storage.read(key: StorageKeys.authToken);
      if (token != null && token.isNotEmpty) return token;
    } on Object catch (error, stackTrace) {
      AppLogger.w('SecureTokenStore: read failed', error, stackTrace);
      return _fallback.readString(StorageKeys.authToken);
    }

    // Nothing in the keystore. A value may still be sitting in preferences if
    // a previous write had to fall back.
    return _fallback.readString(StorageKeys.authToken);
  }

  /// Stores [token], replacing any previous one.
  Future<void> write(String token) async {
    if (token.isEmpty) {
      await delete();
      return;
    }

    try {
      await _storage.write(key: StorageKeys.authToken, value: token);
      // A fallback copy from an earlier failure would shadow this one on the
      // next read, so it goes now.
      await _fallback.remove(StorageKeys.authToken);
      _migrated = true;
    } on Object catch (error, stackTrace) {
      AppLogger.w(
        'SecureTokenStore: write failed; falling back to preferences',
        error,
        stackTrace,
      );
      await _fallback.writeString(StorageKeys.authToken, token);
    }
  }

  /// Forgets the token on this device, from both stores.
  Future<void> delete() async {
    try {
      await _storage.delete(key: StorageKeys.authToken);
    } on Object catch (error, stackTrace) {
      AppLogger.w('SecureTokenStore: delete failed', error, stackTrace);
    }
    await _fallback.remove(StorageKeys.authToken);
  }

  /// Moves a token written by an older build out of plaintext preferences.
  Future<void> _migrateFromPreferences() async {
    if (_migrated) return;
    _migrated = true;

    final String? legacy = _fallback.readString(StorageKeys.authToken);
    if (legacy == null || legacy.isEmpty) return;

    try {
      await _storage.write(key: StorageKeys.authToken, value: legacy);
      await _fallback.remove(StorageKeys.authToken);
      AppLogger.i('SecureTokenStore: moved the session token to the keystore.');
    } on Object catch (error, stackTrace) {
      // Leave the plaintext copy alone: losing it would sign the player out of
      // an account they cannot get back.
      AppLogger.w(
        'SecureTokenStore: could not migrate the token to the keystore',
        error,
        stackTrace,
      );
    }
  }
}
