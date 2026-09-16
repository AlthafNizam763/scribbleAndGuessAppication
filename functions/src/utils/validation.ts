import { FunctionsErrorCode, HttpsError } from 'firebase-functions/v2/https';

import {
  ALLOWED_MAX_PLAYERS,
  ALLOWED_ROUNDS,
  CATEGORIES,
  DEFAULT_SETTINGS,
  LANGUAGES,
  LIMITS,
  RANGES,
  WORD_MODES,
  clampRange,
} from '../config/constants';
import { RoomSettings } from '../models/types';

/**
 * Payload validation for every callable.
 *
 * Two rules run through this file. First, a client's request is *data*, never
 * a fact: nothing here trusts a type, a range or a length without checking it.
 * Second, failures carry an `AppErrorCode` in `details.code` so the Flutter
 * client can map them onto its own error vocabulary instead of matching on
 * English text (see `lib/core/errors/app_exception.dart`).
 */

/** The app's error vocabulary, mirroring `AppErrorCode` in Dart. */
export type AppErrorCode =
  | 'unknown'
  | 'network'
  | 'timeout'
  | 'serverError'
  | 'connectionLost'
  | 'roomNotFound'
  | 'roomFull'
  | 'gameInProgress'
  | 'nameTaken'
  | 'invalidCode'
  | 'banned'
  | 'kicked'
  | 'notHost'
  | 'notDrawer'
  | 'invalidAction'
  | 'validation'
  | 'storage';

/** Raises a callable error carrying an app error code. */
export function fail(
  status: FunctionsErrorCode,
  code: AppErrorCode,
  message: string
): never {
  throw new HttpsError(status, message, { code });
}

/** A rule violation: the request was well-formed but not allowed right now. */
export function failPrecondition(code: AppErrorCode, message: string): never {
  return fail('failed-precondition', code, message);
}

/** A malformed request. */
export function failInvalid(message: string): never {
  return fail('invalid-argument', 'validation', message);
}

/** The caller is not allowed to do this. */
export function failPermission(code: AppErrorCode, message: string): never {
  return fail('permission-denied', code, message);
}

/** The thing the request names does not exist. */
export function failNotFound(code: AppErrorCode, message: string): never {
  return fail('not-found', code, message);
}

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

/** Reads a required string field, trimmed, with a length ceiling. */
export function requireString(
  data: unknown,
  field: string,
  maxLength: number,
  minLength = 1
): string {
  const value = (data as Record<string, unknown>)?.[field];
  if (typeof value !== 'string') {
    failInvalid(`"${field}" must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length < minLength) {
    failInvalid(`"${field}" must be at least ${minLength} characters.`);
  }
  if (trimmed.length > maxLength) {
    failInvalid(`"${field}" must be at most ${maxLength} characters.`);
  }
  return trimmed;
}

/** Reads an optional string field, or null. */
export function optionalString(
  data: unknown,
  field: string,
  maxLength: number
): string | null {
  const value = (data as Record<string, unknown>)?.[field];
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') {
    failInvalid(`"${field}" must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > maxLength) {
    failInvalid(`"${field}" must be at most ${maxLength} characters.`);
  }
  return trimmed;
}

/** Reads a required integer field within `[min, max]`. */
export function requireInt(
  data: unknown,
  field: string,
  min: number,
  max: number
): number {
  const value = (data as Record<string, unknown>)?.[field];
  const n = Number(value);
  if (!Number.isFinite(n) || !Number.isInteger(n)) {
    failInvalid(`"${field}" must be an integer.`);
  }
  if (n < min || n > max) {
    failInvalid(`"${field}" must be between ${min} and ${max}.`);
  }
  return n;
}

/** Reads a boolean field, defaulting when absent. */
export function optionalBool(
  data: unknown,
  field: string,
  fallback: boolean
): boolean {
  const value = (data as Record<string, unknown>)?.[field];
  if (value === undefined || value === null) return fallback;
  if (typeof value !== 'boolean') {
    failInvalid(`"${field}" must be a boolean.`);
  }
  return value;
}

// ---------------------------------------------------------------------------
// Display names (section 7)
// ---------------------------------------------------------------------------

/**
 * Characters that would let a name break layout or smuggle markup, plus the
 * C0/C1 control ranges.
 */
// eslint-disable-next-line no-control-regex -- stripping control characters is the point
const UNSAFE_NAME = /[<>{}[\]\\/|`~^\u0000-\u001f\u007f]/g;

/**
 * Zero-width, bidirectional-override and word-joiner characters.
 *
 * These are invisible when rendered, which makes them the standard trick for
 * impersonating another player (a name with a zero-width space spliced into
 * it looks identical to the original) or reversing how a name reads in the
 * scoreboard. They are stripped before any length check, so a name padded
 * with them cannot sneak past the minimum either.
 */
const INVISIBLE = /[\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]/g;

/** Control characters that are never legitimate in user text. */
// eslint-disable-next-line no-control-regex -- stripping control characters is the point
const CONTROL = /[\u0000-\u0008\u000b-\u001f\u007f]/g;

/**
 * Cleans and validates a display name.
 *
 * Strips invisible/bidi controls and markup characters, collapses whitespace,
 * and rejects names that carry no letter or digit at all.
 */
export function sanitizeDisplayName(raw: unknown): string {
  if (typeof raw !== 'string') {
    failInvalid('Display name must be a string.');
  }
  const cleaned = raw
    .replace(INVISIBLE, '')
    .replace(UNSAFE_NAME, '')
    .replace(/\s+/g, ' ')
    .trim();

  if (cleaned.length < LIMITS.minNameLength) {
    failInvalid(`Name must be at least ${LIMITS.minNameLength} characters.`);
  }
  if (cleaned.length > LIMITS.maxNameLength) {
    failInvalid(`Name must be at most ${LIMITS.maxNameLength} characters.`);
  }
  // A name of nothing but punctuation is unreadable on a scoreboard.
  if (!/[\p{L}\p{N}]/u.test(cleaned)) {
    failInvalid('Name must contain at least one letter or number.');
  }
  return cleaned;
}

/** Cleans a chat message, keeping it printable and bounded. */
export function sanitizeMessage(raw: unknown): string {
  if (typeof raw !== 'string') {
    failInvalid('Message must be a string.');
  }
  const cleaned = raw
    .replace(INVISIBLE, '')
    .replace(CONTROL, '')
    .replace(/\s+/g, ' ')
    .trim();

  if (cleaned.length === 0) {
    failInvalid('Message cannot be empty.');
  }
  if (cleaned.length > LIMITS.maxChatLength) {
    failInvalid(`Message must be at most ${LIMITS.maxChatLength} characters.`);
  }
  return cleaned;
}

// ---------------------------------------------------------------------------
// Room settings (section 13)
// ---------------------------------------------------------------------------

/**
 * Validates and normalises a settings payload.
 *
 * Unknown fields are dropped rather than merged, so a client cannot smuggle an
 * extra key into the room document, and every number is clamped rather than
 * rejected where a sane neighbouring value exists.
 */
export function sanitizeSettings(raw: unknown): RoomSettings {
  const data = (raw ?? {}) as Record<string, unknown>;

  const maxPlayers = pickAllowed(
    data.maxPlayers,
    ALLOWED_MAX_PLAYERS,
    DEFAULT_SETTINGS.maxPlayers
  );
  const rounds = pickAllowed(
    data.rounds,
    ALLOWED_ROUNDS,
    DEFAULT_SETTINGS.rounds
  );

  const hintsEnabled =
    typeof data.hintsEnabled === 'boolean'
      ? data.hintsEnabled
      : DEFAULT_SETTINGS.hintsEnabled;

  const language = LANGUAGES.includes(data.language as never)
    ? (data.language as RoomSettings['language'])
    : DEFAULT_SETTINGS.language;

  const wordMode = WORD_MODES.includes(data.wordMode as never)
    ? (data.wordMode as RoomSettings['wordMode'])
    : DEFAULT_SETTINGS.wordMode;

  const categories = Array.isArray(data.categories)
    ? data.categories
        .filter((c): c is string => typeof c === 'string')
        .filter((c) => CATEGORIES.includes(c as never))
    : [...DEFAULT_SETTINGS.categories];

  return {
    maxPlayers,
    rounds,
    drawTimeSeconds: clampRange(
      data.drawTimeSeconds,
      RANGES.drawTimeSeconds,
      DEFAULT_SETTINGS.drawTimeSeconds
    ),
    wordsToChoose: clampRange(
      data.wordsToChoose,
      RANGES.wordChoiceCount,
      DEFAULT_SETTINGS.wordsToChoose
    ),
    hintsEnabled,
    // Hints disabled means zero hints, whatever the count says: keeping the
    // two consistent here means no downstream code has to check both.
    hintCount: hintsEnabled
      ? clampRange(data.hintCount, RANGES.hintCount, DEFAULT_SETTINGS.hintCount)
      : 0,
    wordSelectSeconds: clampRange(
      data.wordSelectSeconds,
      RANGES.wordSelectSeconds,
      DEFAULT_SETTINGS.wordSelectSeconds
    ),
    wordMode,
    language,
    categories: categories.length > 0 ? categories : ['random'],
    allowVoteKick:
      typeof data.allowVoteKick === 'boolean'
        ? data.allowVoteKick
        : DEFAULT_SETTINGS.allowVoteKick,
    isPrivate:
      typeof data.isPrivate === 'boolean'
        ? data.isPrivate
        : DEFAULT_SETTINGS.isPrivate,
  };
}

/** Returns `value` when it is one of `allowed`, else `fallback`. */
function pickAllowed<T extends number>(
  value: unknown,
  allowed: readonly T[],
  fallback: T
): T {
  const n = Number(value);
  return allowed.includes(n as T) ? (n as T) : fallback;
}
