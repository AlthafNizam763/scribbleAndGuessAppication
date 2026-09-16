import { getFirestore } from 'firebase-admin/firestore';

import {
  CLOSE_GUESS_MIN_LENGTH,
  Category,
  Difficulty,
  Language,
} from '../config/constants';
import { WordChoice, WordDoc } from '../models/types';
import { Random, shuffled, systemRandom } from '../utils/random';

/**
 * Everything about words: picking them, hiding them, and deciding whether a
 * guess matched one.
 *
 * The whole module is written so the answer never has to leave the server. The
 * only word-shaped thing a guesser's client ever receives is the mask produced
 * by {@link maskWord}, which is derived from the answer but cannot be inverted
 * (section 18).
 */

// ---------------------------------------------------------------------------
// Guess normalisation and matching (section 26)
// ---------------------------------------------------------------------------

/** Accent folding for the Latin-1 letters the word banks use. */
const ACCENT_FOLDING: Record<string, string> = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'å': 'a', 'æ': 'ae', 'ç': 'c', 'è': 'e', 'é': 'e',
  'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i',
  'ï': 'i', 'ð': 'd', 'ñ': 'n', 'ò': 'o', 'ó': 'o',
  'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'œ': 'oe',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y',
  'ÿ': 'y', 'þ': 'th', 'ß': 'ss',
};

/** How a guess compares to the answer. */
export type GuessVerdict = 'correct' | 'close' | 'wrong';

/**
 * The canonical form of `value` used for every comparison.
 *
 * Lower-cases, folds Latin-1 accents, strips punctuation that carries no
 * meaning in a one-word answer, and collapses whitespace. This is what makes
 * "Creme  Brulee!", "creme brulee" and "crème brûlée" the same guess, and what
 * lets an alias like "air plane" match the answer "airplane" once spaces are
 * also removed for the tight comparison below.
 *
 * NFKC normalisation runs first, which is what makes the non-Latin word banks
 * usable: it unifies the half-width and full-width forms a Japanese IME can
 * produce, and gives Devanagari and Malayalam a single canonical composition
 * for characters a keyboard may emit either pre-composed or as a base plus a
 * combining mark. Without it two visually identical guesses can compare
 * unequal, which to the player looks like the game simply refusing a correct
 * answer.
 */
export function normalize(value: unknown): string {
  const text = typeof value === 'string' ? value : String(value ?? '');
  let out = '';
  for (const char of text.normalize('NFKC').toLowerCase()) {
    out += ACCENT_FOLDING[char] ?? char;
  }
  return out
    // Punctuation is never significant in a guess. The second range covers the
    // CJK full-width equivalents, which an IME inserts instead of the ASCII.
    .replace(/[.,!?;:'"()[\]{}]/g, '')
    .replace(/[、。！）（，：；？]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** [normalize] with spaces and hyphens removed too. */
function tighten(value: string): string {
  return normalize(value).replace(/[\s-]/g, '');
}

/**
 * The Levenshtein edit distance between `a` and `b`.
 *
 * Iterative and two-row, so memory stays at O(min(len)) however long the
 * strings are.
 */
export function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  const aIsLonger = a.length >= b.length;
  const rows = aIsLonger ? a : b;
  const columns = aIsLonger ? b : a;
  const width = columns.length;

  let previous = new Array<number>(width + 1);
  for (let i = 0; i <= width; i++) previous[i] = i;
  let current = new Array<number>(width + 1).fill(0);

  for (let i = 1; i <= rows.length; i++) {
    current[0] = i;
    const rowUnit = rows.charCodeAt(i - 1);
    for (let j = 1; j <= width; j++) {
      const cost = rowUnit === columns.charCodeAt(j - 1) ? 0 : 1;
      current[j] = Math.min(
        previous[j - 1] + cost,
        previous[j] + 1,
        current[j - 1] + 1
      );
    }
    const swap = previous;
    previous = current;
    current = swap;
  }
  return previous[width];
}

/**
 * Grades `guess` against `word` and its `aliases`.
 *
 * A guess counts as correct when it matches the answer or any alias, with
 * spacing and hyphenation ignored. It counts as close - which earns a private
 * "you're close!" nudge but no points - when the answer is long enough that a
 * single-character typo is plausibly a near miss rather than a different word.
 */
export function evaluateGuess(
  guess: string,
  word: string,
  aliases: readonly string[] = []
): GuessVerdict {
  const g = normalize(guess);
  const w = normalize(word);
  if (g.length === 0 || w.length === 0) return 'wrong';

  const tightGuess = tighten(guess);
  const candidates = [word, ...aliases];
  for (const candidate of candidates) {
    const c = tighten(candidate);
    if (c.length > 0 && tightGuess === c) return 'correct';
  }

  if (w.length >= CLOSE_GUESS_MIN_LENGTH && levenshtein(g, w) === 1) {
    return 'close';
  }
  return 'wrong';
}

// ---------------------------------------------------------------------------
// Masking and hints (sections 18, 30)
// ---------------------------------------------------------------------------

/** The glyph standing in for a hidden letter. */
export const BLANK = '_';

/** Whether `char` is hidden until a hint reveals it. */
function isMaskable(char: string): boolean {
  return char !== ' ' && char !== '-';
}

/** Indices of `word` that can be hidden, ascending. */
function maskablePositions(word: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < word.length; i++) {
    if (isMaskable(word[i])) out.push(i);
  }
  return out;
}

/**
 * Renders `word` with only `revealedIndices` visible.
 *
 * Spaces and hyphens are structural: always shown, never counted as a hint, so
 * players can see the answer is two words without that costing them a letter.
 * Cells are joined with a space, so "ice cream" with index 0 revealed becomes
 * `i _ _   _ _ _ _ _`.
 */
export function maskWord(
  word: string,
  revealedIndices: readonly number[] = []
): string {
  const text = typeof word === 'string' ? word : '';
  const revealed = new Set(revealedIndices.map((i) => Math.trunc(Number(i))));
  const cells: string[] = [];
  for (let i = 0; i < text.length; i++) {
    cells.push(!isMaskable(text[i]) || revealed.has(i) ? text[i] : BLANK);
  }
  return cells.join(' ');
}

/** Number of characters in `word` that can be hidden behind a blank. */
export function letterCount(word: string): number {
  return maskablePositions(word).length;
}

/** How many letters should show once `hintNumber` hints have landed. */
function targetReveals(
  maskable: number,
  totalHints: number,
  hintNumber: number
): number {
  // Never expose more than half the word, however many hints are configured:
  // past that the answer stops being a guess.
  const cap = Math.trunc(maskable / 2);
  const wanted = Math.max(0, hintNumber);
  const allowed = Math.max(0, totalHints);
  return Math.min(Math.min(wanted, allowed), cap);
}

/** The candidate furthest from every already revealed index. */
function mostIsolated(
  candidates: readonly number[],
  revealed: ReadonlySet<number>,
  random: Random
): number {
  const UNBOUNDED = 1 << 30;
  let bestScore = -1;
  const best: number[] = [];
  for (const candidate of candidates) {
    let score = UNBOUNDED;
    for (const index of revealed) {
      score = Math.min(score, Math.abs(candidate - index));
    }
    if (score > bestScore) {
      bestScore = score;
      best.length = 0;
      best.push(candidate);
    } else if (score === bestScore) {
      best.push(candidate);
    }
  }
  return best[random.nextInt(best.length)];
}

/**
 * The cumulative revealed indices of `word` after hint number `hintNumber`.
 *
 * `hintNumber` is one-based and `current` holds what earlier hints already
 * revealed, so repeated calls only ever add letters. Each new letter is taken
 * as far as possible from the ones already showing, which stops hints
 * clustering at the front of the word where they give the most away.
 */
export function nextHintIndices(args: {
  word: string;
  current?: readonly number[];
  totalHints: number;
  hintNumber: number;
  random?: Random;
}): number[] {
  const { word, current = [], totalHints, hintNumber } = args;
  const random = args.random ?? systemRandom;

  const text = typeof word === 'string' ? word : '';
  const maskable = maskablePositions(text);
  const allowed = new Set(maskable);

  const revealed = new Set<number>();
  for (const index of current) {
    const value = Math.trunc(Number(index));
    if (allowed.has(value)) revealed.add(value);
  }

  const target = targetReveals(
    maskable.length,
    Math.trunc(Number(totalHints)) || 0,
    Math.trunc(Number(hintNumber)) || 0
  );

  if (revealed.size < target) {
    const candidates = maskable.filter((i) => !revealed.has(i));
    while (revealed.size < target && candidates.length > 0) {
      const chosen = mostIsolated(candidates, revealed, random);
      revealed.add(chosen);
      const at = candidates.indexOf(chosen);
      if (at >= 0) candidates.splice(at, 1);
    }
  }
  return [...revealed].sort((a, b) => a - b);
}

/**
 * When hint number `n` of `totalHints` should land within a turn.
 *
 * Hints are spread across the middle of the clock: none in the opening
 * seconds, where they would rob the drawer of the chance to be understood on
 * merit, and none in the last stretch, where a free letter would just hand out
 * points as time expires.
 */
export function hintDueAtMs(
  n: number,
  totalHints: number,
  turnMs: number,
  firstFraction: number,
  lastFraction: number
): number {
  if (totalHints <= 0 || n < 1) return Number.POSITIVE_INFINITY;
  if (totalHints === 1) return Math.round(turnMs * firstFraction);
  const span = lastFraction - firstFraction;
  const step = span / (totalHints - 1);
  const fraction = firstFraction + step * (n - 1);
  return Math.round(turnMs * fraction);
}

// ---------------------------------------------------------------------------
// Word selection (sections 17, 19)
// ---------------------------------------------------------------------------

/**
 * Picks `count` distinct words for a drawer to choose between.
 *
 * `exclude` holds the words already used this game, so a room does not draw
 * the same thing twice while the bank still has alternatives; when the filtered
 * bank runs dry the exclusion is dropped rather than failing the round.
 */
export async function pickWordChoices(args: {
  count: number;
  language: Language;
  categories: readonly string[];
  exclude?: readonly string[];
  random?: Random;
}): Promise<WordChoice[]> {
  const { count, language, categories } = args;
  const random = args.random ?? systemRandom;
  const exclude = new Set((args.exclude ?? []).map((w) => normalize(w)));

  const bank = await loadWordBank(language, categories);
  if (bank.length === 0) {
    throw new Error(`Word bank is empty for language "${language}".`);
  }

  const fresh = bank.filter((w) => !exclude.has(normalize(w.word)));
  const pool = fresh.length >= count ? fresh : bank;

  // Draw across difficulties rather than uniformly, so a drawer is usually
  // offered a genuine choice between a safe word and a valuable one.
  const picked = shuffled(pool, random).slice(0, Math.max(1, count));
  return picked.map(toChoice);
}

/**
 * Reads the word bank for a language and category set.
 *
 * Falls back to the whole language when the requested categories turn up
 * nothing. The non-English banks do not cover every category evenly, and a
 * room that picked "sports" in a language with no sports words should get a
 * playable round rather than a failed one.
 */
async function loadWordBank(
  language: Language,
  categories: readonly string[]
): Promise<WordDoc[]> {
  const db = getFirestore();
  const base = db
    .collection('words')
    .where('language', '==', language) as FirebaseFirestore.Query;

  // "random" means "anything", so it is not a filter at all. Firestore caps an
  // `in` filter at 30 values, which every real category list is well under.
  const filtered = categories.filter((c) => c !== 'random');
  if (filtered.length > 0 && filtered.length <= 30) {
    const scoped = await base.where('category', 'in', filtered).get();
    if (!scoped.empty) {
      return scoped.docs.map((doc) => doc.data() as WordDoc);
    }
  }

  const all = await base.get();
  return all.docs.map((doc) => doc.data() as WordDoc);
}

/** Narrows a bank document to what a drawer is allowed to see. */
function toChoice(word: WordDoc): WordChoice {
  return {
    wordId: word.wordId,
    word: word.word,
    category: word.category as Category,
    difficulty: word.difficulty as Difficulty,
    aliases: Array.isArray(word.aliases) ? word.aliases : [],
  };
}
