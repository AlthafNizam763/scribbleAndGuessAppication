import 'package:flutter/foundation.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// How hard a Stupid plays, as the host chose it.
///
/// Wire values are the server's `BOT_DIFFICULTY` and are shouted, because the
/// backend enum is. The middle one is `NORMAL` on the wire and reads as
/// "Medium" to a player — the server's word and the player's word for the same
/// dial, which is why the label is not derived from the name.
enum BotDifficulty {
  easy('EASY', 'Easy'),
  medium('NORMAL', 'Medium'),
  hard('HARD', 'Hard');

  const BotDifficulty(this.wire, this.label);

  final String wire;
  final String label;

  static BotDifficulty fromWire(String value) {
    for (final BotDifficulty level in values) {
      if (level.wire == value.toUpperCase()) return level;
    }
    return BotDifficulty.medium;
  }
}

/// Where a platform room is in its life.
enum PlatformRoomStatus {
  waiting('waiting'),
  playing('playing'),
  completed('completed'),
  closed('closed');

  const PlatformRoomStatus(this.wire);
  final String wire;

  static PlatformRoomStatus fromWire(String value) {
    for (final PlatformRoomStatus status in values) {
      if (status.wire == value) return status;
    }
    return PlatformRoomStatus.waiting;
  }
}

/// One seat at the table — a person or a Stupid.
///
/// Mirrors the server's `PlatformPlayerState` exactly. A bot differs from a
/// person in three fields and nothing else: it has no [userId], it carries a
/// [botDifficulty], and [isBot] is set. Everything a seat needs in order to be
/// *drawn* — name, avatar, colour — is present either way, because the brief
/// is that a Stupid looks like a player apart from one small badge.
@immutable
class PlatformSeat {
  const PlatformSeat({
    required this.playerId,
    required this.userId,
    required this.username,
    required this.avatarId,
    required this.avatarColorIndex,
    required this.isBot,
    required this.botDifficulty,
    required this.isReady,
    required this.connected,
    required this.joinedAtMs,
  });

  factory PlatformSeat.fromJson(Map<String, dynamic> json) {
    final bool bot = asBool(json['isBot']);
    final String difficulty = asString(json['botDifficulty']);

    return PlatformSeat(
      playerId: asString(json['playerId']),
      userId: asString(json['userId']).isEmpty ? null : asString(json['userId']),
      username: asString(json['username']),
      avatarId: asInt(json['avatarId']),
      avatarColorIndex: asInt(json['avatarColorIndex']),
      isBot: bot,
      // Only meaningful on a bot seat. A person carries `null`, and reading a
      // difficulty off them would invent a fact about a human player.
      botDifficulty:
          bot && difficulty.isNotEmpty ? BotDifficulty.fromWire(difficulty) : null,
      isReady: asBool(json['isReady']),
      // Absent means present: the field is only written once somebody drops.
      connected: asBool(json['connected'], true),
      joinedAtMs: asInt(json['joinedAtMs']),
    );
  }

  final String playerId;

  /// The backend account behind this seat, or `null` for a Stupid.
  final String? userId;

  final String username;
  final int avatarId;
  final int avatarColorIndex;

  final bool isBot;

  /// How hard this Stupid plays. Always `null` on a human seat.
  final BotDifficulty? botDifficulty;

  final bool isReady;
  final bool connected;
  final int joinedAtMs;
}

/// A standing offer to play the same table again.
///
/// ## Why the client never decides anything about it
///
/// Whether there are enough players, whether the deadline has passed, whether
/// a bot should fill a gap and whether the match may start are all the
/// server's. This is what it decided, so a screen can show a countdown and a
/// tally of who has said yes.
@immutable
class RematchOffer {
  const RematchOffer({
    required this.open,
    required this.requestedBy,
    required this.deadlineAtMs,
    required this.accepted,
    required this.declined,
    required this.outcome,
  });

  static RematchOffer? fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return null;
    return RematchOffer(
      open: asBool(json['open']),
      requestedBy: asString(json['requestedBy']),
      deadlineAtMs: asInt(json['deadlineAtMs']),
      accepted: asStringList(json['accepted']),
      declined: asStringList(json['declined']),
      outcome: asString(json['outcome'], 'cancelled'),
    );
  }

  /// Still standing and still inside its deadline.
  final bool open;

  final String requestedBy;
  final int deadlineAtMs;
  final List<String> accepted;
  final List<String> declined;

  /// `open`, `started`, `failed` or `cancelled`.
  final String outcome;

  bool get started => outcome == 'started';
  bool get failed => outcome == 'failed';

  bool hasAccepted(String playerId) => accepted.contains(playerId);
  bool hasDeclined(String playerId) => declined.contains(playerId);

  /// Whether [playerId] still owes an answer.
  bool awaits(String playerId) =>
      open && !hasAccepted(playerId) && !hasDeclined(playerId);
}

/// A platform game room, as the server holds it.
///
/// The lobby's model and the gameplay screens' model are the same object on
/// purpose: the roster a player sees while waiting is the roster they play
/// against, and a second summary type would be a second thing to keep in step.
@immutable
class PlatformRoom {
  const PlatformRoom({
    required this.roomId,
    required this.roomCode,
    required this.gameId,
    required this.ownerId,
    required this.status,
    required this.isPrivate,
    required this.maxPlayers,
    required this.seats,
    required this.matchId,
    required this.createdAtMs,
    required this.rematch,
  });

  factory PlatformRoom.fromJson(Map<String, dynamic> json) {
    return PlatformRoom(
      roomId: asString(json['roomId']),
      roomCode: asString(json['roomCode']),
      gameId: GameId.fromWire(asString(json['gameId'])),
      ownerId: asString(json['ownerId']),
      status: PlatformRoomStatus.fromWire(asString(json['status'])),
      isPrivate: asBool(json['isPrivate']),
      maxPlayers: asInt(json['maxPlayers']),
      seats: <PlatformSeat>[
        for (final Object? row in asList(json['players']))
          if (row is Map) PlatformSeat.fromJson(asMap(row)),
      ],
      matchId: asString(json['matchId']),
      createdAtMs: asInt(json['createdAtMs']),
      rematch: RematchOffer.fromJson(asMap(json['rematch'])),
    );
  }

  final String roomId;
  final String roomCode;

  /// `null` when a build meets a room for a game it does not know about.
  final GameId? gameId;

  final String ownerId;
  final PlatformRoomStatus status;
  final bool isPrivate;
  final int maxPlayers;

  /// Every seat, in the order the server sent them. Stupids included.
  final List<PlatformSeat> seats;

  /// The running match, or empty while the room is still waiting.
  final String matchId;

  final int createdAtMs;

  /// The standing offer to play again, or null.
  final RematchOffer? rematch;

  /// Every seat, Stupids included — it is the room's occupancy.
  int get playerCount => seats.length;

  /// How many of those seats are Stupids.
  int get botCount => seats.where((PlatformSeat seat) => seat.isBot).length;

  /// How many are people.
  int get humanCount => playerCount - botCount;

  /// Seats still open.
  int get freeSeats => (maxPlayers - playerCount).clamp(0, maxPlayers);

  bool get hasMatch => matchId.isNotEmpty;

  /// Whether [playerId] owns this room, and so may seat bots and remove them.
  bool isOwner(String playerId) => ownerId == playerId;

  PlatformSeat? seatOf(String playerId) {
    for (final PlatformSeat seat in seats) {
      if (seat.playerId == playerId) return seat;
    }
    return null;
  }
}
