import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// One row of the final standings.
class PlayerScore extends Equatable {
  /// Creates a standings row.
  const PlayerScore({
    this.playerId = '',
    this.name = '',
    this.avatarId = 0,
    this.avatarColorIndex = 0,
    this.score = 0,
    this.rank = 0,
  });

  /// Builds a row from a decoded JSON map, tolerating malformed values.
  factory PlayerScore.fromJson(Map<String, dynamic> json) => PlayerScore(
        playerId: asString(json['playerId']),
        name: asString(json['name']),
        avatarId: asInt(json['avatarId']),
        avatarColorIndex: asInt(json['avatarColorIndex']),
        score: asInt(json['score']),
        rank: asInt(json['rank']),
      );

  /// Identifier of the player.
  final String playerId;

  /// Display name of the player.
  final String name;

  /// Index of the procedural doodle avatar, 0..11.
  final int avatarId;

  /// Index into the avatar colour palette, 0..7.
  final int avatarColorIndex;

  /// Final score of the player.
  final int score;

  /// One-based finishing position, where ties share a rank.
  final int rank;

  /// Serializes this row to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'playerId': playerId,
        'name': name,
        'avatarId': avatarId,
        'avatarColorIndex': avatarColorIndex,
        'score': score,
        'rank': rank,
      };

  /// Returns a copy with the given fields replaced.
  PlayerScore copyWith({
    String? playerId,
    String? name,
    int? avatarId,
    int? avatarColorIndex,
    int? score,
    int? rank,
  }) =>
      PlayerScore(
        playerId: playerId ?? this.playerId,
        name: name ?? this.name,
        avatarId: avatarId ?? this.avatarId,
        avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
        score: score ?? this.score,
        rank: rank ?? this.rank,
      );

  @override
  List<Object?> get props => <Object?>[
        playerId,
        name,
        avatarId,
        avatarColorIndex,
        score,
        rank,
      ];

  @override
  bool get stringify => true;
}
