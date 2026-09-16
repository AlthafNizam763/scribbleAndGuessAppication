import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/progression.dart';

/// Levels, XP and achievements, and their wire formats.
///
/// ## What these tests are for
///
/// The app computes none of this — every figure arrives from the server — so
/// what can go wrong here is parsing, not arithmetic. A field renamed on one
/// side would not throw; it would render a level-1 bar for a level-30 player,
/// and the symptom would be a player whose profile disagrees with the
/// leaderboard they are on.
///
/// So the payload shapes are pinned here, transcribed from the backend's
/// `progression.types.ts`, and the defaults are checked to be the ones that
/// are honest when a field is missing.
void main() {
  group('PlayerLevel', () {
    /// The `level` block the server sends inside `/api/progression/me`.
    Map<String, dynamic> payload() => <String, dynamic>{
          'level': 7,
          'title': 'Sketcher',
          'xp': 1200,
          'levelStartXp': 1000,
          'nextLevelXp': 1400,
          'xpIntoLevel': 200,
          'xpForNextLevel': 400,
          'progress': 0.5,
          'isMaxLevel': false,
        };

    test('parses a complete block', () {
      final PlayerLevel level = PlayerLevel.fromJson(payload());

      expect(level.level, 7);
      expect(level.title, 'Sketcher');
      expect(level.xp, 1200);
      expect(level.progress, 0.5);
      expect(level.isMaxLevel, isFalse);
      expect(level.progressLabel, '200 / 400 XP');
    });

    /// A brand-new account is level 1, not level 0. An empty payload has to
    /// produce that rather than a level the curve does not have.
    test('defaults to a level-1 account rather than a level-0 one', () {
      final PlayerLevel level = PlayerLevel.fromJson(const <String, dynamic>{});

      expect(level.level, 1);
      expect(level.xp, 0);
      expect(level.progress, 0);
    });

    test('clamps a progress value the server could never send', () {
      expect(
        PlayerLevel.fromJson(const <String, dynamic>{'progress': 4.2}).progress,
        1.0,
      );
      expect(
        PlayerLevel.fromJson(const <String, dynamic>{'progress': -1}).progress,
        0.0,
      );
    });

    /// At the cap there is no next level, so the label has to stop showing a
    /// denominator rather than printing `200 / null`.
    test('reads as a total at the maximum level', () {
      final PlayerLevel level = PlayerLevel.fromJson(const <String, dynamic>{
        'level': 50,
        'xp': 90000,
        'nextLevelXp': null,
        'xpForNextLevel': null,
        'progress': 1,
        'isMaxLevel': true,
      });

      expect(level.isMaxLevel, isTrue);
      expect(level.nextLevelXp, isNull);
      expect(level.progressLabel, '90000 XP');
    });
  });

  group('Achievement', () {
    Map<String, dynamic> payload({bool unlocked = false}) => <String, dynamic>{
          'key': 'hundred_guesses',
          'name': '100 Correct Guesses',
          'description': 'Read one hundred drawings correctly.',
          'xpReward': 200,
          'unlocked': unlocked,
          'unlockedAtMs': unlocked ? 1700000000000 : null,
          'progress': unlocked ? 100 : 43,
          'target': 100,
          'showProgress': true,
        };

    test('parses a locked entry with its progress', () {
      final Achievement entry = Achievement.fromJson(payload());

      expect(entry.key, 'hundred_guesses');
      expect(entry.unlocked, isFalse);
      expect(entry.unlockedAtMs, isNull);
      expect(entry.progress, 43);
      expect(entry.fraction, 0.43);
      expect(entry.progressLabel, '43 / 100');
    });

    test('parses an unlocked entry', () {
      final Achievement entry = Achievement.fromJson(payload(unlocked: true));

      expect(entry.unlocked, isTrue);
      expect(entry.unlockedAtMs, 1700000000000);
      expect(entry.fraction, 1.0);
    });

    test('never reports a fraction past one', () {
      final Achievement entry = Achievement.fromJson(const <String, dynamic>{
        'key': 'x',
        'progress': 4000,
        'target': 100,
      });

      expect(entry.fraction, 1.0);
    });

    test('survives a row with nothing in it', () {
      final Achievement entry = Achievement.fromJson(const <String, dynamic>{});

      expect(entry.isEmpty, isTrue);
      expect(entry.fraction, 0);
    });
  });

  group('AchievementsPage', () {
    test('drops entries with no key rather than rendering dead cards', () {
      final AchievementsPage page = AchievementsPage.fromJson(const <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'key': 'first_game', 'unlocked': true},
          <String, dynamic>{'name': 'nameless'},
          'not a map',
        ],
        'unlockedCount': 1,
        'totalCount': 12,
      });

      expect(page.items, hasLength(1));
      expect(page.unlockedCount, 1);
      expect(page.totalCount, 12);
    });

    test('filters the trophy case to what is actually unlocked', () {
      final AchievementsPage page = AchievementsPage.fromJson(const <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'key': 'a', 'unlocked': true},
          <String, dynamic>{'key': 'b', 'unlocked': false},
        ],
      });

      expect(page.unlocked.map((Achievement e) => e.key), <String>['a']);
    });

    test('defaults to an empty catalogue on a malformed response', () {
      final AchievementsPage page =
          AchievementsPage.fromJson(const <String, dynamic>{});

      expect(page.items, isEmpty);
      expect(page.unlockedCount, 0);
    });
  });

  group('MatchProgression', () {
    /// The `progression` block the server puts on `s:game:end`, per viewer.
    Map<String, dynamic> payload() => <String, dynamic>{
          'playerId': 'u-1',
          'xpEarned': 140,
          'level': <String, dynamic>{'level': 3, 'title': 'Beginner', 'xp': 480},
          'leveledUp': true,
          'unlocked': <dynamic>[
            <String, dynamic>{'key': 'first_win', 'name': 'First Win', 'unlocked': true},
          ],
        };

    test('parses a complete report', () {
      final MatchProgression report = MatchProgression.fromJson(payload());

      expect(report.playerId, 'u-1');
      expect(report.xpEarned, 140);
      expect(report.leveledUp, isTrue);
      expect(report.level.level, 3);
      expect(report.unlocked, hasLength(1));
      expect(report.isEmpty, isFalse);
    });

    /// A match the server declined to rank sends nothing. The result screen
    /// keys off `isEmpty` to decide whether to draw the payout card at all, so
    /// an absent report has to read as empty rather than as "+0 XP".
    test('reads an absent report as empty', () {
      final MatchProgression report =
          MatchProgression.fromJson(const <String, dynamic>{});

      expect(report.isEmpty, isTrue);
      expect(report.xpEarned, 0);
      expect(report.unlocked, isEmpty);
    });

    test('is not empty when it unlocked something but paid no match XP', () {
      final MatchProgression report = MatchProgression.fromJson(const <String, dynamic>{
        'xpEarned': 0,
        'unlocked': <dynamic>[
          <String, dynamic>{'key': 'first_game'},
        ],
      });

      expect(report.isEmpty, isFalse);
    });
  });

  group('XpEvent', () {
    test('parses a row and tells play apart from an achievement', () {
      final XpEvent fromPlay = XpEvent.fromJson(const <String, dynamic>{
        'id': 'x-1',
        'reason': 'correctGuess',
        'amount': 40,
        'count': 4,
        'balanceAfter': 480,
        'atMs': 1700000000000,
      });

      final XpEvent fromAchievement = XpEvent.fromJson(const <String, dynamic>{
        'id': 'x-2',
        'reason': 'achievement:first_win',
        'amount': 50,
      });

      expect(fromPlay.isAchievement, isFalse);
      expect(fromPlay.count, 4);
      expect(fromAchievement.isAchievement, isTrue);
    });

    test('survives a row with nothing in it', () {
      expect(XpEvent.fromJson(const <String, dynamic>{}).isEmpty, isTrue);
    });
  });

  group('Progression', () {
    test('parses level and achievements together', () {
      final Progression progression = Progression.fromJson(const <String, dynamic>{
        'level': <String, dynamic>{'level': 4, 'title': 'Beginner'},
        'achievements': <String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{'key': 'first_game', 'unlocked': true},
          ],
          'unlockedCount': 1,
          'totalCount': 12,
        },
      });

      expect(progression.level.level, 4);
      expect(progression.achievements.totalCount, 12);
    });

    test('defaults to a level-1 account with an empty catalogue', () {
      final Progression progression =
          Progression.fromJson(const <String, dynamic>{});

      expect(progression.level.level, 1);
      expect(progression.achievements.items, isEmpty);
    });
  });
}
