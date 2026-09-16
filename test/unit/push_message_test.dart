import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/app_notification.dart';
import 'package:scribble_guess/models/push_message.dart';

/// The push payload, and what the app does with a malformed one.
///
/// ## Why the wire strings are pinned here
///
/// Because they are a contract with a codebase that is not compiled alongside
/// this one. The server writes `data.type` from
/// `PUSH_NOTIFICATION_TYPE.tournamentCheckInOpen` in
/// `constants/notification.constants.ts`, and `PushKind.parse` falls back to
/// [PushKind.unknown] rather than throwing — which is what keeps a notification
/// from a newer server harmless, and also what makes a *drift* completely
/// silent. Every check-in notification would open the app and go nowhere, and
/// nothing would report it. These tests are the thing that would notice.
///
/// Note that the two vocabularies are deliberately different: the push carries
/// `TOURNAMENT_CHECKIN_OPEN` and the inbox row carries
/// `tournament_checkin_open`. They come from different constants on the server
/// and travel on different channels, so both are pinned.
void main() {
  group('the push payload', () {
    test('parses the check-in notification the server sends', () {
      final PushMessage message = PushMessage.fromData(const <String, dynamic>{
        'type': 'TOURNAMENT_CHECKIN_OPEN',
        'tournamentId': '507f1f77bcf86cd799439011',
        'route': '/tournaments',
      });

      expect(message.kind, PushKind.tournamentCheckInOpen);
      expect(message.tournamentId, '507f1f77bcf86cd799439011');
      expect(message.route, '/tournaments');
      expect(message.hasTournament, isTrue);
      expect(message.isEmpty, isFalse);
    });

    test('matches the inbox row the same event writes', () {
      // The server writes both from one call site, so a build that understood
      // the push but not the row would open the tournament from a tap and
      // render a bell with no destination in the notification centre.
      expect(
        NotificationKind.parse('tournament_checkin_open'),
        NotificationKind.tournamentCheckInOpen,
      );
    });

    test('degrades to unknown for a kind this build has never heard of', () {
      final PushMessage message = PushMessage.fromData(const <String, dynamic>{
        'type': 'SOMETHING_INVENTED_LATER',
        'route': '/somewhere',
      });

      // Renders, and goes nowhere. That is what lets the server start sending
      // a new kind before every installed app can act on it.
      expect(message.kind, PushKind.unknown);
      expect(message.isEmpty, isFalse);
    });

    test('survives a payload with nothing in it', () {
      final PushMessage message = PushMessage.fromData(const <String, dynamic>{});

      expect(message.kind, PushKind.unknown);
      expect(message.tournamentId, isEmpty);
      expect(message.isEmpty, isTrue);
    });

    test('survives a payload whose fields are the wrong type', () {
      // FCM data values are always strings on the wire, but a notification can
      // arrive from a server older or newer than this build and nothing here
      // may throw on the way to opening a screen.
      final PushMessage message = PushMessage.fromData(const <String, dynamic>{
        'type': 42,
        'tournamentId': <String>['not', 'an', 'id'],
        'route': null,
      });

      expect(message.kind, PushKind.unknown);
      expect(message.hasTournament, isFalse);
    });

    test('reports a check-in with no id as unusable for navigation', () {
      final PushMessage message = PushMessage.fromData(const <String, dynamic>{
        'type': 'TOURNAMENT_CHECKIN_OPEN',
        'route': '/tournaments',
      });

      // The kind is known, so the listing still opens — but nothing tries to
      // push a detail screen for a tournament that was not named.
      expect(message.kind, PushKind.tournamentCheckInOpen);
      expect(message.hasTournament, isFalse);
    });
  });
}
