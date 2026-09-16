import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/features/notifications/notification_icons.dart';
import 'package:scribble_guess/models/app_notification.dart';

/// The notification model and its wire format.
///
/// ## Why the type strings are pinned here
///
/// Same argument as `room_invite_test.dart`: every `fromJson` in this app is
/// deliberately forgiving, so a *wrong* wire value fails silently rather than
/// throwing. A `friend_request` that parsed as [NotificationKind.unknown]
/// would render a row whose tap goes nowhere, and the symptom would be a
/// player tapping a notification that does nothing they can explain.
///
/// So the strings are transcribed from the backend's `NOTIFICATION_TYPE` and
/// the round-trip test catches a value renamed on one side and not the other.
void main() {
  group('NotificationKind wire format', () {
    test('parses the values the backend actually sends', () {
      expect(
        NotificationKind.parse('friend_request'),
        NotificationKind.friendRequest,
      );
      expect(
        NotificationKind.parse('friend_request_accepted'),
        NotificationKind.friendRequestAccepted,
      );
      expect(
        NotificationKind.parse('room_invitation'),
        NotificationKind.roomInvitation,
      );
      expect(
        NotificationKind.parse('achievement_unlocked'),
        NotificationKind.achievementUnlocked,
      );
      expect(
        NotificationKind.parse('system_announcement'),
        NotificationKind.systemAnnouncement,
      );
    });

    test('round-trips through its wire name', () {
      for (final NotificationKind kind in NotificationKind.values) {
        if (kind == NotificationKind.unknown) continue;
        expect(NotificationKind.parse(kind.wire), kind);
      }
    });

    /// The forward-compatibility rule: the server may start sending a kind
    /// this build has never heard of, and the row still has to render.
    test('falls back to unknown rather than throwing', () {
      expect(NotificationKind.parse(null), NotificationKind.unknown);
      expect(NotificationKind.parse('something_new'), NotificationKind.unknown);
      expect(NotificationKind.parse(42), NotificationKind.unknown);
    });

    test('gives an unknown kind a glyph but no destination', () {
      final NotificationLook look = lookFor(NotificationKind.unknown);
      expect(look.route, isNull);
    });

    test('gives every actionable kind somewhere to go', () {
      expect(lookFor(NotificationKind.friendRequest).route, isNotNull);
      expect(lookFor(NotificationKind.roomInvitation).route, isNotNull);
    });
  });

  group('AppNotification', () {
    /// The payload the server puts on `s:notification:new`.
    Map<String, dynamic> payload({Object? actor = _absent}) => <String, dynamic>{
          'id': 'n-1',
          'type': 'friend_request',
          'title': 'New friend request',
          'body': 'Bo wants to be your friend.',
          if (actor != _absent)
            'actor': actor
          else
            'actor': <String, dynamic>{
              'id': 'u-2',
              'username': 'Bo',
              'avatarId': 3,
              'avatarColorIndex': 4,
            },
          'data': <String, dynamic>{'requestId': 'req-1'},
          'isRead': false,
          'createdAtMs': 1700000000000,
          'readAtMs': null,
        };

    test('parses a complete row', () {
      final AppNotification row = AppNotification.fromJson(payload());

      expect(row.id, 'n-1');
      expect(row.kind, NotificationKind.friendRequest);
      expect(row.actor?.name, 'Bo');
      expect(row.isRead, isFalse);
      expect(row.readAtMs, isNull);
      expect(row.field('requestId'), 'req-1');
    });

    test('leaves the actor null on a system notification', () {
      final AppNotification row =
          AppNotification.fromJson(payload(actor: null));

      expect(row.actor, isNull);
    });

    test('survives a row with nothing in it', () {
      final AppNotification row =
          AppNotification.fromJson(const <String, dynamic>{});

      expect(row.isEmpty, isTrue);
      expect(row.kind, NotificationKind.unknown);
      expect(row.field('anything'), isEmpty);
    });

    test('marks a row read without losing its other fields', () {
      final AppNotification read = AppNotification.fromJson(payload())
          .asRead(1700000001000);

      expect(read.isRead, isTrue);
      expect(read.readAtMs, 1700000001000);
      expect(read.title, 'New friend request');
      expect(read.actor?.name, 'Bo');
    });
  });

  group('NotificationPage', () {
    test('drops rows with no id rather than rendering dead cards', () {
      final NotificationPage page =
          NotificationPage.fromJson(const <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'id': 'n-1', 'type': 'system_announcement'},
          <String, dynamic>{'type': 'system_announcement'},
          'not a map',
        ],
        'unreadCount': 3,
        'total': 2,
        'page': 1,
        'limit': 25,
        'hasMore': false,
      });

      expect(page.items, hasLength(1));
      expect(page.unreadCount, 3);
    });

    test('defaults to an empty inbox on a malformed response', () {
      final NotificationPage page =
          NotificationPage.fromJson(const <String, dynamic>{});

      expect(page.items, isEmpty);
      expect(page.unreadCount, 0);
      expect(page.page, 1);
      expect(page.hasMore, isFalse);
    });

    /// The count is the server's, so `copyWith` has to be able to replace it
    /// without touching the rows — that is the path every mutation takes.
    test('replaces the count without disturbing the rows', () {
      const AppNotification row = AppNotification(id: 'n-1');
      const NotificationPage page = NotificationPage(
        items: <AppNotification>[row],
        unreadCount: 5,
        total: 1,
      );

      final NotificationPage updated = page.copyWith(unreadCount: 0);

      expect(updated.unreadCount, 0);
      expect(updated.items, page.items);
      expect(updated.total, 1);
    });
  });
}

/// Sentinel for "this test did not pass an actor at all".
const Object _absent = Object();
