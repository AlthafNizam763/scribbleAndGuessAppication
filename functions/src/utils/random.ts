import { randomInt, randomUUID } from 'node:crypto';

import { ROOM_CODE_ALPHABET, LIMITS } from '../config/constants';

/**
 * The small random abstraction the pure game rules are written against.
 *
 * Everything random goes through an object with `nextInt(max)`, so word
 * selection and hint placement can be driven by a seeded generator in tests
 * and by a cryptographic one in production.
 */
export interface Random {
  /** An integer in `[0, max)`. */
  nextInt(max: number): number;
  /** A double in `[0, 1)`. */
  nextDouble(): number;
}

/** A cryptographically strong [Random]. Used everywhere but in tests. */
export const systemRandom: Random = {
  nextInt(max: number): number {
    const bound = Math.trunc(max);
    if (!Number.isFinite(bound) || bound < 1) return 0;
    return randomInt(bound);
  },
  nextDouble(): number {
    return randomInt(0, 2 ** 32) / 2 ** 32;
  },
};

/**
 * A deterministic [Random] seeded with `seed` (mulberry32).
 *
 * Used by tests to pin behaviour that would otherwise be unrepeatable.
 */
export function createRandom(seed = 1): Random {
  let state = (Math.trunc(seed) || 1) >>> 0;
  const nextDouble = (): number => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    nextDouble,
    nextInt(max: number): number {
      const bound = Math.trunc(max);
      if (!Number.isFinite(bound) || bound < 1) return 0;
      return Math.floor(nextDouble() * bound) % bound;
    },
  };
}

/** Shuffles `list` in place with `random` (Fisher-Yates). */
export function shuffleInPlace<T>(list: T[], random: Random = systemRandom): T[] {
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

/** A copy of `list`, shuffled. */
export function shuffled<T>(list: readonly T[], random: Random = systemRandom): T[] {
  return shuffleInPlace([...list], random);
}

/** A fresh room code of unambiguous characters. */
export function newRoomCode(random: Random = systemRandom): string {
  let code = '';
  for (let i = 0; i < LIMITS.roomCodeLength; i++) {
    code += ROOM_CODE_ALPHABET[random.nextInt(ROOM_CODE_ALPHABET.length)];
  }
  return code;
}

/** Whether `value` is a syntactically valid room code. */
export function isValidRoomCode(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  const code = normalizeRoomCode(value);
  if (code.length !== LIMITS.roomCodeLength) return false;
  for (const char of code) {
    if (!ROOM_CODE_ALPHABET.includes(char)) return false;
  }
  return true;
}

/** Trims and upper-cases a room code. */
export function normalizeRoomCode(value: unknown): string {
  return String(value ?? '').trim().toUpperCase();
}

/** A random v4 UUID, used for room, message and word ids. */
export function newId(): string {
  return randomUUID();
}
