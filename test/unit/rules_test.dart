import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/rules/guess_matcher.dart';
import 'package:scribble_guess/core/rules/hint_engine.dart';
import 'package:scribble_guess/core/rules/scoring.dart';
import 'package:scribble_guess/core/rules/turn_timer.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/room_settings.dart';

/// Unit tests for the pure client-side rules (§65).
///
/// These mirror the authoritative implementations in `functions/src`. The
/// client keeps them so it can render a prediction — the points a guess is
/// about to be worth, the mask a hint is about to reveal — without waiting for
/// a round trip. They must therefore agree with the server; where they cannot,
/// the server wins, and the test names say so.
void main() {
  group('TurnTimer', () {
    test('counts down from the server clock, not the device clock', () {
      // The whole point of these arguments: a device whose clock is an hour
      // fast must still show the same countdown as everyone else (§29).
      expect(
        TurnTimer.secondsRemaining(turnEndMs: 60000, serverNowMs: 30000),
        30,
      );
    });

    test('never reports negative time', () {
      expect(
        TurnTimer.secondsRemaining(turnEndMs: 1000, serverNowMs: 99999),
        0,
      );
      expect(
        TurnTimer.remaining(turnEndMs: 1000, serverNowMs: 99999),
        Duration.zero,
      );
    });

    test('rounds partial seconds up, so the clock never shows 0 too early', () {
      expect(
        TurnTimer.secondsRemaining(turnEndMs: 1500, serverNowMs: 1000),
        1,
      );
    });

    test('reports expiry only once the deadline has actually passed', () {
      expect(TurnTimer.isExpired(turnEndMs: 1000, serverNowMs: 999), isFalse);
      expect(TurnTimer.isExpired(turnEndMs: 1000, serverNowMs: 1000), isTrue);
    });

    test('progress stays within 0..1 for nonsensical spans', () {
      final double p = TurnTimer.progress(
        startMs: 100,
        endMs: 100,
        nowMs: 5000,
      );
      expect(p, inInclusiveRange(0.0, 1.0));
    });
  });

  group('GuessMatcher', () {
    test('accepts an exact match', () {
      expect(GuessMatcher.evaluate('guitar', 'guitar'), GuessVerdict.correct);
    });

    test('ignores case, padding and accents', () {
      expect(GuessMatcher.evaluate('  GUITAR ', 'guitar'), GuessVerdict.correct);
      expect(
        GuessMatcher.evaluate('creme brulee', 'crème brûlée'),
        GuessVerdict.correct,
      );
    });

    test('calls a single typo close on a long enough word', () {
      expect(GuessMatcher.evaluate('guitr', 'guitar'), GuessVerdict.close);
    });

    test('does not call a short different word close', () {
      expect(GuessMatcher.evaluate('bat', 'cat'), GuessVerdict.wrong);
    });

    test('treats an empty guess as wrong rather than throwing', () {
      expect(GuessMatcher.evaluate('', 'cat'), GuessVerdict.wrong);
      expect(GuessMatcher.evaluate('cat', ''), GuessVerdict.wrong);
    });

    test('normalises to a stable comparison key', () {
      expect(GuessMatcher.normalize('  Ice   CREAM '), 'ice cream');
    });

    test('edit distance is symmetric', () {
      expect(GuessMatcher.levenshtein('kitten', 'sitting'), 3);
      expect(GuessMatcher.levenshtein('sitting', 'kitten'), 3);
    });
  });

  group('HintEngine', () {
    test('masks every letter before a hint lands', () {
      expect(HintEngine.maskWord('cat', const <int>[]), '_ _ _');
    });

    test('keeps spaces visible without spending a hint on them', () {
      expect(HintEngine.letterCount('ice cream'), 8);
      expect(HintEngine.maskWord('ice cream', const <int>[]).contains('  '), isTrue);
    });

    test('reveals only the given indices', () {
      expect(HintEngine.maskWord('cat', const <int>[0]), 'c _ _');
    });

    test('never reveals more than half the word', () {
      final List<int> indices = HintEngine.nextHintIndices(
        word: 'cat',
        current: const <int>[],
        totalHints: 99,
        hintNumber: 99,
        random: Random(7),
      );
      expect(indices.length, lessThanOrEqualTo(1));
    });

    test('only ever adds letters as hints accumulate', () {
      List<int> current = <int>[];
      for (int n = 1; n <= 3; n++) {
        final List<int> next = HintEngine.nextHintIndices(
          word: 'elephant',
          current: current,
          totalHints: 3,
          hintNumber: n,
          random: Random(7),
        );
        expect(next, containsAll(current));
        current = next;
      }
    });
  });

  group('ScoringService', () {
    const ScoringService scoring = ScoringService();

    test('pays more for a faster guess', () {
      final int fast = scoring.guesserPoints(
        msRemaining: 60000,
        msTotal: 60000,
        guessOrder: 1,
        difficulty: WordDifficulty.easy,
      );
      final int slow = scoring.guesserPoints(
        msRemaining: 1000,
        msTotal: 60000,
        guessOrder: 1,
        difficulty: WordDifficulty.easy,
      );
      expect(fast, greaterThan(slow));
    });

    test('pays nothing to a drawer nobody guessed', () {
      expect(
        scoring.drawerPoints(
          correctGuessers: 0,
          totalGuessers: 4,
          difficulty: WordDifficulty.easy,
        ),
        0,
      );
    });

    test('never returns a negative award', () {
      expect(
        scoring.guesserPoints(
          msRemaining: -5,
          msTotal: -5,
          guessOrder: -1,
          difficulty: WordDifficulty.easy,
        ),
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('RoomSettings validation', () {
    test('the defaults are valid', () {
      expect(RoomSettings.defaults.validate(), isEmpty);
    });

    test('rejects an out-of-range round count', () {
      const RoomSettings settings = RoomSettings(rounds: 99);
      expect(settings.validate(), isNotEmpty);
    });

    test('rejects an empty category set', () {
      const RoomSettings settings = RoomSettings(categories: <WordCategory>{});
      expect(settings.validate(), isNotEmpty);
    });

    test('rejects a half-filled custom word list', () {
      const RoomSettings settings = RoomSettings(
        customWords: <String>['cat', 'dog'],
      );
      expect(settings.validate(), isNotEmpty);
    });

    test('accepts a custom list that is long enough', () {
      const RoomSettings settings = RoomSettings(
        customWords: <String>['cat', 'dog', 'fish', 'bird', 'cow'],
      );
      expect(settings.validate(), isEmpty);
    });
  });
}
