/**
 * Faithful port of lib/domain/rules/guess_matcher.dart.
 *
 * Both sides of a comparison are normalized first - case, accents and stray
 * whitespace are irrelevant - so "Creme  Brulee" matches "creme brulee".
 * Pure and deterministic; the client runs the very same rules.
 */

import { VERDICT } from './protocol.js';

/**
 * Minimum letters a word needs before a one-letter typo counts as close.
 * `GameDefaults.closeGuessMinLength`.
 */
export const CLOSE_GUESS_MIN_LENGTH = 4;

/** Accent folding for the Latin-1 letters the word banks use. */
const ACCENT_FOLDING = Object.freeze({
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ð': 'd',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'þ': 'th',
  'ß': 'ss',
});

const WHITESPACE = /\s+/g;

/**
 * The canonical form of `value` used for every comparison.
 *
 * Lower-cases, folds Latin-1 accents (plus n-tilde, c-cedilla, the umlauts and
 * sharp-s to "ss"), collapses runs of whitespace to a single space and trims
 * the ends.
 *
 * @param {string} value
 * @returns {string}
 */
export function normalize(value) {
  const text = typeof value === 'string' ? value : String(value ?? '');
  let out = '';
  for (const char of text.toLowerCase()) {
    out += ACCENT_FOLDING[char] ?? char;
  }
  return out.replace(WHITESPACE, ' ').trim();
}

/**
 * The Levenshtein edit distance between `a` and `b`.
 *
 * Iterative and two-row, so memory stays at O(min(a.length, b.length))
 * however long the strings are.
 *
 * @param {string} a
 * @param {string} b
 * @returns {number}
 */
export function levenshtein(a, b) {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;
  const aIsLonger = a.length >= b.length;
  const rows = aIsLonger ? a : b;
  const columns = aIsLonger ? b : a;
  const width = columns.length;
  let previous = new Array(width + 1);
  for (let i = 0; i <= width; i++) previous[i] = i;
  let current = new Array(width + 1).fill(0);
  for (let i = 1; i <= rows.length; i++) {
    current[0] = i;
    const rowUnit = rows.charCodeAt(i - 1);
    for (let j = 1; j <= width; j++) {
      const cost = rowUnit === columns.charCodeAt(j - 1) ? 0 : 1;
      const substitution = previous[j - 1] + cost;
      const deletion = previous[j] + 1;
      const insertion = current[j - 1] + 1;
      current[j] = Math.min(substitution, Math.min(deletion, insertion));
    }
    const swap = previous;
    previous = current;
    current = swap;
  }
  return previous[width];
}

/**
 * Grades `guess` against `word`.
 *
 * A blank guess or a blank word is always `wrong`. A guess is `close` when the
 * word is at least `CLOSE_GUESS_MIN_LENGTH` characters long and exactly one
 * edit away, which is what earns the "you're close!" chat line.
 *
 * @param {string} guess
 * @param {string} word
 * @returns {'correct'|'close'|'wrong'}
 */
export function evaluate(guess, word) {
  const normalizedGuess = normalize(guess);
  const normalizedWord = normalize(word);
  if (normalizedGuess.length === 0 || normalizedWord.length === 0) return VERDICT.wrong;
  if (normalizedGuess === normalizedWord) return VERDICT.correct;
  if (normalizedWord.length >= CLOSE_GUESS_MIN_LENGTH && levenshtein(normalizedGuess, normalizedWord) === 1) {
    return VERDICT.close;
  }
  return VERDICT.wrong;
}

export const GuessMatcher = Object.freeze({ evaluate, normalize, levenshtein });

export default GuessMatcher;
