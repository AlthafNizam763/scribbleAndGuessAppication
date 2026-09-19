import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// How a discovered room must be joined.
///
/// The platform runs two room engines — the mature Scribble & Guess `Room`
/// service and the generic game platform — and a join sent to the wrong one is
/// refused. **The server decides this, not the client.** A client that mapped
/// game id to engine itself would be holding a copy of a server decision, and
/// would be the thing that broke the day a game moved between engines.
enum RoomJoinRoute {
  /// `POST /api/rooms/:roomId/join` — the Scribble & Guess engine.
  room('ROOM'),

  /// `POST /api/games/:gameId/rooms/:roomId/join` — the generic engine.
  gamePlatform('GAME_PLATFORM');

  const RoomJoinRoute(this.wire);

  /// The value the server sends.
  final String wire;

  /// Reads a wire value, defaulting to [RoomJoinRoute.room].
  ///
  /// An unknown route means this client is older than the server. Falling back
  /// to the Scribble engine is the safe end of that: the worst case is one
  /// refused join with a readable message, rather than a crash on a list the
  /// player only wanted to look at.
  static RoomJoinRoute fromWire(String value) {
    for (final RoomJoinRoute route in values) {
      if (route.wire == value) return route;
    }
    return RoomJoinRoute.room;
  }
}

/// One joinable public room in Quick Match, whatever game it belongs to.
///
/// Distinct from `PublicRoom`, which is the Scribble & Guess browser's richer
/// row — rounds, draw time, word language. None of that generalises: a Ludo
/// room has no draw time. What every game does have is a name, an occupancy
/// and a way in, and that is exactly what this carries.
class DiscoveredRoom extends Equatable {
  /// Creates a Quick Match row.
  const DiscoveredRoom({
    this.gameId,
    this.gameName = '',
    this.roomId = '',
    this.code = '',
    this.name = '',
    this.hostName = '',
    this.playerCount = 0,
    this.maxPlayers = 0,
    this.status = RoomStatus.waiting,
    this.createdAtMs = 0,
    this.joinVia = RoomJoinRoute.room,
  });

  /// Builds a row from a decoded JSON map.
  factory DiscoveredRoom.fromJson(Map<String, dynamic> json) => DiscoveredRoom(
    gameId: GameId.fromWire(asString(json['gameId'])),
    gameName: asString(json['gameName']),
    roomId: asString(json['roomId']),
    code: asString(json['code']),
    name: asString(json['name']),
    hostName: asString(json['hostName']),
    playerCount: asInt(json['playerCount']),
    maxPlayers: asInt(json['maxPlayers']),
    status: RoomStatus.fromName(asString(json['status'])),
    createdAtMs: asInt(json['createdAtMs']),
    joinVia: RoomJoinRoute.fromWire(asString(json['joinVia'])),
  );

  /// Which game this room is playing.
  ///
  /// Null when the server named a game this build does not know about, which
  /// is survivable: the row still renders with [gameName], and the join still
  /// works because [joinVia] came from the server too.
  final GameId? gameId;

  /// The game's display name, as the server spells it.
  ///
  /// Sent rather than looked up locally so a client one release behind still
  /// labels a new game correctly instead of showing a blank.
  final String gameName;

  /// The room id the join call names.
  final String roomId;

  /// The shareable code.
  final String code;

  /// The room's display name.
  final String name;

  /// Who opened it.
  final String hostName;

  /// Seats taken when the list was read.
  final int playerCount;

  /// The room's cap.
  final int maxPlayers;

  /// The room's coarse status.
  final RoomStatus status;

  /// When the room was opened.
  final int createdAtMs;

  /// Which engine to join through.
  final RoomJoinRoute joinVia;

  /// The occupancy line, e.g. `3/6`.
  String get occupancy => '$playerCount/$maxPlayers';

  /// Seats still open when the list was read.
  int get freeSeats => (maxPlayers - playerCount).clamp(0, maxPlayers);

  /// The catalogue entry for this row's game, when this build has one.
  GameDefinition? get game =>
      gameId == null ? null : GameCatalog.all.where((GameDefinition g) => g.gameId == gameId).firstOrNull;

  @override
  List<Object?> get props => <Object?>[
    gameId,
    gameName,
    roomId,
    code,
    name,
    hostName,
    playerCount,
    maxPlayers,
    status,
    createdAtMs,
    joinVia,
  ];
}

/// A page of Quick Match results.
class RoomDiscoveryPage extends Equatable {
  /// Creates a page.
  const RoomDiscoveryPage({
    this.items = const <DiscoveredRoom>[],
    this.currentRoomId = '',
    this.currentRoomCode = '',
  });

  /// Builds a page from a decoded JSON map.
  factory RoomDiscoveryPage.fromJson(Map<String, dynamic> json) =>
      RoomDiscoveryPage(
        items: asList(json['items'])
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> row) => DiscoveredRoom.fromJson(asMap(row)))
            .toList(growable: false),
        currentRoomId: asString(json['currentRoomId']),
        currentRoomCode: asString(json['currentRoomCode']),
      );

  /// The rooms, newest first.
  final List<DiscoveredRoom> items;

  /// The room the player already holds a seat in, if any.
  final String currentRoomId;

  /// Its code, for the "back to your room" action.
  final String currentRoomCode;

  /// Whether the player is already seated somewhere.
  ///
  /// The server refuses a second room outright, so the screen says so *before*
  /// the tap rather than letting somebody tap into a refusal.
  bool get isSeatedElsewhere => currentRoomId.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[items, currentRoomId, currentRoomCode];
}
