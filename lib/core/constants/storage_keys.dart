/// Keys used with `SharedPreferences`.
///
/// Every key is namespaced with [prefix] so the app never collides with other
/// preferences stored by the platform or by plugins.
abstract final class StorageKeys {
  /// Namespace prepended to every key owned by this app.
  static const String prefix = 'sg.';

  /// JSON encoded `PlayerProfile` of the local player.
  static const String profile = '${prefix}profile';

  /// JSON encoded `AppSettings`.
  static const String settings = '${prefix}settings';

  /// JSON encoded list of `LeaderboardEntry`.
  static const String leaderboard = '${prefix}leaderboard';

  /// Code of the room that was joined last, offered as a quick rejoin.
  static const String lastRoomCode = '${prefix}lastRoomCode';

  /// The backend session token (JWT) from `POST /api/auth/guest`.
  ///
  /// This names an entry in the platform keystore rather than in
  /// `SharedPreferences` — see `SecureTokenStore`, which also migrates the
  /// plaintext copy older builds wrote under this same key.
  ///
  /// Deliberately left out of [all]: a local reset clears preferences, and
  /// dropping the token with them would strand the account that holds the
  /// player's score and leaderboard history behind a session they can no
  /// longer prove they own.
  static const String authToken = '${prefix}authToken';

  /// Version of the stored payload shapes, used to migrate or drop old data.
  static const String schemaVersion = '${prefix}schemaVersion';

  /// Schema version this build reads and writes.
  ///
  /// v2 dropped the old `http://localhost:3000` default out of the stored
  /// settings. It was written by every v1 install, so leaving it in place
  /// would have pinned upgraded devices to a loopback address instead of the
  /// deployed backend.
  static const int currentSchemaVersion = 2;

  /// The server address v1 shipped as its default.
  ///
  /// Only the v1 -> v2 migration reads this. It is matched exactly, so a
  /// player who deliberately types this address afterwards keeps it.
  static const String legacyDefaultServerUrl = 'http://localhost:3000';

  /// Every key owned by the app, for a full local reset.
  static const List<String> all = <String>[
    profile,
    settings,
    leaderboard,
    lastRoomCode,
    schemaVersion,
  ];
}
