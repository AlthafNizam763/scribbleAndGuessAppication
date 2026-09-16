import 'package:scribble_guess/core/constants/firebase_constants.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/services/functions_client.dart';

/// The result of creating or joining a room.
class RoomHandle {
  const RoomHandle({required this.roomId, required this.roomCode});

  /// Firestore document id, used for every subsequent call and subscription.
  final String roomId;

  /// The short code a player reads out to their friends.
  final String roomCode;
}

/// Room lifecycle and moderation, as calls to Cloud Functions (§10-12, §33).
///
/// Nothing here writes to Firestore directly. Every one of these is an
/// *intention* the server validates and then acts on, which is what makes the
/// anti-cheat model hold (§50).
class RoomService {
  RoomService(this._client);

  final FunctionsClient _client;

  /// Creates a room owned by the caller (§10).
  Future<RoomHandle> createRoom({
    required PlayerProfile profile,
    required RoomSettings settings,
  }) async {
    final Map<String, dynamic> result = await _client.call(
      FirebaseCallables.createRoom,
      <String, dynamic>{
        'displayName': profile.name,
        'avatarId': profile.avatarId,
        'avatarColorIndex': profile.avatarColorIndex,
        'settings': _settingsPayload(settings),
      },
    );
    return RoomHandle(
      roomId: asString(result['roomId']),
      roomCode: asString(result['roomCode']),
    );
  }

  /// Joins a room by code (§11).
  Future<RoomHandle> joinRoom({
    required String roomCode,
    required PlayerProfile profile,
  }) async {
    final Map<String, dynamic> result = await _client.call(
      FirebaseCallables.joinRoom,
      <String, dynamic>{
        'roomCode': roomCode,
        'displayName': profile.name,
        'avatarId': profile.avatarId,
        'avatarColorIndex': profile.avatarColorIndex,
      },
    );
    return RoomHandle(
      roomId: asString(result['roomId']),
      roomCode: asString(result['roomCode']),
    );
  }

  /// Leaves a room.
  Future<void> leaveRoom(String roomId) {
    return _client.call(
      FirebaseCallables.leaveRoom,
      <String, dynamic>{'roomId': roomId},
    );
  }

  /// Sets the caller's ready flag in the lobby.
  Future<void> setReady(String roomId, {required bool isReady}) {
    return _client.call(
      FirebaseCallables.updateReadyStatus,
      <String, dynamic>{'roomId': roomId, 'isReady': isReady},
    );
  }

  /// Replaces the room's rules. Host only (§13).
  Future<void> updateSettings(String roomId, RoomSettings settings) {
    return _client.call(
      FirebaseCallables.updateRoomSettings,
      <String, dynamic>{
        'roomId': roomId,
        'settings': _settingsPayload(settings),
      },
    );
  }

  /// Tells the server this client is still present (§35).
  Future<void> heartbeat(String roomId) {
    return _client.call(
      FirebaseCallables.heartbeat,
      <String, dynamic>{'roomId': roomId},
    );
  }

  // --- Moderation (§33-34) -------------------------------------------------

  Future<void> kickPlayer(String roomId, String targetUserId) {
    return _client.call(
      FirebaseCallables.kickPlayer,
      <String, dynamic>{'roomId': roomId, 'targetUserId': targetUserId},
    );
  }

  Future<void> banPlayer(String roomId, String targetUserId) {
    return _client.call(
      FirebaseCallables.banPlayer,
      <String, dynamic>{'roomId': roomId, 'targetUserId': targetUserId},
    );
  }

  Future<void> mutePlayer(
    String roomId,
    String targetUserId, {
    required bool muted,
  }) {
    return _client.call(
      FirebaseCallables.mutePlayer,
      <String, dynamic>{
        'roomId': roomId,
        'targetUserId': targetUserId,
        'muted': muted,
      },
    );
  }

  Future<void> reportPlayer(
    String roomId,
    String targetUserId,
    String reason,
  ) {
    return _client.call(
      FirebaseCallables.reportPlayer,
      <String, dynamic>{
        'roomId': roomId,
        'targetUserId': targetUserId,
        'reason': reason,
      },
    );
  }

  /// Casts a vote to remove a player, returning the running tally (§34).
  Future<VoteKickTally> voteKick(String roomId, String targetUserId) async {
    final Map<String, dynamic> result = await _client.call(
      FirebaseCallables.voteKick,
      <String, dynamic>{'roomId': roomId, 'targetUserId': targetUserId},
    );
    return VoteKickTally(
      votes: asInt(result['votes']),
      needed: asInt(result['needed']),
      removed: asBool(result['removed']),
    );
  }

  /// Hands the host badge to another player.
  Future<void> transferHost(String roomId, String targetUserId) {
    return _client.call(
      FirebaseCallables.transferHost,
      <String, dynamic>{'roomId': roomId, 'targetUserId': targetUserId},
    );
  }

  /// Serializes settings into the shape the backend validates.
  ///
  /// Enums travel as their wire names, and the field names are the server's
  /// (`wordsToChoose`, not `wordChoiceCount`) — the translation belongs here
  /// rather than leaking the backend's vocabulary into the model.
  Map<String, dynamic> _settingsPayload(RoomSettings settings) {
    return <String, dynamic>{
      'maxPlayers': settings.maxPlayers,
      'rounds': settings.rounds,
      'drawTimeSeconds': settings.drawTimeSeconds,
      'wordsToChoose': settings.wordChoiceCount,
      'hintsEnabled': settings.hintCount > 0,
      'hintCount': settings.hintCount,
      'wordSelectSeconds': settings.wordSelectSeconds,
      'wordMode': settings.wordMode.name,
      'language': settings.language.name,
      'categories': <String>[
        for (final WordCategory category in settings.categories) category.name,
      ],
      'allowVoteKick': settings.allowVoteKick,
      'isPrivate': settings.isPrivate,
    };
  }
}

/// The state of a vote-kick ballot after a vote was cast.
class VoteKickTally {
  const VoteKickTally({
    required this.votes,
    required this.needed,
    required this.removed,
  });

  /// Votes cast so far.
  final int votes;

  /// Votes required to remove the player.
  final int needed;

  /// Whether this vote was the one that removed them.
  final bool removed;
}
