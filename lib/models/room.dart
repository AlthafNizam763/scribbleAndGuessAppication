import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/room_settings.dart';

/// A room and everyone seated in it, as broadcast on `s:room:state`.
class Room extends Equatable {
  /// Creates a room.
  const Room({
    this.id = '',
    this.code = '',
    this.hostId = '',
    this.players = const <Player>[],
    this.settings = RoomSettings.defaults,
    this.status = RoomStatus.waiting,
    this.createdAtMs = 0,
    this.bannedIds = const <String>[],
  });

  /// Builds a room from a decoded JSON map, tolerating malformed values.
  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: asString(json['id']),
        code: asString(json['code']),
        hostId: asString(json['hostId']),
        players: <Player>[
          for (final dynamic raw in asList(json['players']))
            Player.fromJson(asMap(raw)),
        ],
        settings: RoomSettings.fromJson(asMap(json['settings'])),
        status: RoomStatus.fromName(asString(json['status'])),
        createdAtMs: asInt(json['createdAtMs']),
        bannedIds: asStringList(json['bannedIds']),
      );

  /// Firestore document id. Stable for the life of the room, and the key
  /// every subcollection (players, messages, rounds) hangs off.
  final String id;

  /// Short shareable join code.
  final String code;

  /// Identifier of the player who owns the room.
  final String hostId;

  /// Everyone currently seated, in turn order.
  final List<Player> players;

  /// Rules the host configured.
  final RoomSettings settings;

  /// Lifecycle state of the room.
  final RoomStatus status;

  /// Creation time in milliseconds since epoch, on the server clock.
  final int createdAtMs;

  /// Identifiers the host banned from re-joining.
  final List<String> bannedIds;

  /// Returns the seated player with [id], or `null` when nobody matches.
  Player? playerById(String id) {
    for (final Player player in players) {
      if (player.id == id) return player;
    }
    return null;
  }

  /// Whether every seat is taken.
  bool get isFull => players.length >= settings.maxPlayers;

  /// Whether [id] identifies the host of this room.
  bool isHost(String id) => id.isNotEmpty && id == hostId;

  /// How many seated players pressed ready.
  int get readyCount {
    int count = 0;
    for (final Player player in players) {
      if (player.isReady) count++;
    }
    return count;
  }

  /// Serializes this room to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'hostId': hostId,
        'players': <Map<String, dynamic>>[
          for (final Player player in players) player.toJson(),
        ],
        'settings': settings.toJson(),
        'status': status.wire,
        'createdAtMs': createdAtMs,
        'bannedIds': <String>[...bannedIds],
      };

  /// Returns a copy with the given fields replaced.
  Room copyWith({
    String? id,
    String? code,
    String? hostId,
    List<Player>? players,
    RoomSettings? settings,
    RoomStatus? status,
    int? createdAtMs,
    List<String>? bannedIds,
  }) =>
      Room(
        id: id ?? this.id,
        code: code ?? this.code,
        hostId: hostId ?? this.hostId,
        players: players ?? this.players,
        settings: settings ?? this.settings,
        status: status ?? this.status,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        bannedIds: bannedIds ?? this.bannedIds,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        code,
        hostId,
        players,
        settings,
        status,
        createdAtMs,
        bannedIds,
      ];

  @override
  bool get stringify => true;
}
