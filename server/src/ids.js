/**
 * Identifier generation plus the small random abstraction the pure game
 * rules are written against.
 *
 * Everything random in the rules goes through a `Random` object with a
 * `nextInt(max)` method, exactly like Dart's `dart:math` `Random`, so the
 * server ports can be tested deterministically with a seeded generator.
 */

import { randomUUID, randomInt } from 'node:crypto';

import { config } from './config.js';

/**
 * Characters a room code may contain. Mirrors
 * `AppConstants.roomCodeAlphabet`: deliberately excludes O, 0, I and 1 so a
 * code can be read aloud and typed without ambiguity.
 */
export const ROOM_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Number of characters in a room code. `AppConstants.roomCodeLength`. */
export const ROOM_CODE_LENGTH = config.limits.roomCodeLength;

/** A cryptographically strong `Random`. Used everywhere but in tests. */
export const systemRandom = Object.freeze({
  /** An integer in `[0, max)`. Mirrors Dart's `Random.nextInt`. */
  nextInt(max) {
    const bound = Math.trunc(max);
    if (!Number.isFinite(bound) || bound < 1) return 0;
    return randomInt(bound);
  },
  /** A double in `[0, 1)`. Mirrors Dart's `Random.nextDouble`. */
  nextDouble() {
    return randomInt(0, 2 ** 32) / 2 ** 32;
  },
});

/**
 * A deterministic `Random` seeded with `seed` (mulberry32).
 *
 * The sequence deliberately differs from Dart's, because a JS and a Dart RNG
 * can never agree; what matters is that the *algorithms* around it match, and
 * that tests can pin the server's own behaviour.
 */
export function createRandom(seed = 1) {
  let state = (Math.trunc(seed) || 1) >>> 0;
  const nextDouble = () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    nextInt(max) {
      const bound = Math.trunc(max);
      if (!Number.isFinite(bound) || bound < 1) return 0;
      return Math.floor(nextDouble() * bound) % bound;
    },
    nextDouble,
  };
}

/**
 * Shuffles `list` in place with `random`.
 *
 * A one-for-one port of Dart's `List.shuffle`, so a seeded port of the word
 * selector behaves like the client's for the same generator.
 */
export function shuffleInPlace(list, random = systemRandom) {
  let length = list.length;
  while (length > 1) {
    const pos = random.nextInt(length);
    length -= 1;
    const tmp = list[length];
    list[length] = list[pos];
    list[pos] = tmp;
  }
  return list;
}

/** A fresh room code of `ROOM_CODE_LENGTH` unambiguous characters. */
export function newRoomCode(random = systemRandom) {
  let code = '';
  for (let i = 0; i < ROOM_CODE_LENGTH; i++) {
    code += ROOM_CODE_ALPHABET[random.nextInt(ROOM_CODE_ALPHABET.length)];
  }
  return code;
}

/** Whether `value` is a syntactically valid room code. */
export function isValidRoomCode(value) {
  if (typeof value !== 'string') return false;
  const code = normalizeRoomCode(value);
  if (code.length !== ROOM_CODE_LENGTH) return false;
  for (const char of code) {
    if (!ROOM_CODE_ALPHABET.includes(char)) return false;
  }
  return true;
}

/** Trims and upper-cases a room code. Mirrors `Validators.normalizeRoomCode`. */
export function normalizeRoomCode(value) {
  return String(value ?? '').trim().toUpperCase();
}

/** A random v4 UUID, used for player, stroke, message and room ids. */
export function newId() {
  return randomUUID();
}

/** A prefixed id, e.g. `msg_9f1c...`, handy when reading logs. */
export function newPrefixedId(prefix) {
  return `${prefix}_${randomUUID()}`;
}
