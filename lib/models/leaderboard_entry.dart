import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// A locally stored career record for one player.
class LeaderboardEntry extends Equatable {
  /// Creates a leaderboard entry.
  const LeaderboardEntry({
    this.playerId = '',
    this.name = '',
    this.avatarId = 0,
    this.avatarColorIndex = 0,
    this.totalScore = 0,
    this.gamesPlayed = 0,
    this.wins = 0,
    this.bestRoundScore = 0,
    this.updatedAtMs = 0,
  });

  /// Builds an entry from a decoded JSON map, tolerating malformed values.
  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        playerId: asString(json['playerId']),
        name: asString(json['name']),
        avatarId: asInt(json['avatarId']),
        avatarColorIndex: asInt(json['avatarColorIndex']),
        totalScore: asInt(json['totalScore']),
        gamesPlayed: asInt(json['gamesPlayed']),
        wins: asInt(json['wins']),
        bestRoundScore: asInt(json['bestRoundScore']),
        updatedAtMs: asInt(json['updatedAtMs']),
      );

  /// Identifier of the player the record belongs to.
  final String playerId;

  /// Display name last seen for the player.
  final String name;

  /// Index of the procedural doodle avatar, 0..11.
  final int avatarId;

  /// Index into the avatar colour palette, 0..7.
  final int avatarColorIndex;

  /// Points scored across every recorded game.
  final int totalScore;

  /// How many games were finished.
  final int gamesPlayed;

  /// How many games ended in first place.
  final int wins;

  /// Best single-round score ever recorded.
  final int bestRoundScore;

  /// Last update time in milliseconds since epoch.
  final int updatedAtMs;

  /// Serializes this entry to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'playerId': playerId,
        'name': name,
        'avatarId': avatarId,
        'avatarColorIndex': avatarColorIndex,
        'totalScore': totalScore,
        'gamesPlayed': gamesPlayed,
        'wins': wins,
        'bestRoundScore': bestRoundScore,
        'updatedAtMs': updatedAtMs,
      };

  /// Returns a copy with the given fields replaced.
  LeaderboardEntry copyWith({
    String? playerId,
    String? name,
    int? avatarId,
    int? avatarColorIndex,
    int? totalScore,
    int? gamesPlayed,
    int? wins,
    int? bestRoundScore,
    int? updatedAtMs,
  }) =>
      LeaderboardEntry(
        playerId: playerId ?? this.playerId,
        name: name ?? this.name,
        avatarId: avatarId ?? this.avatarId,
        avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
        totalScore: totalScore ?? this.totalScore,
        gamesPlayed: gamesPlayed ?? this.gamesPlayed,
        wins: wins ?? this.wins,
        bestRoundScore: bestRoundScore ?? this.bestRoundScore,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );

  @override
  List<Object?> get props => <Object?>[
        playerId,
        name,
        avatarId,
        avatarColorIndex,
        totalScore,
        gamesPlayed,
        wins,
        bestRoundScore,
        updatedAtMs,
      ];

  @override
  bool get stringify => true;
}
