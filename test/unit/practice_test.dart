import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/rules/rules.dart';
import 'package:scribble_guess/features/practice/practice_session.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/models/words/fallback_words.dart';

/// Solo practice.
///
/// ## Why the engine is pure, and why that matters here
///
/// Practice is the one mode with no server to be authoritative, so every rule
/// it applies is applied by this device — the timer, the hints, the verdict,
/// the score. That makes it the mode where a logic bug is invisible: there is
/// nothing to disagree with it. So the engine takes a clock reading as an
/// argument rather than reading one, and every transition below is asserted
/// against a fixed clock.
void main() {
  const int start = 1700000000000;

  /// Settings with a predictable turn length and hint budget.
  const RoomSettings settings = RoomSettings(
    drawTimeSeconds: 60,
    hintCount: 2,
    wordChoiceCount: 3,
  );

  PracticeEngine engineWith({int seed = 7}) => PracticeEngine(
        bank: FallbackWords.bank(AppLanguage.en),
        random: Random(seed),
      );

  group('starting a session', () {
    test('opens on a choice of words', () {
      final PracticeSession session = engineWith().start(settings, start);

      expect(session.phase, PracticePhase.choosing);
      expect(session.choices, hasLength(settings.wordChoiceCount));
      expect(session.word, isNull);
      expect(session.score, 0);
      expect(session.roundsPlayed, 0);
    });

    /// Practice must work with no network and no assets loaded, so the bundled
    /// fallback is the expected source on a first run rather than an error.
    test('draws from the bundled bank with nothing loaded', () {
      final PracticeSession session = engineWith().start(settings, start);

      for (final WordItem choice in session.choices) {
        expect(choice.text, isNotEmpty);
      }
    });
  });

  group('taking a turn', () {
    test('starts the clock when a word is chosen', () {
      final PracticeEngine engine = engineWith();
      PracticeSession session = engine.start(settings, start);
      final WordItem word = session.choices.first;

      session = engine.choose(session, word, start);

      expect(session.phase, PracticePhase.drawing);
      expect(session.word, word);
      expect(session.turnStartMs, start);
      expect(session.turnEndMs, start + 60000);
      expect(session.choices, isEmpty);
      expect(session.secondsRemaining(start), 60);
    });

    test('masks the word until hints land', () {
      final PracticeEngine engine = engineWith();
      PracticeSession session = engine.start(settings, start);
      session = engine.choose(session, session.choices.first, start);

      // Nothing revealed at the top of the turn.
      expect(session.maskedWord, isNot(contains(session.word!.text)));
      expect(session.hintIndices, isEmpty);
    });

    /// Hints are derived from elapsed time rather than scheduled, so a session
    /// backgrounded mid-turn catches up on resume instead of silently skipping
    /// the hints it slept through.
    test('reveals hints as the clock runs down', () {
      final PracticeEngine engine = engineWith();
      PracticeSession session = engine.start(settings, start);
      session = engine.choose(session, session.choices.first, start);

      final PracticeSession early = engine.tick(session, start + 5000);
      expect(early.hintIndices, isEmpty);

      final PracticeSession late = engine.tick(session, start + 45000);
      expect(late.hintIndices, isNotEmpty);
    });

    test('catches up on hints after a long gap', () {
      final PracticeEngine engine = engineWith();
      PracticeSession session = engine.start(settings, start);
      session = engine.choose(session, session.choices.first, start);

      // Jumped straight to near the end, as a resumed app would.
      final PracticeSession resumed = engine.tick(session, start + 55000);

      expect(resumed.hintIndices.length, greaterThanOrEqualTo(1));
    });

    test('ends the turn when the clock expires', () {
      final PracticeEngine engine = engineWith();
      PracticeSession session = engine.start(settings, start);
      session = engine.choose(session, session.choices.first, start);

      final PracticeSession expired = engine.tick(session, start + 61000);

      expect(expired.phase, PracticePhase.finished);
      expect(expired.roundsPlayed, 1);
      // The word stays, because the finished screen shows it.
      expect(expired.word, isNotNull);
    });
  });

  group('guessing', () {
    PracticeSession drawing(PracticeEngine engine) {
      final PracticeSession session = engine.start(settings, start);
      return engine.choose(session, session.choices.first, start);
    }

    test('scores a correct guess and ends the turn', () {
      final PracticeEngine engine = engineWith();
      final PracticeSession session = drawing(engine);

      final PracticeSession won =
          engine.guess(session, session.word!.text, start + 10000);

      expect(won.phase, PracticePhase.finished);
      expect(won.score, greaterThan(0));
      expect(won.roundsPlayed, 1);
      expect(won.lastVerdict, GuessVerdict.correct);
    });

    /// Guessing early is worth more than guessing late, exactly as in a real
    /// turn — the same `ScoringService` decides both.
    test('pays more for a faster guess', () {
      // Two engines seeded identically, so both turns draw the same word and
      // the only difference between them is when the guess landed. Reusing one
      // engine would advance its random state and change the word.
      final PracticeSession early = drawing(engineWith());
      final PracticeSession later = drawing(engineWith());

      final PracticeSession fast =
          engineWith().guess(early, early.word!.text, start + 2000);
      final PracticeSession slow =
          engineWith().guess(later, later.word!.text, start + 55000);

      expect(fast.score, greaterThan(slow.score));
    });

    test('leaves the turn running after a wrong guess', () {
      final PracticeEngine engine = engineWith();
      final PracticeSession session = drawing(engine);

      final PracticeSession after =
          engine.guess(session, 'definitely not the word', start + 5000);

      expect(after.phase, PracticePhase.drawing);
      expect(after.score, 0);
      expect(after.lastVerdict, GuessVerdict.wrong);
    });

    test('ignores a guess outside a live turn', () {
      final PracticeEngine engine = engineWith();
      final PracticeSession choosing = engine.start(settings, start);

      expect(engine.guess(choosing, 'anything', start), choosing);
    });
  });

  group('moving on', () {
    test('offers fresh words and keeps the score', () {
      final PracticeEngine engine = engineWith();
      PracticeSession session = engine.start(settings, start);
      session = engine.choose(session, session.choices.first, start);
      session = engine.guess(session, session.word!.text, start + 5000);

      final int earned = session.score;
      final PracticeSession next = engine.next(session, start + 6000);

      expect(next.phase, PracticePhase.choosing);
      expect(next.choices, isNotEmpty);
      expect(next.word, isNull);
      expect(next.score, earned);
      expect(next.roundsPlayed, 1);
    });

    /// A short bundled bank would otherwise offer the same word every turn.
    test('remembers what has already been drawn', () {
      final PracticeEngine engine = engineWith();
      PracticeSession session = engine.start(settings, start);

      final WordItem first = session.choices.first;
      session = engine.choose(session, first, start);

      expect(session.usedWords, contains(first.text));
    });
  });
}
