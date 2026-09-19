import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// The notification and privacy switches an **account** owns.
///
/// ## Why these are not in `AppSettings`
///
/// Because the server acts on them, and `AppSettings` never leaves the device.
/// A "do not send me friend activity" toggle stored locally is a toggle the
/// push service never sees: the notification is composed and delivered while
/// the app is closed, so a client-side filter would run on a phone that has
/// already buzzed. Visibility is the same shape of problem — whether a
/// stranger can see you are online is decided when *their* request is served.
///
/// Sound, music, haptics, reduced motion, theme and language stay in
/// `AppSettings`, because those are properties of a device rather than of a
/// person: somebody who mutes the game on a train has not asked for silence on
/// their tablet.
///
/// Every switch defaults to the permissive value, so an account that predates
/// this behaves exactly as it did.
class UserPreferences extends Equatable {
  /// Creates a preference set.
  const UserPreferences({
    this.notifyGameInvites = true,
    this.notifyFriendActivity = true,
    this.notifyRoomActivity = true,
    this.notifySystem = true,
    this.showOnlineStatus = true,
    this.discoverable = true,
  });

  /// Builds a set from a decoded JSON map. Missing keys take the default.
  factory UserPreferences.fromJson(Map<String, dynamic> json) => UserPreferences(
    notifyGameInvites: asBool(json['notifyGameInvites'], true),
    notifyFriendActivity: asBool(json['notifyFriendActivity'], true),
    notifyRoomActivity: asBool(json['notifyRoomActivity'], true),
    notifySystem: asBool(json['notifySystem'], true),
    showOnlineStatus: asBool(json['showOnlineStatus'], true),
    discoverable: asBool(json['discoverable'], true),
  );

  /// Push when somebody invites this player to a room.
  final bool notifyGameInvites;

  /// Push for friend requests and acceptances.
  final bool notifyFriendActivity;

  /// Push when a room this player is in needs them.
  final bool notifyRoomActivity;

  /// Announcements and maintenance notices.
  final bool notifySystem;

  /// Whether anybody but a friend may see this player as online.
  final bool showOnlineStatus;

  /// Whether this player appears in username search.
  final bool discoverable;

  /// A copy with the named switches replaced.
  UserPreferences copyWith({
    bool? notifyGameInvites,
    bool? notifyFriendActivity,
    bool? notifyRoomActivity,
    bool? notifySystem,
    bool? showOnlineStatus,
    bool? discoverable,
  }) => UserPreferences(
    notifyGameInvites: notifyGameInvites ?? this.notifyGameInvites,
    notifyFriendActivity: notifyFriendActivity ?? this.notifyFriendActivity,
    notifyRoomActivity: notifyRoomActivity ?? this.notifyRoomActivity,
    notifySystem: notifySystem ?? this.notifySystem,
    showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
    discoverable: discoverable ?? this.discoverable,
  );

  /// Whether any notification at all is enabled.
  ///
  /// What the Settings screen keys its "you have turned everything off" line
  /// off. Worth saying out loud: somebody who muted all four and then wonders
  /// why invitations never arrive has no other way to find out.
  bool get anyNotificationEnabled =>
      notifyGameInvites || notifyFriendActivity || notifyRoomActivity || notifySystem;

  @override
  List<Object?> get props => <Object?>[
    notifyGameInvites,
    notifyFriendActivity,
    notifyRoomActivity,
    notifySystem,
    showOnlineStatus,
    discoverable,
  ];
}
