import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// A player seated in a room, as broadcast by the server.
class Player extends Equatable {
  /// Creates a player.
  const Player({
    this.id = '',
    this.name = '',
    this.avatarId = 0,
    this.avatarColorIndex = 0,
    this.score = 0,
    this.roundScore = 0,
    this.isHost = false,
    this.isReady = false,
    this.isDrawing = false,
    this.hasGuessed = false,
    this.guessOrder,
    this.isMuted = false,
    this.connection = PlayerConnection.connected,
    this.isBot = false,
    this.botDifficulty,
  });

  /// Builds a player from a decoded JSON map, tolerating malformed values.
  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: asString(json['id']),
        name: asString(json['name']),
        avatarId: asInt(json['avatarId']),
        avatarColorIndex: asInt(json['avatarColorIndex']),
        score: asInt(json['score']),
        roundScore: asInt(json['roundScore']),
        isHost: asBool(json['isHost']),
        isReady: asBool(json['isReady']),
        isDrawing: asBool(json['isDrawing']),
        hasGuessed: asBool(json['hasGuessed']),
        guessOrder:
            json['guessOrder'] == null ? null : asInt(json['guessOrder']),
        isMuted: asBool(json['isMuted']),
        connection: PlayerConnection.fromName(asString(json['connection'])),
        isBot: asBool(json['isBot']),
        botDifficulty: asString(json['botDifficulty']).isEmpty
            ? null
            : asString(json['botDifficulty']),
      );

  /// Server-assigned identifier, unique inside the room.
  final String id;

  /// Display name shown to other players.
  final String name;

  /// Index of the procedural doodle avatar, 0..11.
  final int avatarId;

  /// Index into the avatar colour palette, 0..7.
  final int avatarColorIndex;

  /// Total score accumulated across the whole game.
  final int score;

  /// Points earned during the current round.
  final int roundScore;

  /// Whether this player owns the room.
  final bool isHost;

  /// Whether this player pressed ready in the lobby.
  final bool isReady;

  /// Whether this player is the drawer of the current turn.
  final bool isDrawing;

  /// Whether this player already guessed the word this turn.
  final bool hasGuessed;

  /// Position in the correct-guess order this turn, `null` until they guess.
  final int? guessOrder;

  /// Whether the host muted this player in chat.
  final bool isMuted;

  /// Realtime connection state reported by the server.
  final PlayerConnection connection;

  /// Whether this seat is an AI player rather than a person.
  ///
  /// Sent by the server on every seat in every room snapshot, not only in
  /// tournament matches — false for everybody in an ordinary room. It is here
  /// rather than inferred so that showing the badge is the easy thing and
  /// showing an AI as a person takes effort, which is the whole of "do not
  /// show AI bots as real humans" on this side of the wire.
  final bool isBot;

  /// `EASY`, `NORMAL` or `HARD` for an AI seat; null for a person.
  ///
  /// A raw string rather than an enum: it is only ever shown beside the badge,
  /// and an unrecognised value from a newer server should render as itself
  /// instead of being coerced into a difficulty the server did not send.
  final String? botDifficulty;

  /// Whether the player currently holds a live socket.
  bool get isConnected => connection == PlayerConnection.connected;

  /// Serializes this player to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'avatarId': avatarId,
        'avatarColorIndex': avatarColorIndex,
        'score': score,
        'roundScore': roundScore,
        'isHost': isHost,
        'isReady': isReady,
        'isDrawing': isDrawing,
        'hasGuessed': hasGuessed,
        'guessOrder': guessOrder,
        'isMuted': isMuted,
        'connection': connection.name,
        'isBot': isBot,
        'botDifficulty': botDifficulty,
      };

  /// Returns a copy with the given fields replaced. Pass `clearGuessOrder`
  /// to reset [guessOrder] back to `null`.
  Player copyWith({
    String? id,
    String? name,
    int? avatarId,
    int? avatarColorIndex,
    int? score,
    int? roundScore,
    bool? isHost,
    bool? isReady,
    bool? isDrawing,
    bool? hasGuessed,
    int? guessOrder,
    bool clearGuessOrder = false,
    bool? isMuted,
    PlayerConnection? connection,
    bool? isBot,
    String? botDifficulty,
  }) =>
      Player(
        id: id ?? this.id,
        name: name ?? this.name,
        avatarId: avatarId ?? this.avatarId,
        avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
        score: score ?? this.score,
        roundScore: roundScore ?? this.roundScore,
        isHost: isHost ?? this.isHost,
        isReady: isReady ?? this.isReady,
        isDrawing: isDrawing ?? this.isDrawing,
        hasGuessed: hasGuessed ?? this.hasGuessed,
        guessOrder: clearGuessOrder ? null : guessOrder ?? this.guessOrder,
        isMuted: isMuted ?? this.isMuted,
        connection: connection ?? this.connection,
        isBot: isBot ?? this.isBot,
        botDifficulty: botDifficulty ?? this.botDifficulty,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        avatarId,
        avatarColorIndex,
        score,
        roundScore,
        isHost,
        isReady,
        isDrawing,
        hasGuessed,
        guessOrder,
        isMuted,
        connection,
        isBot,
        botDifficulty,
      ];

  @override
  bool get stringify => true;
}
