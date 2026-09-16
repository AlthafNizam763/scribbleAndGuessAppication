import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// The local identity of the person using the app, persisted between sessions
/// and sent to the server on every handshake.
class PlayerProfile extends Equatable {
  /// Creates a profile.
  const PlayerProfile({
    this.id = '',
    this.name = '',
    this.avatarId = 0,
    this.avatarColorIndex = 0,
  });

  /// Builds a profile from a decoded JSON map, tolerating malformed values.
  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
        id: asString(json['id']),
        name: asString(json['name']),
        avatarId: asInt(json['avatarId']),
        avatarColorIndex: asInt(json['avatarColorIndex']),
      );

  /// Stable client-generated identifier.
  final String id;

  /// Display name shown to other players.
  final String name;

  /// Index of the procedural character avatar, 0..17.
  final int avatarId;

  /// Index into the avatar colour palette, 0..7.
  final int avatarColorIndex;

  /// Serializes this profile to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'avatarId': avatarId,
        'avatarColorIndex': avatarColorIndex,
      };

  /// Returns a copy with the given fields replaced.
  PlayerProfile copyWith({
    String? id,
    String? name,
    int? avatarId,
    int? avatarColorIndex,
  }) =>
      PlayerProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        avatarId: avatarId ?? this.avatarId,
        avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
      );

  @override
  List<Object?> get props => <Object?>[id, name, avatarId, avatarColorIndex];

  @override
  bool get stringify => true;
}
