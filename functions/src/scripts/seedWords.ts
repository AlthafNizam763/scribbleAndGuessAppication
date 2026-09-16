import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

import { CATEGORIES, DIFFICULTIES, LANGUAGES } from '../config/constants';
import { WordDoc } from '../models/types';

/**
 * Seeds the `words` collection from `assets/words/words_<lang>.json` (§69).
 *
 * Run against the emulator:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 npm run seed
 *
 * Run against a real project:
 *   GOOGLE_APPLICATION_CREDENTIALS=./sa.json FIREBASE_PROJECT=my-project npm run seed
 *
 * Word ids are derived from the language and the word itself rather than being
 * random, which makes the whole script idempotent: running it twice updates
 * the same documents instead of duplicating the bank.
 */

interface WordBankFile {
  language: string;
  categories: Record<string, Record<string, string[]>>;
}

/** Where the shared word banks live, relative to `functions/`. */
const ASSETS_DIR = resolve(__dirname, '../../../assets/words');

/** Firestore refuses batches larger than 500 writes. */
const BATCH_LIMIT = 450;

async function main(): Promise<void> {
  const projectId =
    process.env.FIREBASE_PROJECT ??
    process.env.GCLOUD_PROJECT ??
    'scribble-and-guess-dev';

  const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  initializeApp(
    usingEmulator
      ? { projectId }
      : { projectId, credential: applicationDefault() }
  );

  const db = getFirestore();
  const words = collectWords();

  if (words.length === 0) {
    throw new Error(`No word banks found in ${ASSETS_DIR}`);
  }

  console.log(
    `Seeding ${words.length} words into "${projectId}"` +
      (usingEmulator ? ' (emulator)' : '')
  );

  let written = 0;
  for (let i = 0; i < words.length; i += BATCH_LIMIT) {
    const slice = words.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const word of slice) {
      batch.set(db.collection('words').doc(word.wordId), word);
    }
    await batch.commit();
    written += slice.length;
    console.log(`  ${written}/${words.length}`);
  }

  const summary = new Map<string, number>();
  for (const word of words) {
    summary.set(word.language, (summary.get(word.language) ?? 0) + 1);
  }
  console.log('Done:');
  for (const [language, count] of [...summary].sort()) {
    console.log(`  ${language}: ${count}`);
  }
}

/** Reads every bank file and flattens it into word documents. */
function collectWords(): WordDoc[] {
  const files = readdirSync(ASSETS_DIR).filter(
    (f) => f.startsWith('words_') && f.endsWith('.json')
  );

  const out: WordDoc[] = [];
  const seen = new Set<string>();

  for (const file of files) {
    const raw = readFileSync(join(ASSETS_DIR, file), 'utf8');
    const bank = JSON.parse(raw) as WordBankFile;

    const language = bank.language;
    if (!LANGUAGES.includes(language as never)) {
      console.warn(`  skipping ${file}: unsupported language "${language}"`);
      continue;
    }

    for (const [category, byDifficulty] of Object.entries(bank.categories)) {
      if (!CATEGORIES.includes(category as never)) {
        console.warn(`  skipping category "${category}" in ${file}`);
        continue;
      }
      for (const [difficulty, list] of Object.entries(byDifficulty)) {
        if (!DIFFICULTIES.includes(difficulty as never)) {
          console.warn(`  skipping difficulty "${difficulty}" in ${file}`);
          continue;
        }
        for (const word of list) {
          const text = String(word ?? '').trim();
          if (text.length === 0) continue;

          const wordId = makeWordId(language, text);
          // The same word can legitimately appear under two categories; the
          // first listing wins so the id stays stable.
          if (seen.has(wordId)) continue;
          seen.add(wordId);

          out.push({
            wordId,
            word: text,
            category: category as WordDoc['category'],
            difficulty: difficulty as WordDoc['difficulty'],
            language: language as WordDoc['language'],
            aliases: aliasesFor(text),
          });
        }
      }
    }
  }
  return out;
}

/**
 * A stable, filesystem-safe document id for a word.
 *
 * Firestore ids may not contain "/", and must be usable in a URL, so the word
 * is percent-encoded — which also keeps non-Latin banks (Malayalam, Hindi,
 * Japanese, Russian) addressable.
 */
function makeWordId(language: string, word: string): string {
  return `${language}_${encodeURIComponent(word.toLowerCase())}`;
}

/**
 * Alternative spellings that should also count as correct (§26).
 *
 * Only mechanical variants are generated here: a spaced or hyphenated word is
 * accepted written solid, and vice versa. Anything semantic ("plane" for
 * "airplane") belongs in the bank as an explicit alias, because guessing at it
 * automatically would start accepting genuinely wrong answers.
 */
function aliasesFor(word: string): string[] {
  const aliases = new Set<string>();
  if (/[\s-]/.test(word)) {
    aliases.add(word.replace(/[\s-]/g, ''));
    aliases.add(word.replace(/-/g, ' '));
  }
  aliases.delete(word);
  return [...aliases];
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
