import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { SCORING, TIMING } from '../config/constants';
import { createRandom } from '../utils/random';
import {
  sanitizeDisplayName,
  sanitizeMessage,
  sanitizeSettings,
} from '../utils/validation';
import { ScoringService, roundHalfAwayFromZero } from './scoringService';
import {
  BLANK,
  evaluateGuess,
  hintDueAtMs,
  letterCount,
  levenshtein,
  maskWord,
  nextHintIndices,
  normalize,
} from './wordService';

/**
 * Unit tests for the pure game rules (section 65).
 *
 * Everything here is deterministic: no Firestore, no clock, and any randomness
 * comes from a seeded generator. These are the rules that decide who wins, so
 * they are tested directly rather than only through the engine.
 */

const scoring = new ScoringService();
const MINUTE = 60_000;

describe('scoring: guesser points', () => {
  it('awards the maximum with the whole clock left', () => {
    const points = scoring.guesserPoints({
      msRemaining: MINUTE,
      msTotal: MINUTE,
      guessOrder: 1,
      difficulty: 'easy',
    });
    assert.equal(points, SCORING.maxGuessPoints + SCORING.orderBonuses[0]);
  });

  it('awards the minimum as the clock runs out', () => {
    const points = scoring.guesserPoints({
      msRemaining: 0,
      msTotal: MINUTE,
      guessOrder: 4,
      difficulty: 'easy',
    });
    assert.equal(points, SCORING.minGuessPoints);
  });

  it('pays the order bonus to the first three only', () => {
    const at = (order: number) =>
      scoring.guesserPoints({
        msRemaining: 0,
        msTotal: MINUTE,
        guessOrder: order,
        difficulty: 'easy',
      });
    assert.equal(at(1), SCORING.minGuessPoints + 50);
    assert.equal(at(2), SCORING.minGuessPoints + 30);
    assert.equal(at(3), SCORING.minGuessPoints + 20);
    assert.equal(at(4), SCORING.minGuessPoints);
    assert.equal(at(9), SCORING.minGuessPoints);
  });

  it('scales the whole award by difficulty', () => {
    const easy = scoring.guesserPoints({
      msRemaining: MINUTE,
      msTotal: MINUTE,
      guessOrder: 1,
      difficulty: 'easy',
    });
    const hard = scoring.guesserPoints({
      msRemaining: MINUTE,
      msTotal: MINUTE,
      guessOrder: 1,
      difficulty: 'hard',
    });
    assert.equal(hard, Math.round(easy * SCORING.difficultyMultiplier.hard));
  });

  it('decreases monotonically as time runs down', () => {
    let previous = Infinity;
    for (let left = MINUTE; left >= 0; left -= 5_000) {
      const points = scoring.guesserPoints({
        msRemaining: left,
        msTotal: MINUTE,
        guessOrder: 2,
        difficulty: 'medium',
      });
      assert.ok(points <= previous, `${points} should be <= ${previous}`);
      previous = points;
    }
  });

  it('never returns a negative award for nonsense input', () => {
    const points = scoring.guesserPoints({
      msRemaining: -1_000,
      msTotal: -1,
      guessOrder: -5,
      difficulty: 'nonexistent',
    });
    assert.ok(points >= 0);
  });
});

describe('scoring: drawer points', () => {
  it('pays nothing when nobody guessed', () => {
    assert.equal(
      scoring.drawerPoints({
        correctGuessers: 0,
        totalGuessers: 4,
        difficulty: 'easy',
      }),
      0
    );
  });

  it('pays per guesser', () => {
    assert.equal(
      scoring.drawerPoints({
        correctGuessers: 2,
        totalGuessers: 5,
        difficulty: 'easy',
      }),
      SCORING.drawerPointsPerGuess * 2
    );
  });

  it('adds the all-guessed bonus when nobody is left behind', () => {
    assert.equal(
      scoring.drawerPoints({
        correctGuessers: 3,
        totalGuessers: 3,
        difficulty: 'easy',
      }),
      SCORING.drawerPointsPerGuess * 3 + SCORING.drawerAllGuessedBonus
    );
  });

  it('caps the drawer award', () => {
    const points = scoring.drawerPoints({
      correctGuessers: 19,
      totalGuessers: 19,
      difficulty: 'hard',
    });
    assert.equal(points, SCORING.drawerMaxPoints);
  });

  it('never pays for more guessers than exist', () => {
    const inflated = scoring.drawerPoints({
      correctGuessers: 99,
      totalGuessers: 2,
      difficulty: 'easy',
    });
    const honest = scoring.drawerPoints({
      correctGuessers: 2,
      totalGuessers: 2,
      difficulty: 'easy',
    });
    assert.equal(inflated, honest);
  });
});

describe('scoring: rounding', () => {
  it('rounds halves away from zero, like Dart', () => {
    assert.equal(roundHalfAwayFromZero(2.5), 3);
    assert.equal(roundHalfAwayFromZero(-2.5), -3);
    assert.equal(roundHalfAwayFromZero(2.4), 2);
    assert.equal(roundHalfAwayFromZero(Number.NaN), 0);
  });
});

describe('guessing: normalisation', () => {
  it('lower-cases, trims and collapses whitespace', () => {
    assert.equal(normalize('  Ice   CREAM  '), 'ice cream');
  });

  it('folds Latin-1 accents', () => {
    assert.equal(normalize('Crème Brûlée'), 'creme brulee');
    assert.equal(normalize('jalapeño'), 'jalapeno');
    assert.equal(normalize('straße'), 'strasse');
  });

  it('drops punctuation', () => {
    assert.equal(normalize("don't!"), 'dont');
  });

  it('normalises full-width characters to their plain forms', () => {
    // A Japanese IME emits full-width Latin; it must match the plain form.
    assert.equal(normalize('ＲＯＣＫＥＴ'), 'rocket');
  });

  it('leaves non-Latin scripts intact', () => {
    assert.equal(normalize('  кошка '), 'кошка');
    assert.equal(normalize('ねこ'), 'ねこ');
  });
});

describe('guessing: verdicts', () => {
  it('accepts an exact match', () => {
    assert.equal(evaluateGuess('guitar', 'guitar'), 'correct');
  });

  it('ignores case, accents and spacing', () => {
    assert.equal(evaluateGuess('  GuiTar ', 'guitar'), 'correct');
    assert.equal(evaluateGuess('creme brulee', 'Crème Brûlée'), 'correct');
  });

  it('treats spacing and hyphens as insignificant', () => {
    assert.equal(evaluateGuess('air plane', 'airplane'), 'correct');
    assert.equal(evaluateGuess('airplane', 'air-plane'), 'correct');
  });

  it('accepts a configured alias', () => {
    assert.equal(evaluateGuess('plane', 'airplane', ['plane']), 'correct');
  });

  it('calls a one-letter typo close on a long enough word', () => {
    assert.equal(evaluateGuess('guitr', 'guitar'), 'close');
    assert.equal(evaluateGuess('guitars', 'guitar'), 'close');
  });

  it('does not call short words close', () => {
    // "cat" vs "bat" is a different animal, not a typo.
    assert.equal(evaluateGuess('bat', 'cat'), 'wrong');
  });

  it('rejects an empty guess', () => {
    assert.equal(evaluateGuess('   ', 'guitar'), 'wrong');
    assert.equal(evaluateGuess('guitar', ''), 'wrong');
  });

  it('computes edit distance symmetrically', () => {
    assert.equal(levenshtein('kitten', 'sitting'), 3);
    assert.equal(levenshtein('sitting', 'kitten'), 3);
    assert.equal(levenshtein('', 'abc'), 3);
    assert.equal(levenshtein('same', 'same'), 0);
  });
});

describe('hints: masking', () => {
  it('hides every letter before any hint', () => {
    assert.equal(maskWord('cat'), `${BLANK} ${BLANK} ${BLANK}`);
  });

  it('keeps spaces and hyphens visible', () => {
    const masked = maskWord('ice cream');
    assert.ok(masked.includes(' '));
    assert.equal(letterCount('ice cream'), 8);
    assert.equal(letterCount('air-plane'), 8);
  });

  it('reveals only the given indices', () => {
    assert.equal(maskWord('cat', [0]), `c ${BLANK} ${BLANK}`);
  });

  it('reveals the whole word when every index is given', () => {
    const all = [0, 1, 2];
    assert.equal(maskWord('cat', all), 'c a t');
  });
});

describe('hints: reveal schedule', () => {
  const random = () => createRandom(1234);

  it('reveals nothing for hint zero', () => {
    const indices = nextHintIndices({
      word: 'elephant',
      totalHints: 3,
      hintNumber: 0,
      random: random(),
    });
    assert.deepEqual(indices, []);
  });

  it('reveals one letter per hint', () => {
    for (let n = 1; n <= 3; n++) {
      const indices = nextHintIndices({
        word: 'elephant',
        totalHints: 3,
        hintNumber: n,
        random: random(),
      });
      assert.equal(indices.length, n);
    }
  });

  it('never reveals more than half the word', () => {
    const indices = nextHintIndices({
      word: 'cat',
      totalHints: 99,
      hintNumber: 99,
      random: random(),
    });
    assert.ok(indices.length <= 1, `revealed ${indices.length} of 3`);
  });

  it('only ever adds letters', () => {
    let current: number[] = [];
    for (let n = 1; n <= 4; n++) {
      const next = nextHintIndices({
        word: 'elephant',
        current,
        totalHints: 4,
        hintNumber: n,
        random: random(),
      });
      for (const index of current) {
        assert.ok(next.includes(index), `hint ${n} lost index ${index}`);
      }
      current = next;
    }
  });

  it('returns sorted, unique indices', () => {
    const indices = nextHintIndices({
      word: 'extraordinary',
      totalHints: 5,
      hintNumber: 5,
      random: random(),
    });
    assert.deepEqual(indices, [...new Set(indices)].sort((a, b) => a - b));
  });

  it('ignores indices that are not in the word', () => {
    const indices = nextHintIndices({
      word: 'cat',
      current: [99, -1],
      totalHints: 1,
      hintNumber: 1,
      random: random(),
    });
    assert.ok(indices.every((i) => i >= 0 && i < 3));
  });

  it('spreads hints across the middle of the turn', () => {
    const turn = 80_000;
    const first = hintDueAtMs(
      1,
      3,
      turn,
      TIMING.firstHintAtFraction,
      TIMING.lastHintAtFraction
    );
    const last = hintDueAtMs(
      3,
      3,
      turn,
      TIMING.firstHintAtFraction,
      TIMING.lastHintAtFraction
    );
    assert.ok(first > 0 && first < last && last < turn);
    assert.equal(first, Math.round(turn * TIMING.firstHintAtFraction));
    assert.equal(last, Math.round(turn * TIMING.lastHintAtFraction));
  });

  it('never schedules a hint when none are configured', () => {
    assert.equal(hintDueAtMs(1, 0, 80_000, 0.45, 0.85), Infinity);
  });
});

describe('validation: display names', () => {
  it('accepts an ordinary name', () => {
    assert.equal(sanitizeDisplayName('  Althaf '), 'Althaf');
  });

  it('strips markup characters', () => {
    assert.equal(sanitizeDisplayName('<script>Bob'), 'scriptBob');
  });

  it('strips zero-width characters used to clone a name', () => {
    // "Rahul" with a zero-width space spliced in must collapse to "Rahul",
    // so it cannot masquerade as a different player.
    assert.equal(sanitizeDisplayName('Rah​ul'), 'Rahul');
  });

  it('rejects a name that is too short once cleaned', () => {
    assert.throws(() => sanitizeDisplayName('​​A'));
  });

  it('rejects a name of pure punctuation', () => {
    assert.throws(() => sanitizeDisplayName('!!!!'));
  });

  it('rejects a non-string', () => {
    assert.throws(() => sanitizeDisplayName(42));
  });
});

describe('validation: messages', () => {
  it('collapses whitespace and trims', () => {
    assert.equal(sanitizeMessage('  hello   there '), 'hello there');
  });

  it('rejects an empty message', () => {
    assert.throws(() => sanitizeMessage('    '));
  });

  it('rejects an over-long message', () => {
    assert.throws(() => sanitizeMessage('x'.repeat(500)));
  });
});

describe('validation: room settings', () => {
  it('falls back to defaults for a junk payload', () => {
    const settings = sanitizeSettings({ maxPlayers: 'lots', rounds: -3 });
    assert.equal(settings.maxPlayers, 8);
    assert.equal(settings.rounds, 3);
  });

  it('keeps allowed discrete values', () => {
    const settings = sanitizeSettings({ maxPlayers: 12, rounds: 5 });
    assert.equal(settings.maxPlayers, 12);
    assert.equal(settings.rounds, 5);
  });

  it('rejects a max-player count that is not on the menu', () => {
    // 7 is not one of the offered sizes, so it must not survive.
    assert.equal(sanitizeSettings({ maxPlayers: 7 }).maxPlayers, 8);
  });

  it('clamps the draw time into range', () => {
    assert.equal(sanitizeSettings({ drawTimeSeconds: 9999 }).drawTimeSeconds, 180);
    assert.equal(sanitizeSettings({ drawTimeSeconds: 1 }).drawTimeSeconds, 30);
  });

  it('forces the hint count to zero when hints are off', () => {
    const settings = sanitizeSettings({ hintsEnabled: false, hintCount: 4 });
    assert.equal(settings.hintCount, 0);
  });

  it('drops unknown categories and never leaves the list empty', () => {
    const settings = sanitizeSettings({ categories: ['animals', 'wat'] });
    assert.deepEqual(settings.categories, ['animals']);
    assert.deepEqual(sanitizeSettings({ categories: ['nope'] }).categories, [
      'random',
    ]);
  });

  it('ignores unknown fields entirely', () => {
    const settings = sanitizeSettings({ isAdmin: true, score: 9999 });
    assert.ok(!('isAdmin' in settings));
    assert.ok(!('score' in settings));
  });

  it('falls back for an unsupported language', () => {
    assert.equal(sanitizeSettings({ language: 'klingon' }).language, 'en');
    assert.equal(sanitizeSettings({ language: 'ml' }).language, 'ml');
  });
});
