/**
 * Faithful port of lib/domain/rules/hint_engine.dart.
 *
 * Builds the masked word shown to guessers and decides which letters the
 * server reveals as hints. Spaces and hyphens are structural: always visible,
 * never counted as a hint. Pure; the only randomness is the injected random.
 */

import { systemRandom } from './ids.js';

/** The glyph standing in for a hidden letter. */
export const BLANK = '_';

/** Stands in for "infinitely far away" while nothing is revealed yet. */
const UNBOUNDED = 1 << 30;

/** Whether `char` is hidden until a hint reveals it. */
function isMaskable(char) {
  return char !== ' ' && char !== '-';
}

/** Indices of `word` that can be hidden, ascending. */
function maskablePositions(word) {
  const out = [];
  for (let i = 0; i < word.length; i++) {
    if (isMaskable(word[i])) out.push(i);
  }
  return out;
}

/**
 * Renders `word` with only `revealedIndices` visible.
 *
 * Cells are joined with a single space, so `ice cream` with index 0 revealed
 * becomes `i _ _   _ _ _ _ _`.
 *
 * @param {string} word
 * @param {number[]} revealedIndices
 * @returns {string}
 */
export function maskWord(word, revealedIndices = []) {
  const text = typeof word === 'string' ? word : '';
  const revealed = new Set(
    (Array.isArray(revealedIndices) ? revealedIndices : []).map((index) => Math.trunc(Number(index))),
  );
  const cells = [];
  for (let i = 0; i < text.length; i++) {
    cells.push(!isMaskable(text[i]) || revealed.has(i) ? text[i] : BLANK);
  }
  return cells.join(' ');
}

/** Number of characters in `word` that can be hidden behind a blank. */
export function letterCount(word) {
  const text = typeof word === 'string' ? word : '';
  let count = 0;
  for (let i = 0; i < text.length; i++) {
    if (isMaskable(text[i])) count++;
  }
  return count;
}

/** How many letters should be showing once `hintNumber` hints have landed. */
function targetReveals({ maskable, totalHints, hintNumber }) {
  const cap = Math.trunc(maskable / 2);
  const wanted = hintNumber < 0 ? 0 : hintNumber;
  const allowedHints = totalHints < 0 ? 0 : totalHints;
  const limited = wanted < allowedHints ? wanted : allowedHints;
  return limited < cap ? limited : cap;
}

/**
 * The candidate furthest from every already revealed index.
 *
 * Ties - including the very first reveal, where nothing is showing yet - are
 * broken with `random`.
 */
function mostIsolated(candidates, revealed, random) {
  let bestScore = -1;
  const best = [];
  for (const candidate of candidates) {
    let score = UNBOUNDED;
    for (const index of revealed) {
      const distance = Math.abs(candidate - index);
      if (distance < score) score = distance;
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
 * `hintNumber` is one-based and `current` holds what previous hints already
 * revealed, so calling this repeatedly only ever adds letters. At most half of
 * the maskable positions are ever revealed, no index is revealed twice, and
 * each new letter is taken as far as possible from the ones already showing so
 * hints do not cluster at the start of the word. The result is sorted ascending.
 *
 * @param {{word: string, current?: number[], totalHints: number, hintNumber: number, random?: {nextInt: (max: number) => number}}} args
 * @returns {number[]}
 */
export function nextHintIndices({ word, current = [], totalHints, hintNumber, random = systemRandom }) {
  const text = typeof word === 'string' ? word : '';
  const maskable = maskablePositions(text);
  const allowed = new Set(maskable);
  const revealed = new Set();
  for (const index of Array.isArray(current) ? current : []) {
    const value = Math.trunc(Number(index));
    if (allowed.has(value)) revealed.add(value);
  }
  const target = targetReveals({
    maskable: maskable.length,
    totalHints: Math.trunc(Number(totalHints)) || 0,
    hintNumber: Math.trunc(Number(hintNumber)) || 0,
  });
  if (revealed.size < target) {
    const candidates = maskable.filter((index) => !revealed.has(index));
    while (revealed.size < target && candidates.length > 0) {
      const chosen = mostIsolated(candidates, revealed, random);
      revealed.add(chosen);
      const at = candidates.indexOf(chosen);
      if (at >= 0) candidates.splice(at, 1);
    }
  }
  return [...revealed].sort((a, b) => a - b);
}

export const HintEngine = Object.freeze({ blank: BLANK, maskWord, letterCount, nextHintIndices });

export default HintEngine;
