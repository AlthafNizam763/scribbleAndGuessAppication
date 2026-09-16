import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/social.dart';

/// One entry in the notification centre.
///
/// ## Read-only, like every other server-backed model
///
/// There is no `toJson` here and no endpoint that would accept one. Every
/// notification is written by the server from something that already happened,
/// so a client that could serialise one could be asked to put a row in
/// somebody else's inbox — which is the whole of what a spam feature needs.
/// The only thing this app sends about a notification is its id.
///
/// ## Why the type is an enum and the data is a map
///
/// The type decides the icon and where a tap goes, so it has to be a value
/// this app can switch on. What a given type *carries* differs completely
/// between them — a request id, a room code, an achievement key — so [data]
/// stays a map rather than eleven subclasses of one row.
///
/// An unrecognised type parses to [NotificationKind.unknown] and still renders
/// its stored title and body; it simply does nothing on tap. That is what lets
/// the server start sending a new kind before every installed app can act on
/// it.

/// What a notification is about.
///
/// The wire strings are the server's `NOTIFICATION_TYPE` values and must be
/// changed in lockstep with them.
enum NotificationKind {
  /// Somebody asked to be this player's friend.
  friendRequest('friend_request'),

  /// A request this player sent was accepted.
  friendRequestAccepted('friend_request_accepted'),

  /// A friend invited this player to their room.
  roomInvitation('room_invitation'),

  /// A friend started a game.
  friendStartedPlaying('friend_started_playing'),

  /// A friend took a seat in a room.
  friendJoinedRoom('friend_joined_room'),

  /// Somebody joined a room this player is in.
  userJoinedRoom('user_joined_room'),

  /// A game this player was in finished.
  gameResult('game_result'),

  /// An achievement was unlocked.
  achievementUnlocked('achievement_unlocked'),

  /// A daily challenge was completed.
  dailyChallengeCompleted('daily_challenge_completed'),

  /// A tournament was announced.
  tournamentAnnouncement('tournament_announcement'),

  /// A tournament this player registered for has opened check-in.
  ///
  /// The one kind that also arrives as a push, because it is the one with a
  /// deadline: a player who misses the window loses their place. `data`
  /// carries `tournamentId`.
  tournamentCheckInOpen('tournament_checkin_open'),

  /// A message from the operators.
  systemAnnouncement('system_announcement'),

  /// A kind this build does not know. Renders, but does nothing on tap.
  unknown('');

  const NotificationKind(this.wire);

  /// The string the server sends.
  final String wire;

  /// Parses [value], falling back to [unknown] rather than throwing.
  static NotificationKind parse(dynamic value) {
    final String raw = asString(value);

    for (final NotificationKind kind in NotificationKind.values) {
      if (kind.wire == raw) return kind;
    }

    return NotificationKind.unknown;
  }
}

/// A single notification row.
class AppNotification extends Equatable {
  /// Creates a notification.
  const AppNotification({
    this.id = '',
    this.kind = NotificationKind.unknown,
    this.title = '',
    this.body = '',
    this.actor,
    this.data = const <String, dynamic>{},
    this.isRead = false,
    this.createdAtMs = 0,
    this.readAtMs,
  });

  /// Builds a row from a decoded JSON map. Never throws.
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> actor = asMap(json['actor']);

    return AppNotification(
      id: asString(json['id']),
      kind: NotificationKind.parse(json['type']),
      title: asString(json['title']),
      body: asString(json['body']),
      actor: actor.isEmpty ? null : UserCard.fromJson(actor),
      data: asMap(json['data']),
      isRead: asBool(json['isRead']),
      createdAtMs: asInt(json['createdAtMs']),
      readAtMs: json['readAtMs'] == null ? null : asInt(json['readAtMs']),
    );
  }

  /// The server-issued row id, and the only thing this app sends back.
  final String id;

  /// What happened.
  final NotificationKind kind;

  /// The headline, written by the server.
  final String title;

  /// The supporting line, written by the server.
  final String body;

  /// Who caused it, or null for a system notification.
  final UserCard? actor;

  /// Ids the tap target needs. Never authoritative data — the screen it opens
  /// re-reads the real row over REST.
  final Map<String, dynamic> data;

  /// Whether this row has been opened.
  final bool isRead;

  /// When it was written, in server milliseconds.
  final int createdAtMs;

  /// When it was read, or null while unread.
  final int? readAtMs;

  /// Whether this refers to a real row.
  bool get isEmpty => id.isEmpty;

  /// A string field of [data], or empty when it is absent.
  String field(String key) => asString(data[key]);

  /// A copy marked read, for settling a row before the list re-reads.
  AppNotification asRead(int atMs) => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        actor: actor,
        data: data,
        isRead: true,
        createdAtMs: createdAtMs,
        readAtMs: readAtMs ?? atMs,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        kind,
        title,
        body,
        actor,
        isRead,
        createdAtMs,
        readAtMs,
      ];

  @override
  bool get stringify => true;
}

/// One page of the inbox, with the badge number alongside.
///
/// The count is carried by the same response as the rows so the badge never
/// needs a second request, and it is the *server's* number: this app never
/// adds one to its own last value, because a push it missed while backgrounded
/// would make that arithmetic permanently wrong.
class NotificationPage extends Equatable {
  /// Creates a page.
  const NotificationPage({
    this.items = const <AppNotification>[],
    this.unreadCount = 0,
    this.total = 0,
    this.page = 1,
    this.limit = 25,
    this.hasMore = false,
  });

  /// Builds a page from a decoded JSON map. Never throws.
  factory NotificationPage.fromJson(Map<String, dynamic> json) =>
      NotificationPage(
        items: <AppNotification>[
          for (final dynamic row in asList(json['items']))
            AppNotification.fromJson(asMap(row)),
        ]
            .where((AppNotification row) => !row.isEmpty)
            .toList(growable: false),
        unreadCount: asInt(json['unreadCount']),
        total: asInt(json['total']),
        page: asInt(json['page'], 1),
        limit: asInt(json['limit'], 25),
        hasMore: asBool(json['hasMore']),
      );

  /// The rows, newest first.
  final List<AppNotification> items;

  /// How many are unread across the whole inbox, capped by the server.
  final int unreadCount;

  /// How many rows the filter matches in total.
  final int total;

  /// This page's 1-based number.
  final int page;

  /// How many rows were asked for.
  final int limit;

  /// Whether another page follows.
  final bool hasMore;

  /// An empty inbox.
  static const NotificationPage empty = NotificationPage();

  /// A copy with [items] replaced and the count updated.
  NotificationPage copyWith({
    List<AppNotification>? items,
    int? unreadCount,
    int? total,
    int? page,
    bool? hasMore,
  }) =>
      NotificationPage(
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        total: total ?? this.total,
        page: page ?? this.page,
        limit: limit,
        hasMore: hasMore ?? this.hasMore,
      );

  @override
  List<Object?> get props =>
      <Object?>[items, unreadCount, total, page, limit, hasMore];

  @override
  bool get stringify => true;
}
