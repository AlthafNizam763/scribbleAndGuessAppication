import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/social.dart';

/// The room-invitation and room-browser payloads.
///
/// ## Why these live beside [UserCard] rather than inside `room.dart`
///
/// Every one of them is a *person or a room seen from outside it*. An
/// invitation is somebody else's room described to you; an invite candidate is
/// a friend annotated with facts about a room they are not in; a public room
/// row is what a stranger may know about one. None of them is the [Room] model
/// the game runs on, and putting them there would put "the room I am playing
/// in" and "a room I have been told about" behind one name.
///
/// ## They are read-only, and every flag on them is the server's
///
/// None of these has a `toJson`. Whether a friend can be invited, whether a
/// room has space, whether an invitation is still good — all of it is decided
/// on the server, and a client that could serialise one of these could be
/// asked to send its own answer back. The only thing this app ever sends about
/// a room or a friend is an id.
///
/// Every `fromJson` tolerates a missing or malformed field rather than
/// throwing, in the same style as the rest of `lib/models`: a list that drops
/// one bad row still renders.

/// Where an invitation stands.
enum RoomInvitationStatus {
  /// Sent, unanswered, and not yet past its deadline.
  pending('pending'),

  /// The invitee accepted it.
  accepted('accepted'),

  /// The invitee declined it.
  rejected('rejected'),

  /// Nobody answered in time, or the room it named went away.
  expired('expired');

  const RoomInvitationStatus(this.wire);

  /// The value used on the wire.
  final String wire;

  /// Parses [v] by wire value, falling back to [RoomInvitationStatus.pending].
  static RoomInvitationStatus fromName(String? v) =>
      asWireEnum(
        RoomInvitationStatus.values,
        v,
        (RoomInvitationStatus e) => e.wire,
      ) ??
      asEnum(RoomInvitationStatus.values, v) ??
      RoomInvitationStatus.pending;
}

/// An invitation to somebody else's room.
///
/// Carries everything the invitation card shows — who asked, which room, how
/// full it is, whether it is public — because the invitee is not in that room
/// and may not be allowed to read it. The numbers are a snapshot taken when
/// the list was read: the room can fill before the tap, which is exactly why
/// accepting is re-checked on the server rather than trusted from here.
class RoomInvitation extends Equatable {
  /// Creates an invitation.
  const RoomInvitation({
    this.id = '',
    this.roomId = '',
    this.roomCode = '',
    this.status = RoomInvitationStatus.pending,
    this.inviter = const UserCard(),
    this.playerCount = 0,
    this.maxPlayers = 0,
    this.isPublic = true,
    this.roomStatus = RoomStatus.waiting,
    this.createdAtMs = 0,
    this.expiresAtMs = 0,
  });

  /// Builds an invitation from a decoded JSON map.
  factory RoomInvitation.fromJson(Map<String, dynamic> json) => RoomInvitation(
        id: asString(json['id']),
        roomId: asString(json['roomId']),
        roomCode: asString(json['roomCode']),
        status: RoomInvitationStatus.fromName(asString(json['status'])),
        inviter: UserCard.fromJson(asMap(json['inviter'])),
        playerCount: asInt(json['playerCount']),
        maxPlayers: asInt(json['maxPlayers']),
        isPublic: asBool(json['isPublic'], true),
        roomStatus: RoomStatus.fromName(asString(json['roomStatus'])),
        createdAtMs: asInt(json['createdAtMs']),
        expiresAtMs: asInt(json['expiresAtMs']),
      );

  /// The invitation id, which is what accept and reject act on.
  final String id;

  /// The room this invitation points at.
  final String roomId;

  /// The shareable code, so the lobby can be reached without a second lookup.
  final String roomCode;

  /// Where the invitation stands.
  final RoomInvitationStatus status;

  /// Who sent it. Empty only when that account has since been deleted.
  final UserCard inviter;

  /// Seats taken when the invitation was read.
  final int playerCount;

  /// The room's cap.
  final int maxPlayers;

  /// Whether the room is listed publicly. A private room is still invitable.
  final bool isPublic;

  /// The room's coarse status when the invitation was read.
  final RoomStatus roomStatus;

  /// When it was sent.
  final int createdAtMs;

  /// When it stops being answerable.
  final int expiresAtMs;

  /// The occupancy line, e.g. `3/8 players`.
  String get occupancy => '$playerCount/$maxPlayers';

  /// Whether this invitation has lapsed according to the device clock.
  ///
  /// Used only to hide a card that is visibly stale — never to decide whether
  /// the tap is allowed. Device clocks drift and can move backwards, so the
  /// server's comparison against its own clock is the one that counts.
  bool get isLapsed =>
      expiresAtMs > 0 && DateTime.now().millisecondsSinceEpoch >= expiresAtMs;

  /// Whether this invitation is still worth drawing a button for.
  bool get isOpen => status == RoomInvitationStatus.pending && !isLapsed;

  @override
  List<Object?> get props => <Object?>[
        id,
        roomId,
        roomCode,
        status,
        inviter,
        playerCount,
        maxPlayers,
        isPublic,
        roomStatus,
        createdAtMs,
        expiresAtMs,
      ];

  @override
  bool get stringify => true;
}

/// A friend as the invite sheet draws them, annotated for one room.
///
/// The three booleans and [canInvite] are computed by the server, which is
/// the whole reason this is not just a [Friend]: whether somebody is seated,
/// already asked, or reachable at all are facts about the *room*, and a client
/// that worked them out itself would be deciding who it may invite.
class InviteCandidate extends Equatable {
  /// Creates a candidate.
  const InviteCandidate({
    this.card = const UserCard(),
    this.isOnline = false,
    this.isMember = false,
    this.isInvited = false,
    this.canInvite = false,
    this.blockedReason = '',
    this.lastSeenAtMs = 0,
  });

  /// Builds a candidate from a decoded JSON map.
  factory InviteCandidate.fromJson(Map<String, dynamic> json) => InviteCandidate(
        card: UserCard.fromJson(json),
        isOnline: asBool(json['isOnline']),
        isMember: asBool(json['isMember']),
        isInvited: asBool(json['isInvited']),
        canInvite: asBool(json['canInvite']),
        blockedReason: asString(json['blockedReason']),
        lastSeenAtMs: asInt(json['lastSeenAtMs']),
      );

  /// Who they are.
  final UserCard card;

  /// Whether they have a device connected right now.
  final bool isOnline;

  /// Whether they are already seated in this room.
  final bool isMember;

  /// Whether an unanswered invitation to this room already exists.
  final bool isInvited;

  /// Whether the Invite button may be offered at all.
  final bool canInvite;

  /// Why not, when [canInvite] is false. Empty otherwise.
  final String blockedReason;

  /// When they were last seen online.
  final int lastSeenAtMs;

  /// Returns a copy with the invited flag set, after a successful invite.
  ///
  /// Used only where the server has already confirmed the invitation and the
  /// row is avoiding a full reload to redraw — never to guess at a state the
  /// server has not agreed to.
  InviteCandidate asInvited() => InviteCandidate(
        card: card,
        isOnline: isOnline,
        isMember: isMember,
        isInvited: true,
        canInvite: false,
        blockedReason: blockedReason,
        lastSeenAtMs: lastSeenAtMs,
      );

  @override
  List<Object?> get props => <Object?>[
        card,
        isOnline,
        isMember,
        isInvited,
        canInvite,
        blockedReason,
        lastSeenAtMs,
      ];

  @override
  bool get stringify => true;
}

/// One row of the public room browser.
///
/// Note what is absent: the player list, the ban list and the word settings.
/// A browser row says who is hosting, how full the room is and roughly what
/// the rules are; anything more would be telling people about a room they have
/// not joined.
class PublicRoom extends Equatable {
  /// Creates a public room row.
  const PublicRoom({
    this.id = '',
    this.code = '',
    this.name = '',
    this.hostId = '',
    this.hostName = '',
    this.playerCount = 0,
    this.maxPlayers = 0,
    this.status = RoomStatus.waiting,
    this.rounds = 0,
    this.drawTimeSeconds = 0,
    this.language = AppLanguage.en,
    this.createdAtMs = 0,
  });

  /// Builds a row from a decoded JSON map.
  factory PublicRoom.fromJson(Map<String, dynamic> json) => PublicRoom(
        id: asString(json['id']),
        code: asString(json['code']),
        name: asString(json['name']),
        hostId: asString(json['hostId']),
        hostName: asString(json['hostName']),
        playerCount: asInt(json['playerCount']),
        maxPlayers: asInt(json['maxPlayers']),
        status: RoomStatus.fromName(asString(json['status'])),
        rounds: asInt(json['rounds']),
        drawTimeSeconds: asInt(json['drawTimeSeconds']),
        language: AppLanguage.fromName(asString(json['language'])),
        createdAtMs: asInt(json['createdAtMs']),
      );

  /// The room id, which is what the join call names.
  final String id;

  /// The shareable code.
  final String code;

  /// The room's display name, built by the server from the host's.
  final String name;

  /// Who is hosting.
  final String hostId;

  /// Their display name, already sanitised by the server.
  final String hostName;

  /// Seats taken when the list was read.
  final int playerCount;

  /// The room's cap.
  final int maxPlayers;

  /// The room's coarse status.
  final RoomStatus status;

  /// How many rounds the host chose.
  final int rounds;

  /// How long each turn runs.
  final int drawTimeSeconds;

  /// The word language.
  final AppLanguage language;

  /// When the room was opened.
  final int createdAtMs;

  /// The occupancy line, e.g. `3/8`.
  String get occupancy => '$playerCount/$maxPlayers';

  /// How many seats are left, by this snapshot.
  int get freeSeats => (maxPlayers - playerCount).clamp(0, maxPlayers);

  @override
  List<Object?> get props => <Object?>[
        id,
        code,
        name,
        hostId,
        hostName,
        playerCount,
        maxPlayers,
        status,
        rounds,
        drawTimeSeconds,
        language,
        createdAtMs,
      ];

  @override
  bool get stringify => true;
}

/// A room's membership, as `GET /api/rooms/:roomId/members` returns it.
///
/// Read by anybody already in the room. The live lobby normally renders from
/// the pushed room snapshot instead; this exists for the cold read — a screen
/// opened before the socket has finished its handshake.
class RoomMembers extends Equatable {
  /// Creates a membership snapshot.
  const RoomMembers({
    this.roomId = '',
    this.roomCode = '',
    this.hostId = '',
    this.playerCount = 0,
    this.maxPlayers = 0,
    this.status = RoomStatus.waiting,
    this.members = const <Player>[],
  });

  /// Builds a snapshot from a decoded JSON map.
  factory RoomMembers.fromJson(Map<String, dynamic> json) => RoomMembers(
        roomId: asString(json['roomId']),
        roomCode: asString(json['roomCode']),
        hostId: asString(json['hostId']),
        playerCount: asInt(json['playerCount']),
        maxPlayers: asInt(json['maxPlayers']),
        status: RoomStatus.fromName(asString(json['status'])),
        members: asList(json['members'])
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> row) => Player.fromJson(asMap(row)))
            .toList(growable: false),
      );

  /// The room.
  final String roomId;

  /// Its code.
  final String roomCode;

  /// Who is hosting.
  final String hostId;

  /// Seats taken.
  final int playerCount;

  /// The cap.
  final int maxPlayers;

  /// The room's coarse status.
  final RoomStatus status;

  /// Everybody seated.
  final List<Player> members;

  @override
  List<Object?> get props => <Object?>[
        roomId,
        roomCode,
        hostId,
        playerCount,
        maxPlayers,
        status,
        members,
      ];

  @override
  bool get stringify => true;
}
