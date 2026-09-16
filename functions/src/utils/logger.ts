import * as functions from 'firebase-functions/logger';

/**
 * Structured logging for the backend.
 *
 * Cloud Logging indexes the second argument, so context goes there as fields
 * rather than being interpolated into the message — that is what makes
 * `roomId="A7K9P"` a filterable query instead of a substring search.
 *
 * NEVER log the answer to a live round, an id token, or anything a player
 * typed verbatim in production (§63). `redactWord` exists for exactly this.
 */

type Fields = Record<string, unknown>;

export const logger = {
  debug(message: string, fields: Fields = {}): void {
    functions.debug(message, fields);
  },
  info(message: string, fields: Fields = {}): void {
    functions.info(message, fields);
  },
  warn(message: string, fields: Fields = {}): void {
    functions.warn(message, fields);
  },
  error(message: string, error?: unknown, fields: Fields = {}): void {
    functions.error(message, {
      ...fields,
      error: serializeError(error),
    });
  },
};

/** Turns anything thrown into something Cloud Logging can render. */
function serializeError(error: unknown): unknown {
  if (error instanceof Error) {
    return { name: error.name, message: error.message, stack: error.stack };
  }
  return error ?? null;
}

/**
 * A word rendered safe to log: its length and first letter only.
 *
 * Enough to debug a hint or scoring problem from a log trace, never enough to
 * leak the answer of a round that is still being played.
 */
export function redactWord(word: string | null | undefined): string {
  if (!word) return '<none>';
  if (word.length <= 1) return '*';
  return `${word[0]}${'*'.repeat(word.length - 1)}`;
}
