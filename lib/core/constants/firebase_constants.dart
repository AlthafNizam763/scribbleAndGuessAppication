/// Every Firestore path, document field and callable-function name the client
/// uses, in one place.
///
/// These strings are a contract with `functions/src` and `firestore.rules`.
/// Never inline a collection name or a callable name anywhere else: a typo in
/// a string literal fails at runtime, a typo here fails everywhere at once and
/// is caught by the first test that runs.
abstract final class FirebaseCollections {
  /// Player profiles. One document per authenticated uid.
  static const String users = 'users';

  /// Game rooms. One document per room, keyed by a generated room id.
  static const String rooms = 'rooms';

  /// Members of a room: `rooms/{roomId}/players/{userId}`.
  static const String players = 'players';

  /// Chat and guess feed: `rooms/{roomId}/messages/{messageId}`.
  static const String messages = 'messages';

  /// Per-round public record: `rooms/{roomId}/rounds/{roundNumber}`.
  static const String rounds = 'rounds';

  /// Server-only round secrets: `rooms/{roomId}/secret/{roundNumber}`.
  ///
  /// Holds the chosen word and the drawer's word choices. Firestore rules deny
  /// every client read of this subcollection unconditionally (§18) — only the
  /// Cloud Functions' admin credentials can see it.
  static const String secret = 'secret';

  /// Vote-kick ballots: `rooms/{roomId}/votes/{targetUserId}`.
  static const String votes = 'votes';

  /// Moderation reports, written by players and read only by admins.
  static const String reports = 'reports';

  /// The word bank: `words/{wordId}`.
  static const String words = 'words';

  /// Aggregated all-time standings: `leaderboard/{userId}`.
  static const String leaderboard = 'leaderboard';
}

/// Names of the callable Cloud Functions (§54).
///
/// Every one of these validates auth, payload, permission and room state
/// before it does anything (§50). The client only ever states an intention.
abstract final class FirebaseCallables {
  static const String createRoom = 'createRoom';
  static const String joinRoom = 'joinRoom';
  static const String leaveRoom = 'leaveRoom';
  static const String updateReadyStatus = 'updateReadyStatus';
  static const String updateRoomSettings = 'updateRoomSettings';
  static const String startGame = 'startGame';
  static const String selectWord = 'selectWord';
  static const String submitGuess = 'submitGuess';
  static const String sendMessage = 'sendMessage';
  static const String endRound = 'endRound';
  static const String nextRound = 'nextRound';
  static const String restartGame = 'restartGame';
  static const String kickPlayer = 'kickPlayer';
  static const String banPlayer = 'banPlayer';
  static const String mutePlayer = 'mutePlayer';
  static const String reportPlayer = 'reportPlayer';
  static const String voteKick = 'voteKick';
  static const String transferHost = 'transferHost';
  static const String heartbeat = 'heartbeat';
  static const String issueDrawingToken = 'issueDrawingToken';
}

/// Field names shared between the client, the rules and the functions.
///
/// Only fields the client actually reads or filters on need to appear here.
abstract final class FirebaseFields {
  // users/{userId}
  static const String userId = 'userId';
  static const String displayName = 'displayName';
  static const String avatarId = 'avatarId';
  static const String avatarColorIndex = 'avatarColorIndex';
  static const String photoUrl = 'photoUrl';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
  static const String lastSeenAt = 'lastSeenAt';
  static const String gamesPlayed = 'gamesPlayed';
  static const String gamesWon = 'gamesWon';
  static const String totalScore = 'totalScore';

  // rooms/{roomId}
  static const String roomCode = 'roomCode';
  static const String ownerId = 'ownerId';
  static const String status = 'status';
  static const String maxPlayers = 'maxPlayers';
  static const String currentPlayerCount = 'currentPlayerCount';
  static const String settings = 'settings';
  static const String game = 'game';
  static const String bannedUserIds = 'bannedUserIds';

  // rooms/{roomId}.game
  static const String currentRound = 'currentRound';
  static const String totalRounds = 'totalRounds';
  static const String currentDrawerId = 'currentDrawerId';
  static const String roundStatus = 'roundStatus';
  static const String roundStartedAt = 'roundStartedAt';
  static const String roundEndsAt = 'roundEndsAt';
  static const String maskedWord = 'maskedWord';
  static const String revealedWord = 'revealedWord';

  // rooms/{roomId}/players/{userId}
  static const String joinedAt = 'joinedAt';
  static const String isReady = 'isReady';
  static const String isConnected = 'isConnected';
  static const String score = 'score';
  static const String correctGuesses = 'correctGuesses';
  static const String hasGuessedCorrectly = 'hasGuessedCorrectly';
  static const String isMuted = 'isMuted';

  // rooms/{roomId}/messages/{messageId}
  static const String message = 'message';
  static const String type = 'type';

  // words/{wordId}
  static const String word = 'word';
  static const String category = 'category';
  static const String difficulty = 'difficulty';
  static const String language = 'language';
  static const String aliases = 'aliases';
}

/// Storage object paths (§52).
abstract final class StoragePaths {
  /// A player's uploaded avatar: `users/{userId}/avatar/avatar.jpg`.
  static String avatar(String userId) => 'users/$userId/avatar/avatar.jpg';

  /// Largest avatar the storage rules accept, in bytes.
  static const int maxAvatarBytes = 2 * 1024 * 1024;

  /// Content types the storage rules accept for an avatar.
  static const List<String> avatarContentTypes = <String>[
    'image/jpeg',
    'image/png',
    'image/webp',
  ];
}
