/// Immutable, app-wide constants that never change at runtime.
///
/// Anything tunable per room lives in `GameDefaults` instead.
abstract final class AppConstants {
  /// Human readable product name.
  static const String appName = 'Scribble & Guess';

  /// Marketing version of the client, mirrored in `pubspec.yaml`.
  static const String appVersion = '1.0.0';

  /// Aspect ratio the drawing surface is always laid out at.
  ///
  /// Stroke points are normalized against this box so a drawing looks
  /// identical on every device.
  static const double canvasAspectRatio = 4 / 3;

  /// Milliseconds between outgoing batches of freshly drawn stroke points.
  static const int strokeBatchMs = 60;

  /// Number of characters in a room code.
  static const int roomCodeLength = 5;

  /// Characters a room code may contain.
  ///
  /// Deliberately excludes `O`, `0`, `I` and `1` so codes can be read aloud
  /// and typed without ambiguity.
  static const String roomCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Shortest accepted player name, after trimming.
  static const int minNameLength = 2;

  /// Longest accepted player name, after trimming.
  static const int maxNameLength = 16;

  /// Longest accepted chat message, after trimming.
  static const int maxChatLength = 120;

  /// Number of procedural avatar characters, indexed `0..avatarCount - 1`.
  ///
  /// Split evenly across the three families in `AvatarKind`: people, animals
  /// and anime. Entries may be appended, never reordered, because an id is
  /// persisted with the profile and broadcast to every other player.
  static const int avatarCount = 18;

  /// Number of avatar colours, indexed `0..avatarColorCount - 1`.
  static const int avatarColorCount = 8;

  /// The value `AppSettings.serverUrl` holds when the player has not
  /// configured a server of their own.
  ///
  /// Empty rather than an address: an empty override means "use whatever this
  /// build was configured with", which is `AppConfig.deployedBackendUrl`
  /// unless `--dart-define=API_BASE_URL=...` says otherwise. Storing a
  /// concrete default here instead would pin the app to one origin and quietly
  /// beat the build-time define.
  static const String defaultServerUrl = '';

  /// How many times the socket transport retries before giving up.
  static const int reconnectAttempts = 8;

  /// Base delay between socket reconnection attempts, in milliseconds.
  static const int reconnectDelayMs = 1500;

  /// Ceiling on the reconnection backoff, in milliseconds.
  ///
  /// The delay grows exponentially from [reconnectDelayMs], so without a cap
  /// the last of [reconnectAttempts] tries would land minutes after the first.
  /// A player who walked through a dead spot mid-round needs the socket back
  /// in seconds, not after the round they were in has ended.
  static const int reconnectDelayMaxMs = 8000;

  /// Number of ping samples averaged into one clock-offset estimate.
  static const int timeSyncSamples = 5;

  /// Seconds between clock synchronisation rounds.
  static const int timeSyncIntervalSeconds = 20;

  /// Maximum chat messages kept in memory for a room.
  static const int chatHistoryLimit = 200;

  /// Hard cap on strokes retained by a single board, guarding memory use.
  static const int maxStrokesPerBoard = 4000;

  /// Ramer-Douglas-Peucker tolerance, in normalized canvas units.
  static const double simplifyTolerance = 0.0025;
}
