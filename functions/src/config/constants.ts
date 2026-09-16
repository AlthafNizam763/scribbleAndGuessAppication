/**
 * Every tunable number the backend depends on.
 *
 * The ranges mirror `lib/models/room_settings.dart` and
 * `lib/core/constants/game_constants.dart` exactly — both sides must agree, or
 * a client will offer a setting the server then rejects.
 */

/** Inclusive bounds for a numeric setting. */
export interface IntRange {
  readonly min: number;
  readonly max: number;
}

/** Pulls `value` inside `range`, falling back for nonsense input. */
export function clampRange(
  value: unknown,
  range: IntRange,
  fallback: number
): number {
  const n = Number(value);
  const int = Number.isFinite(n) ? Math.trunc(n) : fallback;
  return Math.min(range.max, Math.max(range.min, int));
}

/** Allowed room-settings ranges. */
export const RANGES = {
  maxPlayers: { min: 2, max: 20 } as IntRange,
  rounds: { min: 1, max: 10 } as IntRange,
  drawTimeSeconds: { min: 30, max: 180 } as IntRange,
  wordChoiceCount: { min: 1, max: 5 } as IntRange,
  hintCount: { min: 0, max: 4 } as IntRange,
  wordSelectSeconds: { min: 5, max: 30 } as IntRange,
} as const;

/** Discrete choices the create-room UI offers (§13). */
export const ALLOWED_MAX_PLAYERS = [4, 6, 8, 10, 12, 16, 20] as const;
export const ALLOWED_ROUNDS = [1, 2, 3, 5, 10] as const;

/** Every supported word language (§13). */
export const LANGUAGES = ['en', 'ml', 'hi', 'de', 'ja', 'ru'] as const;
export type Language = (typeof LANGUAGES)[number];

/** Every word category (§17). */
export const CATEGORIES = [
  'animals',
  'food',
  'objects',
  'places',
  'movies',
  'sports',
  'jobs',
  'technology',
  'nature',
  'music',
  'vehicles',
  'random',
] as const;
export type Category = (typeof CATEGORIES)[number];

/** Word difficulty tiers, which feed the scoring multiplier. */
export const DIFFICULTIES = ['easy', 'medium', 'hard'] as const;
export type Difficulty = (typeof DIFFICULTIES)[number];

/** How words are offered to the drawer (§13). */
export const WORD_MODES = ['normal', 'hidden', 'combination'] as const;
export type WordMode = (typeof WORD_MODES)[number];

/** Room lifecycle (§8). */
export const ROOM_STATUSES = [
  'waiting',
  'starting',
  'playing',
  'round_result',
  'finished',
  'closed',
] as const;
export type RoomStatus = (typeof ROOM_STATUSES)[number];

/** The explicit game state machine (§14). */
export const ROUND_STATUSES = [
  'waiting',
  'starting',
  'word_selection',
  'drawing',
  'round_result',
  'final_result',
] as const;
export type RoundStatus = (typeof ROUND_STATUSES)[number];

/** Chat message kinds (§31). */
export const MESSAGE_TYPES = [
  'chat',
  'guess',
  'correct',
  'close',
  'system',
  'warning',
] as const;
export type MessageType = (typeof MESSAGE_TYPES)[number];

/** Default settings a room is created with. */
export const DEFAULT_SETTINGS = {
  maxPlayers: 8,
  rounds: 3,
  drawTimeSeconds: 80,
  wordsToChoose: 3,
  hintsEnabled: true,
  hintCount: 2,
  wordSelectSeconds: 15,
  wordMode: 'normal' as WordMode,
  language: 'en' as Language,
  categories: ['random'] as string[],
  allowVoteKick: true,
  isPrivate: false,
} as const;

/** Timings the game loop runs on, in milliseconds. */
export const TIMING = {
  /** Lobby → first turn countdown. */
  startCountdownMs: 3_000,
  /** How long the round-result screen stays up before the next round. */
  roundResultMs: 6_000,
  /** Slack added to a deadline before the server calls a round over. */
  turnGraceMs: 500,
  /** A disconnected drawer is waited for this long before the round is cut. */
  drawerGraceMs: 20_000,
  /** A disconnected player keeps their seat this long. */
  reconnectGraceMs: 45_000,
  /** A player is considered offline after this long without a heartbeat. */
  presenceTimeoutMs: 30_000,
  /** Minimum gap between presence writes, so heartbeats stay cheap (§35). */
  heartbeatIntervalMs: 15_000,
  /** Fraction of the turn elapsed before the first hint lands. */
  firstHintAtFraction: 0.45,
  /** Fraction of the turn after which no further hint lands. */
  lastHintAtFraction: 0.85,
  /** An empty room is closed after this long (§56). */
  idleRoomMs: 300_000,
  /** Closed rooms are deleted this long after they finish. */
  roomRetentionMs: 86_400_000,
} as const;

/** Hard limits that protect the backend from abuse. */
export const LIMITS = {
  minPlayersToStart: 2,
  minNameLength: 2,
  maxNameLength: 20,
  maxChatLength: 120,
  roomCodeLength: 5,
  /** Rooms one user may own at once. */
  maxRoomsPerUser: 3,
  /** Chat messages per user per window, enforced in the callable (§32). */
  chatRateWindowMs: 10_000,
  chatRateMax: 8,
  /** Guesses per user per window. */
  guessRateWindowMs: 10_000,
  guessRateMax: 12,
  /** Longest accepted free-form report reason. */
  maxReportLength: 200,
  /** Attempts to find a free room code before giving up. */
  roomCodeAttempts: 8,
} as const;

/** Scoring balance (§28). Every number is server-side and configurable. */
export const SCORING = {
  /** Award for a guesser who answers with the whole clock still left. */
  maxGuessPoints: 100,
  /** Award for a guesser who answers as the clock runs out. */
  minGuessPoints: 30,
  /** Order bonuses for the first three correct guesses. */
  orderBonuses: [50, 30, 20] as number[],
  /** Points the drawer earns per player who guessed. */
  drawerPointsPerGuess: 20,
  /** Bonus for a drawer whose word everybody guessed. */
  drawerAllGuessedBonus: 30,
  /** Ceiling on what a drawer can earn in one turn. */
  drawerMaxPoints: 120,
  /** Multiplier applied last, keyed by word difficulty. */
  difficultyMultiplier: { easy: 1.0, medium: 1.15, hard: 1.35 } as Record<
    string,
    number
  >,
} as const;

/**
 * Room code alphabet: deliberately excludes O, 0, I and 1 so a code can be
 * read aloud over a call and typed without ambiguity.
 */
export const ROOM_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Minimum word length before a one-letter typo counts as "close". */
export const CLOSE_GUESS_MIN_LENGTH = 4;
