import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/player_stats.dart';
import 'package:scribble_guess/models/user_preferences.dart';

/// The account-owned half of Settings, and the profile figures beside it.
///
/// ## What is worth asserting here
///
/// Parsing and defaulting, because that is all the client does with either.
/// The one failure that would be invisible in a screenshot and expensive in
/// production is a *missing* key silently reading as `false`: every account
/// created before preferences existed sends no `preferences` object at all,
/// and treating that as "opted out of everything" would quietly stop every
/// notification for every existing player.
void main() {
  group('UserPreferences', () {
    test('an absent payload is fully opted in', () {
      final UserPreferences prefs =
          UserPreferences.fromJson(const <String, dynamic>{});

      // The shape every account had before this feature shipped.
      expect(prefs.notifyGameInvites, isTrue);
      expect(prefs.notifyFriendActivity, isTrue);
      expect(prefs.notifyRoomActivity, isTrue);
      expect(prefs.notifySystem, isTrue);
      expect(prefs.showOnlineStatus, isTrue);
      expect(prefs.discoverable, isTrue);
    });

    test('reads the switches the server actually sent', () {
      final UserPreferences prefs = UserPreferences.fromJson(const <String, dynamic>{
        'notifyGameInvites': false,
        'discoverable': false,
      });

      expect(prefs.notifyGameInvites, isFalse);
      expect(prefs.discoverable, isFalse);
      // Untouched keys keep the permissive default rather than following the
      // ones beside them.
      expect(prefs.notifySystem, isTrue);
      expect(prefs.showOnlineStatus, isTrue);
    });

    test('copyWith replaces only what it names', () {
      const UserPreferences before = UserPreferences();
      final UserPreferences after = before.copyWith(notifySystem: false);

      expect(after.notifySystem, isFalse);
      expect(after.notifyGameInvites, isTrue);
    });

    test('knows when every notification is off', () {
      const UserPreferences allOff = UserPreferences(
        notifyGameInvites: false,
        notifyFriendActivity: false,
        notifyRoomActivity: false,
        notifySystem: false,
      );

      // What the Settings screen keys its warning off: somebody who muted all
      // four has no other way to discover why nothing reaches them.
      expect(allOff.anyNotificationEnabled, isFalse);
      expect(
        allOff.copyWith(notifySystem: true).anyNotificationEnabled,
        isTrue,
      );
      // Privacy switches are not notifications and must not count.
      expect(
        allOff.copyWith(showOnlineStatus: true).anyNotificationEnabled,
        isFalse,
      );
    });
  });

  group('the profile breakdown', () {
    test('parses the online and bot split the server derived', () {
      final PlayerCareerStats career =
          PlayerCareerStats.fromJson(const <String, dynamic>{
        'gamesPlayed': 10,
        'botGamesPlayed': 4,
        'onlineGamesPlayed': 6,
      });

      expect(career.botGamesPlayed, 4);
      expect(career.onlineGamesPlayed, 6);
      // Derived server-side precisely so the two can never disagree with the
      // total the profile prints beside them.
      expect(
        career.botGamesPlayed + career.onlineGamesPlayed,
        career.gamesPlayed,
      );
    });

    test('parses the per-game tally in the order the server sent it', () {
      final PlayerCareerStats career =
          PlayerCareerStats.fromJson(const <String, dynamic>{
        'gamesByGameId': <Map<String, dynamic>>[
          <String, dynamic>{'gameId': 'SCRIBBLE_GUESS', 'played': 9},
          <String, dynamic>{'gameId': 'LUDO', 'played': 2},
        ],
      });

      // Ordering is the server's, so every client draws the same bars.
      expect(
        career.gamesByGameId.map((GameTally t) => t.gameId),
        <String>['SCRIBBLE_GUESS', 'LUDO'],
      );
      expect(career.gamesByGameId.first.displayName, 'Scribble & Guess');
    });

    test('still renders a game this build has never heard of', () {
      final PlayerCareerStats career =
          PlayerCareerStats.fromJson(const <String, dynamic>{
        'gamesByGameId': <Map<String, dynamic>>[
          <String, dynamic>{'gameId': 'SOME_FUTURE_GAME', 'played': 3},
        ],
      });

      final GameTally tally = career.gamesByGameId.single;

      // No catalogue entry, so no colour and no name — but the row still
      // appears with its count, rather than vanishing from the breakdown.
      expect(tally.game, isNull);
      expect(tally.played, 3);
      expect(tally.displayName, 'SOME_FUTURE_GAME');
    });

    test('an account with no finished games has an empty breakdown', () {
      final PlayerCareerStats career =
          PlayerCareerStats.fromJson(const <String, dynamic>{});

      // Zeroes are dropped server-side: five games listed at zero says nothing
      // about the player, and the profile shows its empty state instead.
      expect(career.gamesByGameId, isEmpty);
      expect(career.hasPlayed, isFalse);
    });
  });
}
