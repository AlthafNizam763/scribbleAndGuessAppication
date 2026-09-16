/**
 * Unit tests for the pure rule ports.
 *
 * These are the algorithms the Flutter client also runs for prediction, so a
 * failure here means client and server would disagree about the outcome of a
 * game. Every expected number is derived from lib/domain/rules/*.dart.
 */

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { evaluate, levenshtein, normalize } from '../src/guess.js';
import { letterCount, maskWord, nextHintIndices } from '../src/hints.js';
import { createRandom, isValidRoomCode, newRoomCode, ROOM_CODE_ALPHABET, shuffleInPlace } from '../src/ids.js';
import { roundHalfAwayFromZero, ScoringConfig, ScoringService } from '../src/scoring.js';
import { gameStateJson, mayseeWord, standingsFrom, strokeJson } from '../src/serialize.js';
import { loadBank, parseBank, pickChoices, poolFor } from '../src/words.js';

const scoring = new ScoringService(ScoringConfig.standard);

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

describe('scoring: guesserPoints', () => {
  it('awards the full time component plus the first-guess bonus on an easy word', () => {
    // 30 + (100 - 30) * 1.0 = 100, + 25 first-guess bonus, * 1.0 easy.
    const points = scoring.guesserPoints({ msRemaining: 80000, msTotal: 80000, guessOrder: 1, difficulty: 'easy' });
    assert.equal(points, 125);
  });

  it('applies the difficulty multiplier last, rounding away from zero', () => {
    // (100 + 25) * 1.15 = 143.75 -> 144   |   * 1.35 = 168.75 -> 169
    assert.equal(scoring.guesserPoints({ msRemaining: 1000, msTotal: 1000, guessOrder: 1, difficulty: 'medium' }), 144);
    assert.equal(scoring.guesserPoints({ msRemaining: 1000, msTotal: 1000, guessOrder: 1, difficulty: 'hard' }), 169);
  });

  it('scales the time component linearly', () => {
    // Half the clock: 30 + 70 * 0.5 = 65, + 15 for second place.
    const points = scoring.guesserPoints({ msRemaining: 40000, msTotal: 80000, guessOrder: 2, difficulty: 'easy' });
    assert.equal(points, 80);
  });

  it('floors at minGuessPoints when the clock has run out', () => {
    assert.equal(scoring.guesserPoints({ msRemaining: 0, msTotal: 80000, guessOrder: 9, difficulty: 'easy' }), 30);
  });

  it('gives an order bonus only to the first three guessers', () => {
    const base = { msRemaining: 0, msTotal: 80000, difficulty: 'easy' };
    assert.equal(scoring.guesserPoints({ ...base, guessOrder: 1 }), 55);
    assert.equal(scoring.guesserPoints({ ...base, guessOrder: 2 }), 45);
    assert.equal(scoring.guesserPoints({ ...base, guessOrder: 3 }), 38);
    assert.equal(scoring.guesserPoints({ ...base, guessOrder: 4 }), 30);
  });

  it('coerces nonsensical input instead of throwing', () => {
    assert.equal(scoring.guesserPoints({ msRemaining: -5, msTotal: 0, guessOrder: 0, difficulty: 'nope' }), 55);
    assert.equal(
      scoring.guesserPoints({ msRemaining: 999999, msTotal: 1000, guessOrder: 1, difficulty: 'easy' }),
      125,
      'more time left than the turn lasted still clamps to a full clock',
    );
  });
});

describe('scoring: drawerPoints', () => {
  it('pays per guesser and adds the all-guessed bonus', () => {
    // 20 * 3 * 1.0 = 60, + 30 because nobody was left behind.
    assert.equal(scoring.drawerPoints({ correctGuessers: 3, totalGuessers: 3, difficulty: 'easy' }), 90);
  });

  it('omits the bonus when somebody did not guess', () => {
    assert.equal(scoring.drawerPoints({ correctGuessers: 2, totalGuessers: 3, difficulty: 'easy' }), 40);
  });

  it('caps at drawerMaxPoints', () => {
    // 20 * 4 * 1.15 = 92, + 30 = 122, capped to 120.
    assert.equal(scoring.drawerPoints({ correctGuessers: 4, totalGuessers: 4, difficulty: 'medium' }), 120);
  });

  it('pays nothing for a turn nobody guessed', () => {
    assert.equal(scoring.drawerPoints({ correctGuessers: 0, totalGuessers: 5, difficulty: 'hard' }), 0);
    assert.equal(scoring.drawerPoints({ correctGuessers: 3, totalGuessers: 0, difficulty: 'hard' }), 0);
  });

  it('clamps more correct guessers than there were guessers', () => {
    assert.equal(
      scoring.drawerPoints({ correctGuessers: 9, totalGuessers: 2, difficulty: 'easy' }),
      scoring.drawerPoints({ correctGuessers: 2, totalGuessers: 2, difficulty: 'easy' }),
    );
  });

  it('honours a custom ScoringConfig', () => {
    const tuned = new ScoringService(new ScoringConfig({ drawerPointsPerGuess: 5, drawerAllGuessedBonus: 0 }));
    assert.equal(tuned.drawerPoints({ correctGuessers: 2, totalGuessers: 2, difficulty: 'easy' }), 10);
  });
});

describe('scoring: rounding', () => {
  it('rounds halves away from zero, like Dart double.round()', () => {
    assert.equal(roundHalfAwayFromZero(2.5), 3);
    assert.equal(roundHalfAwayFromZero(-2.5), -3);
    assert.equal(roundHalfAwayFromZero(2.4), 2);
    assert.equal(roundHalfAwayFromZero(Number.NaN), 0);
  });
});

// ---------------------------------------------------------------------------
// Hints
// ---------------------------------------------------------------------------

describe('hints: maskWord', () => {
  it('blanks every letter of an unrevealed word', () => {
    assert.equal(maskWord('cat', []), '_ _ _');
  });

  it('always shows spaces and hyphens, and joins cells with a space', () => {
    assert.equal(maskWord('ice cream', [0]), 'i _ _   _ _ _ _ _');
    assert.equal(maskWord('t-shirt', []), '_ - _ _ _ _ _');
  });

  it('reveals exactly the given indices', () => {
    assert.equal(maskWord('elephant', [0, 7]), 'e _ _ _ _ _ _ t');
  });

  it('never spells the word out, because cells are space separated', () => {
    const word = 'elephant';
    const everything = [...word].map((_, index) => index);
    assert.equal(maskWord(word, everything), 'e l e p h a n t');
    assert.ok(!maskWord(word, everything).includes(word));
  });

  it('survives malformed input', () => {
    assert.equal(maskWord(null, null), '');
    assert.equal(maskWord('cat', ['x', 1]), '_ a _');
  });
});

describe('hints: letterCount', () => {
  it('counts only maskable characters', () => {
    assert.equal(letterCount('ice cream'), 8);
    assert.equal(letterCount('t-shirt'), 6);
    assert.equal(letterCount(''), 0);
  });
});

describe('hints: nextHintIndices', () => {
  const random = createRandom(7);

  it('reveals one more letter per hint number, cumulatively', () => {
    const first = nextHintIndices({ word: 'elephant', current: [], totalHints: 3, hintNumber: 1, random });
    const second = nextHintIndices({ word: 'elephant', current: first, totalHints: 3, hintNumber: 2, random });
    assert.equal(first.length, 1);
    assert.equal(second.length, 2);
    assert.ok(first.every((index) => second.includes(index)), 'hints only ever add letters');
  });

  it('never reveals more than half of the maskable positions', () => {
    const indices = nextHintIndices({ word: 'cat', current: [], totalHints: 5, hintNumber: 5, random });
    assert.equal(indices.length, 1, '3 letters -> cap of 1');
    const long = nextHintIndices({ word: 'elephant', current: [], totalHints: 9, hintNumber: 9, random });
    assert.equal(long.length, 4, '8 letters -> cap of 4');
  });

  it('never reveals a space or a hyphen', () => {
    const word = 'ice cream';
    const indices = nextHintIndices({ word, current: [], totalHints: 4, hintNumber: 4, random });
    assert.ok(indices.every((index) => word[index] !== ' ' && word[index] !== '-'));
  });

  it('returns a sorted list with no duplicates', () => {
    const indices = nextHintIndices({ word: 'lighthouse', current: [], totalHints: 4, hintNumber: 4, random });
    assert.deepEqual(indices, [...new Set(indices)].sort((a, b) => a - b));
  });

  it('drops indices that are not maskable positions of the word', () => {
    const indices = nextHintIndices({ word: 'cat', current: [99, -1], totalHints: 1, hintNumber: 1, random });
    assert.equal(indices.length, 1);
    assert.ok(indices[0] >= 0 && indices[0] < 3);
  });

  it('spreads reveals out instead of clustering them', () => {
    // With two hints on an 8 letter word, the second letter must not sit
    // right next to the first one.
    const first = nextHintIndices({ word: 'elephant', current: [], totalHints: 2, hintNumber: 1, random });
    const second = nextHintIndices({ word: 'elephant', current: first, totalHints: 2, hintNumber: 2, random });
    const added = second.find((index) => !first.includes(index));
    assert.ok(Math.abs(added - first[0]) > 1, `${added} should be far from ${first[0]}`);
  });

  it('returns zero indices when hints are switched off', () => {
    assert.deepEqual(nextHintIndices({ word: 'elephant', current: [], totalHints: 0, hintNumber: 1, random }), []);
  });
});

// ---------------------------------------------------------------------------
// Guess matching
// ---------------------------------------------------------------------------

describe('guess: evaluate', () => {
  it('matches ignoring case and surrounding whitespace', () => {
    assert.equal(evaluate('  CAT ', 'cat'), 'correct');
  });

  it('matches ignoring accents', () => {
    assert.equal(evaluate('Crème  Brûlée', 'creme brulee'), 'correct');
    assert.equal(evaluate('strasse', 'straße'), 'correct');
  });

  it('calls a one-edit typo close on a word of four letters or more', () => {
    assert.equal(evaluate('hous', 'house'), 'close');
    assert.equal(evaluate('housse', 'house'), 'close');
    assert.equal(evaluate('mouse', 'house'), 'close');
  });

  it('never calls anything close on a short word', () => {
    assert.equal(evaluate('ca', 'cat'), 'wrong');
    assert.equal(evaluate('bat', 'cat'), 'wrong');
  });

  it('is wrong for two or more edits', () => {
    assert.equal(evaluate('cta', 'cat'), 'wrong');
    assert.equal(evaluate('mice', 'house'), 'wrong');
  });

  it('treats blank input as wrong', () => {
    assert.equal(evaluate('', 'cat'), 'wrong');
    assert.equal(evaluate('   ', 'cat'), 'wrong');
    assert.equal(evaluate('cat', ''), 'wrong');
  });
});

describe('guess: normalize and levenshtein', () => {
  it('folds accents, collapses whitespace and lower-cases', () => {
    assert.equal(normalize('  Ünïcôrn   Ärt '), 'unicorn art');
    assert.equal(normalize('ß'), 'ss');
    assert.equal(normalize('ŒUF'), 'oeuf');
  });

  it('computes the textbook distances', () => {
    assert.equal(levenshtein('kitten', 'sitting'), 3);
    assert.equal(levenshtein('', 'abc'), 3);
    assert.equal(levenshtein('abc', 'abc'), 0);
    assert.equal(levenshtein('flaw', 'lawn'), 2);
  });
});

// ---------------------------------------------------------------------------
// Word bank and selection
// ---------------------------------------------------------------------------

describe('words: bank loading', () => {
  it('loads the bundled English asset', () => {
    const bank = loadBank('en');
    assert.ok(bank.all().length > 100, `expected a real word list, got ${bank.all().length}`);
    assert.ok(bank.all().every((word) => typeof word.text === 'string' && word.text.length > 0));
  });

  it('loads every bundled language', () => {
    for (const language of ['en', 'es', 'fr', 'de']) {
      assert.ok(loadBank(language).all().length > 50, `${language} bank looks empty`);
    }
  });

  it('falls back to English for an unknown language', () => {
    assert.equal(loadBank('klingon').language, 'en');
  });

  it('parses defensively, skipping unknown keys and blank words', () => {
    const bank = parseBank(
      {
        language: 'en',
        categories: {
          animals: { easy: ['cat', '  ', 42, 'dog'], impossible: ['x'] },
          notacategory: { easy: ['nope'] },
        },
      },
      'en',
    );
    assert.deepEqual(
      bank.all().map((word) => word.text),
      ['cat', 'dog'],
    );
  });

  it('deduplicates by lowercase text and honours the category filter', () => {
    const bank = parseBank(
      { language: 'en', categories: { animals: { easy: ['Cat', 'cat'] }, food: { easy: ['pie'] } } },
      'en',
    );
    assert.deepEqual(bank.wordsFor(['animals']).map((word) => word.text), ['Cat']);
    assert.equal(bank.wordsFor(['random']).length, 2);
    assert.equal(bank.wordsFor([]).length, 2);
  });
});

describe('words: pickChoices', () => {
  const settings = {
    wordMode: 'choose',
    language: 'en',
    categories: ['random'],
    customWords: [],
  };

  it('returns exactly the requested number of choices', () => {
    const random = createRandom(11);
    const choices = pickChoices({ pool: poolFor(settings), settings, usedWords: new Set(), count: 3, random });
    assert.equal(choices.length, 3);
  });

  it('is deterministic for a seeded generator', () => {
    const pool = poolFor(settings);
    const a = pickChoices({ pool, settings, usedWords: new Set(), count: 4, random: createRandom(99) });
    const b = pickChoices({ pool, settings, usedWords: new Set(), count: 4, random: createRandom(99) });
    assert.deepEqual(a, b);
  });

  it('skips words already used this game, case-insensitively', () => {
    const pool = poolFor(settings);
    const used = new Set(pool.slice(0, 100).map((word) => word.text.toUpperCase()));
    const choices = pickChoices({ pool, settings, usedWords: used, count: 5, random: createRandom(3) });
    assert.equal(choices.length, 5);
    for (const choice of choices) {
      assert.ok(!used.has(choice.text.toUpperCase()), `${choice.text} was already used`);
    }
  });

  it('honours the category filter', () => {
    const filtered = { ...settings, categories: ['animals'] };
    const choices = pickChoices({
      pool: poolFor(filtered),
      settings: filtered,
      usedWords: new Set(),
      count: 5,
      random: createRandom(5),
    });
    assert.equal(choices.length, 5);
    assert.ok(choices.every((choice) => choice.category === 'animals'));
  });

  it('mixes difficulties when it can', () => {
    const choices = pickChoices({
      pool: poolFor(settings),
      settings,
      usedWords: new Set(),
      count: 3,
      random: createRandom(21),
    });
    assert.equal(new Set(choices.map((choice) => choice.difficulty)).size, 3);
  });

  it('draws from customWords in custom mode', () => {
    const custom = {
      ...settings,
      wordMode: 'custom',
      customWords: ['flibbertigibbet', 'wobblesnark', 'quibblewick'],
    };
    const choices = pickChoices({ settings: custom, usedWords: new Set(), count: 3, random: createRandom(2) });
    assert.equal(choices.length, 3);
    assert.ok(choices.every((choice) => custom.customWords.includes(choice.text)));
    assert.ok(choices.every((choice) => choice.difficulty === 'medium'));
  });

  it('relaxes constraints rather than returning too few, padding as a last resort', () => {
    const tiny = [{ text: 'solo', category: 'objects', difficulty: 'easy' }];
    const choices = pickChoices({
      pool: tiny,
      settings,
      usedWords: new Set(['solo']),
      count: 3,
      random: createRandom(1),
    });
    assert.equal(choices.length, 3);
    assert.ok(choices.every((choice) => choice.text === 'solo'));
  });

  it('returns an empty list for an empty pool or a nonsensical count', () => {
    assert.deepEqual(pickChoices({ pool: [], settings, usedWords: new Set(), count: 3 }), []);
    assert.deepEqual(pickChoices({ pool: poolFor(settings), settings, usedWords: new Set(), count: 0 }), []);
  });
});

// ---------------------------------------------------------------------------
// Ids
// ---------------------------------------------------------------------------

describe('ids: room codes', () => {
  it('are five characters from the unambiguous alphabet', () => {
    for (let i = 0; i < 200; i++) {
      const code = newRoomCode();
      assert.equal(code.length, 5);
      assert.ok(isValidRoomCode(code));
      assert.ok(!/[O0I1]/.test(code), `${code} contains an ambiguous character`);
      assert.ok([...code].every((char) => ROOM_CODE_ALPHABET.includes(char)));
    }
  });

  it('rejects malformed codes and accepts lower case', () => {
    assert.ok(!isValidRoomCode('ABC'));
    assert.ok(!isValidRoomCode('ABCD0'));
    assert.ok(!isValidRoomCode(null));
    assert.ok(isValidRoomCode(newRoomCode().toLowerCase()));
  });

  it('shuffles deterministically for a seeded generator', () => {
    const a = shuffleInPlace([1, 2, 3, 4, 5, 6, 7, 8], createRandom(4));
    const b = shuffleInPlace([1, 2, 3, 4, 5, 6, 7, 8], createRandom(4));
    assert.deepEqual(a, b);
    assert.deepEqual([...a].sort((x, y) => x - y), [1, 2, 3, 4, 5, 6, 7, 8]);
  });
});

// ---------------------------------------------------------------------------
// Serialization and the word-secrecy gate
// ---------------------------------------------------------------------------

describe('serialize: word secrecy', () => {
  const state = {
    roomCode: 'ABCDE',
    phase: 'drawing',
    currentRound: 1,
    totalRounds: 3,
    turnIndex: 0,
    drawerId: 'drawer',
    word: 'lighthouse',
    maskedWord: '_ _ _ _ _ _ _ _ _ _',
    wordLength: 10,
    hintIndices: [],
    turnStartMs: 1,
    turnEndMs: 2,
    correctGuesserIds: [],
    roundScores: {},
    wordChoices: [{ text: 'lighthouse', category: 'places', difficulty: 'hard' }],
  };

  it('gives the word and the choices to the drawer', () => {
    const json = gameStateJson(state, 'drawer');
    assert.equal(json.word, 'lighthouse');
    assert.equal(json.wordChoices.length, 1);
  });

  it('withholds the word and the choices from everybody else while drawing', () => {
    for (const recipient of ['guesser', '', null, undefined]) {
      const json = gameStateJson(state, recipient);
      assert.equal(json.word, null, `recipient ${String(recipient)} must not see the word`);
      assert.deepEqual(json.wordChoices, []);
      assert.ok(!JSON.stringify(json).includes('lighthouse'));
    }
  });

  it('withholds the word during word selection too', () => {
    const selecting = { ...state, phase: 'wordSelection', word: null };
    assert.equal(gameStateJson(selecting, 'guesser').word, null);
    assert.deepEqual(gameStateJson(selecting, 'guesser').wordChoices, []);
  });

  it('reveals the word to everyone once the round ends', () => {
    const ended = { ...state, phase: 'roundEnd' };
    assert.equal(gameStateJson(ended, 'guesser').word, 'lighthouse');
    assert.ok(mayseeWord(ended, 'anyone'));
    assert.ok(!mayseeWord(state, 'anyone'));
  });

  it('keeps the masked word and the length available to guessers', () => {
    const json = gameStateJson(state, 'guesser');
    assert.equal(json.maskedWord, '_ _ _ _ _ _ _ _ _ _');
    assert.equal(json.wordLength, 10);
  });
});

describe('serialize: shapes the Dart models parse', () => {
  it('uses the compact stroke keys', () => {
    const json = strokeJson({
      id: 's1',
      authorId: 'p1',
      points: [{ x: 0.1, y: 0.2 }],
      colorValue: 123,
      width: 6,
      tool: 'eraser',
      timestampMs: 99,
    });
    assert.deepEqual(json, { id: 's1', a: 'p1', p: [[0.1, 0.2]], c: 123, w: 6, t: 'eraser', ts: 99 });
  });

  it('ranks standings descending, with ties sharing a rank', () => {
    const standings = standingsFrom([
      { id: 'a', name: 'Ann', avatarId: 0, avatarColorIndex: 0, score: 10 },
      { id: 'b', name: 'Bob', avatarId: 1, avatarColorIndex: 1, score: 30 },
      { id: 'c', name: 'Cid', avatarId: 2, avatarColorIndex: 2, score: 10 },
      { id: 'd', name: 'Dee', avatarId: 3, avatarColorIndex: 3, score: 5 },
    ]);
    assert.deepEqual(
      standings.map((row) => [row.playerId, row.score, row.rank]),
      [
        ['b', 30, 1],
        ['a', 10, 2],
        ['c', 10, 2],
        ['d', 5, 4],
      ],
    );
  });
});
