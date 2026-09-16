import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_mode.dart';
import 'package:scribble_guess/models/tournament.dart';

/// Tournaments and the interface-language setting.
///
/// ## What is worth pinning here
///
/// Every number on a tournament board is the server's, so there is no
/// arithmetic on this side to get wrong. What *can* be wrong is the parse: a
/// status that falls back to the wrong state would either offer a register
/// button on a finished event or hide one on an open event, and neither
/// throws. The fallback direction is the test.
void main() {
  group('tournament status parsing', () {
    test('parses every status the server writes', () {
      expect(
        TournamentStatus.fromName('announced'),
        TournamentStatus.announced,
      );
      expect(
        TournamentStatus.fromName('registering'),
        TournamentStatus.registering,
      );
      expect(TournamentStatus.fromName('live'), TournamentStatus.live);
      expect(TournamentStatus.fromName('finished'), TournamentStatus.finished);
    });

    /// An unrecognised status must land somewhere that offers the player
    /// *less*, not more. `announced` shows an event as not yet open; falling
    /// back to `live` would tell somebody their matches were counting when
    /// they were not.
    test('falls back conservatively on an unknown value', () {
      expect(TournamentStatus.fromName('seeding'), TournamentStatus.announced);
      expect(TournamentStatus.fromName(''), TournamentStatus.announced);
      expect(TournamentStatus.fromName(null), TournamentStatus.announced);
    });

    test('only the two open states accept entries', () {
      expect(TournamentStatus.registering.acceptsEntries, isTrue);
      // Registering mid-event is allowed on purpose: a points tournament has
      // no pairings to disturb.
      expect(TournamentStatus.live.acceptsEntries, isTrue);
      expect(TournamentStatus.announced.acceptsEntries, isFalse);
      expect(TournamentStatus.finished.acceptsEntries, isFalse);
    });

    test('only live counts matches', () {
      expect(TournamentStatus.live.isLive, isTrue);
      expect(TournamentStatus.registering.isLive, isFalse);
    });
  });

  group('Tournament.fromJson', () {
    test('reads a full row', () {
      final Tournament event = Tournament.fromJson(const <String, dynamic>{
        'id': 'abc',
        'name': 'Weekend Sprint',
        'description': 'Two hours, best total wins.',
        'format': 'points',
        'gameMode': 'speed',
        'categories': <String>['animals', 'food'],
        'status': 'live',
        'registerFromMs': 1000,
        'startsAtMs': 2000,
        'endsAtMs': 3000,
        'rewardXp': 250,
        'rewardBadgeKey': 'tournament_winner',
        'entrantCount': 42,
        'isRegistered': true,
        'winner': <String, dynamic>{
          'id': 'u1',
          'username': 'Nila',
          'avatarId': 3,
          'avatarColorIndex': 2,
        },
      });

      expect(event.id, 'abc');
      expect(event.name, 'Weekend Sprint');
      expect(event.gameMode, GameMode.speed);
      expect(event.categories, <WordCategory>[
        WordCategory.animals,
        WordCategory.food,
      ]);
      expect(event.status, TournamentStatus.live);
      expect(event.rewardXp, 250);
      expect(event.rewardBadgeKey, 'tournament_winner');
      expect(event.entrantCount, 42);
      expect(event.isRegistered, isTrue);
      expect(event.winner?.name, 'Nila');
    });

    /// A tournament that has not been closed has no winner, and an absent
    /// badge is null rather than the empty string — the card branches on null.
    test('leaves an unclosed event with no winner and no badge', () {
      final Tournament event = Tournament.fromJson(const <String, dynamic>{
        'id': 'abc',
        'name': 'Soon',
        'status': 'registering',
      });

      expect(event.winner, isNull);
      expect(event.rewardBadgeKey, isNull);
      expect(event.isRegistered, isFalse);
      expect(event.categories, isEmpty);
    });

    test('survives a malformed row rather than throwing', () {
      final Tournament event = Tournament.fromJson(const <String, dynamic>{
        'id': 42,
        'entrantCount': 'lots',
        'categories': 'animals',
        'winner': 'nobody',
      });

      expect(event.entrantCount, 0);
      expect(event.categories, isEmpty);
      expect(event.winner, isNull);
    });
  });

  group('TournamentBoard.fromJson', () {
    test('keeps the server ranks rather than re-deriving them', () {
      final TournamentBoard board = TournamentBoard.fromJson(const <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'u1',
            'username': 'Nila',
            'rank': 51,
            'score': 900,
            'matchesPlayed': 6,
            'matchesWon': 2,
            'isSelf': false,
          },
          <String, dynamic>{
            'id': 'u2',
            'username': 'Ravi',
            'rank': 52,
            'score': 880,
            'isSelf': true,
          },
        ],
        'total': 120,
        'page': 3,
        'hasMore': true,
      });

      // Absolute within the tournament, not within the page: a second-page row
      // that renumbered itself from 1 would be a different claim entirely.
      expect(board.items.first.rank, 51);
      expect(board.items.last.rank, 52);
      expect(board.items.last.isSelf, isTrue);
      expect(board.items.first.matchesWon, 2);
      expect(board.total, 120);
      expect(board.page, 3);
      expect(board.hasMore, isTrue);
    });

    test('an empty board is a page, not a failure', () {
      final TournamentBoard board =
          TournamentBoard.fromJson(const <String, dynamic>{});

      expect(board.items, isEmpty);
      expect(board.total, 0);
      expect(board.page, 1);
      expect(board.hasMore, isFalse);
    });
  });

  group('interface language', () {
    test('round-trips through settings JSON', () {
      const AppSettings settings = AppSettings(language: AppLanguage.ta);
      final AppSettings restored = AppSettings.fromJson(settings.toJson());

      expect(restored.language, AppLanguage.ta);
    });

    /// An install predating the setting has no `language` key at all, and must
    /// read as English rather than as whatever `asEnum` does with null.
    test('an older stored blob reads as English', () {
      final AppSettings restored = AppSettings.fromJson(const <String, dynamic>{
        'soundEnabled': false,
      });

      expect(restored.language, AppLanguage.en);
      expect(restored.soundEnabled, isFalse);
    });

    test('Arabic is the only right-to-left language', () {
      for (final AppLanguage language in AppLanguage.values) {
        expect(
          language.isRtl,
          language == AppLanguage.ar,
          reason: '${language.name} reported the wrong direction',
        );
      }
    });

    /// The locale is what `MaterialApp` resolves against, so it has to be the
    /// plain subtag the framework's delegates are registered under.
    test('maps each language to its locale', () {
      expect(AppLanguage.en.locale.languageCode, 'en');
      expect(AppLanguage.ta.locale.languageCode, 'ta');
      expect(AppLanguage.ar.locale.languageCode, 'ar');
    });

    test('every language has an endonym label', () {
      for (final AppLanguage language in AppLanguage.values) {
        expect(language.label, isNotEmpty);
      }
    });
  });
}
