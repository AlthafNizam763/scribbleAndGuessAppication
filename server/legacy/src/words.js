/**
 * Word bank loading plus a faithful port of
 * lib/domain/rules/word_selection.dart (`WordSelector.pickChoices`).
 *
 * The bank is parsed from assets/words/words_<lang>.json - the very same asset
 * the Flutter client bundles - and cached per language. Loading never throws:
 * a missing or broken asset falls back to a small built-in list so the game
 * always has words to offer.
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { LANGUAGES, WORD_CATEGORIES, WORD_DIFFICULTIES, WORD_MODE } from './protocol.js';
import { shuffleInPlace, systemRandom } from './ids.js';
import { logger } from './logger.js';

const log = logger.child('words');
const here = path.dirname(fileURLToPath(import.meta.url));

/** Cache of parsed banks, keyed by language name. */
const cache = new Map();

/**
 * A last-resort word list, used only when no asset file can be read.
 * Mirrors the spirit of lib/data/words/fallback_words.dart.
 */
const FALLBACK_WORDS = Object.freeze([
  { text: 'cat', category: 'animals', difficulty: 'easy' },
  { text: 'dog', category: 'animals', difficulty: 'easy' },
  { text: 'house', category: 'places', difficulty: 'easy' },
  { text: 'tree', category: 'nature', difficulty: 'easy' },
  { text: 'apple', category: 'food', difficulty: 'easy' },
  { text: 'guitar', category: 'objects', difficulty: 'medium' },
  { text: 'rocket', category: 'technology', difficulty: 'medium' },
  { text: 'penguin', category: 'animals', difficulty: 'medium' },
  { text: 'lighthouse', category: 'places', difficulty: 'hard' },
  { text: 'astronaut', category: 'jobs', difficulty: 'hard' },
  { text: 'telescope', category: 'technology', difficulty: 'hard' },
  { text: 'waterfall', category: 'nature', difficulty: 'medium' },
]);

/** Normalizes a language name to a supported one, defaulting to English. */
export function normalizeLanguage(value) {
  const name = String(value ?? '').trim();
  return LANGUAGES.includes(name) ? name : 'en';
}

/** Candidate locations of the word assets, most likely first. */
export function candidatePaths(language) {
  const file = `words_${language}.json`;
  const fromEnv = (process.env.WORDS_DIR || '').trim();
  const roots = [
    // server/src -> repo root/assets/words (the canonical layout)
    path.resolve(here, '..', '..', 'assets', 'words'),
    // server/assets/words, for a self-contained deployment bundle
    path.resolve(here, '..', 'assets', 'words'),
    path.resolve(process.cwd(), 'assets', 'words'),
    path.resolve(process.cwd(), '..', 'assets', 'words'),
  ];
  if (fromEnv) roots.unshift(path.resolve(fromEnv));
  return roots.map((root) => path.join(root, file));
}

/** Reads and JSON-parses the first candidate path that works. */
function readBankJson(language) {
  for (const candidate of candidatePaths(language)) {
    try {
      const raw = readFileSync(candidate, 'utf8');
      return { json: JSON.parse(raw), source: candidate };
    } catch {
      // Try the next candidate; a missing asset is not an error yet.
    }
  }
  return null;
}

/**
 * Parses the asset shape
 * `{"language": "en", "categories": {"<category>": {"easy": [...]}}}`
 * defensively: unknown keys, non-list values and blank words are skipped
 * rather than thrown on. Mirrors `WordBank.fromJson`.
 */
export function parseBank(json, language) {
  const categories = json && typeof json === 'object' ? json.categories : null;
  /** @type {Map<string, {text: string, category: string, difficulty: string}[]>} */
  const byCategory = new Map();
  if (categories && typeof categories === 'object') {
    for (const [categoryKey, group] of Object.entries(categories)) {
      const category = WORD_CATEGORIES.find((name) => name === categoryKey || name === String(categoryKey).toLowerCase());
      if (!category) continue;
      if (!byCategory.has(category)) byCategory.set(category, []);
      const words = byCategory.get(category);
      if (!group || typeof group !== 'object') continue;
      for (const [difficultyKey, list] of Object.entries(group)) {
        const difficulty = WORD_DIFFICULTIES.find(
          (name) => name === difficultyKey || name === String(difficultyKey).toLowerCase(),
        );
        if (!difficulty || !Array.isArray(list)) continue;
        for (const raw of list) {
          const text = typeof raw === 'string' ? raw.trim() : '';
          if (text.length === 0) continue;
          words.push({ text, category, difficulty });
        }
      }
    }
  }
  return {
    language: normalizeLanguage(json?.language ?? language),
    byCategory,
    /** Every word, in canonical WordCategory order. */
    all() {
      const out = [];
      for (const category of WORD_CATEGORIES) {
        for (const word of byCategory.get(category) ?? []) out.push(word);
      }
      return out;
    },
    /**
     * Words of any of `categories`, deduplicated by lowercase text, in
     * canonical category order. An empty set or one containing `random`
     * selects every category. Mirrors `WordBank.wordsFor`.
     */
    wordsFor(wanted) {
      const set = new Set(Array.isArray(wanted) ? wanted : [...(wanted ?? [])]);
      const everything = set.size === 0 || set.has('random');
      const out = [];
      const seen = new Set();
      for (const category of WORD_CATEGORIES) {
        if (!everything && !set.has(category)) continue;
        for (const word of byCategory.get(category) ?? []) {
          const key = word.text.toLowerCase();
          if (seen.has(key)) continue;
          seen.add(key);
          out.push(word);
        }
      }
      return out;
    },
  };
}

/** The bank of `language`, parsed on first use and cached afterwards. */
export function loadBank(language) {
  const lang = normalizeLanguage(language);
  const cached = cache.get(lang);
  if (cached) return cached;
  const read = readBankJson(lang);
  let bank = read ? parseBank(read.json, lang) : null;
  if (!bank || bank.all().length === 0) {
    log.warn(`no usable word asset for "${lang}"; falling back to the built-in list`);
    bank = parseBank(
      {
        language: lang,
        categories: FALLBACK_WORDS.reduce((acc, word) => {
          acc[word.category] ??= {};
          acc[word.category][word.difficulty] ??= [];
          acc[word.category][word.difficulty].push(word.text);
          return acc;
        }, {}),
      },
      lang,
    );
  } else {
    log.debug(`loaded ${bank.all().length} "${lang}" words from ${read.source}`);
  }
  cache.set(lang, bank);
  return bank;
}

/** Drops every cached bank. Intended for tests. */
export function clearCache() {
  cache.clear();
}

/** The pool a room draws from, honouring its language and categories. */
export function poolFor(settings) {
  const bank = loadBank(settings?.language);
  return bank.wordsFor(settings?.categories ?? ['random']);
}

/** The case- and whitespace-insensitive key of a word. */
function keyOf(word) {
  return String(word ?? '').trim().toLowerCase();
}

/** Wraps raw custom words as medium, uncategorised word items. */
function customPool(customWords) {
  const out = [];
  for (const word of Array.isArray(customWords) ? customWords : []) {
    const text = typeof word === 'string' ? word.trim() : '';
    if (text.length === 0) continue;
    out.push({ text, category: 'random', difficulty: 'medium' });
  }
  return out;
}

/** Drops blank entries from a word-bank pool. */
function cleanPool(pool) {
  const out = [];
  for (const item of Array.isArray(pool) ? pool : []) {
    if (item && typeof item.text === 'string' && item.text.trim().length > 0) out.push(item);
  }
  return out;
}

/** The categories to keep, or `null` when every category is allowed. */
function categoryFilter(categories) {
  const set = new Set(Array.isArray(categories) ? categories : [...(categories ?? [])]);
  return set.size === 0 || set.has('random') ? null : set;
}

/** The entries of `source` passing the category and used-word filters. */
function filterPool(source, categories, used) {
  const out = [];
  for (const item of source) {
    if (categories !== null && !categories.has(item.category)) continue;
    if (used.has(keyOf(item.text))) continue;
    out.push(item);
  }
  return out;
}

/**
 * Draws up to `count` items from `candidates`, round-robin over the
 * difficulties so an offer mixes easy and hard words when it can.
 */
function spread(candidates, count, random) {
  /** @type {Map<string, object[]>} */
  const buckets = new Map(WORD_DIFFICULTIES.map((difficulty) => [difficulty, []]));
  for (const item of candidates) {
    const bucket = buckets.get(item.difficulty) ?? buckets.get('medium');
    bucket.push(item);
  }
  for (const bucket of buckets.values()) shuffleInPlace(bucket, random);
  const picked = [];
  let progressed = true;
  while (picked.length < count && progressed) {
    progressed = false;
    for (const difficulty of WORD_DIFFICULTIES) {
      if (picked.length >= count) break;
      const bucket = buckets.get(difficulty);
      if (bucket.length > 0) {
        picked.push(bucket.pop());
        progressed = true;
      }
    }
  }
  return picked;
}

/** Repeats `picked` in place until it holds `count` items. */
function pad(picked, count) {
  if (picked.length === 0 || picked.length >= count) return;
  const available = picked.length;
  for (let i = 0; picked.length < count; i++) {
    picked.push(picked[i % available]);
  }
}

/**
 * Returns `count` words for the drawer to choose from.
 *
 * The pool is filtered by the categories of `settings` - where `random` means
 * "every category" - and words in `usedWords` are skipped case-insensitively.
 * When that leaves too few candidates the constraints are relaxed in order:
 * first `usedWords` is ignored, then the category filter, and finally the
 * result is padded by repeating words. Custom word mode draws from
 * `settings.customWords` instead.
 *
 * Never throws and never returns fewer than `min(count, pool.length)` items;
 * an empty pool yields an empty list.
 *
 * @param {{pool?: object[], settings: object, usedWords?: Set<string>|string[], count: number, random?: {nextInt: (max: number) => number}}} args
 * @returns {{text: string, category: string, difficulty: string}[]}
 */
export function pickChoices({ pool, settings, usedWords = new Set(), count, random = systemRandom }) {
  const wanted = Math.trunc(Number(count));
  if (!Number.isFinite(wanted) || wanted < 1) return [];
  const isCustom =
    settings?.wordMode === WORD_MODE.custom &&
    Array.isArray(settings?.customWords) &&
    settings.customWords.length > 0;
  const source = isCustom ? customPool(settings.customWords) : cleanPool(pool ?? poolFor(settings));
  if (source.length === 0) return [];
  const categories = isCustom ? null : categoryFilter(settings?.categories);
  const used = new Set();
  for (const word of usedWords ?? []) used.add(keyOf(word));

  let candidates = filterPool(source, categories, used);
  if (candidates.length < wanted) candidates = filterPool(source, categories, new Set());
  if (candidates.length < wanted) candidates = source;
  const picked = spread(candidates, wanted, random);
  pad(picked, wanted);
  return picked;
}

export default { loadBank, poolFor, pickChoices, parseBank, clearCache, candidatePaths, normalizeLanguage };
