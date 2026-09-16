/**
 * Environment driven configuration with sane, production-ready defaults.
 *
 * Every number the game loop depends on lives here so tests can shrink the
 * timings (START_COUNTDOWN_MS=50 npm test) without touching game code.
 * The ranges mirror lib/models/room_settings.dart validate() and
 * lib/core/constants/game_defaults.dart exactly - both sides must agree.
 */

import { normalizeLevel } from './logger.js';

/** Reads an integer from the environment, clamped to [min, max]. */
function envInt(name, fallback, min = Number.MIN_SAFE_INTEGER, max = Number.MAX_SAFE_INTEGER) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') return fallback;
  const parsed = Number.parseInt(String(raw).trim(), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

/** Reads a float from the environment, clamped to [min, max]. */
function envFloat(name, fallback, min = -Infinity, max = Infinity) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') return fallback;
  const parsed = Number.parseFloat(String(raw).trim());
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

/** Reads a boolean from the environment (1/true/yes/on). */
function envBool(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') return fallback;
  const value = String(raw).trim().toLowerCase();
  if (value === '1' || value === 'true' || value === 'yes' || value === 'on') return true;
  if (value === '0' || value === 'false' || value === 'no' || value === 'off') return false;
  return fallback;
}

/**
 * Parses CORS_ORIGIN. A bare "*" (the default) allows every origin, which is
 * what a Flutter mobile client needs; a comma separated list is an allowlist.
 */
function envOrigin(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') return fallback;
  const value = String(raw).trim();
  if (value === '*') return '*';
  const list = value
    .split(',')
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
  return list.length > 0 ? list : fallback;
}

/** Pulls value inside the inclusive range, mirroring Dart IntRange.coerce. */
export function clampRange(value, range, fallback) {
  const number = Number.isFinite(value) ? Math.trunc(value) : fallback;
  return Math.min(range.max, Math.max(range.min, number));
}

/** Allowed room-settings ranges. Mirrors GameDefaults on the client. */
export const RANGES = Object.freeze({
  maxPlayers: Object.freeze({ min: 2, max: 12 }),
  rounds: Object.freeze({ min: 1, max: 10 }),
  drawTimeSeconds: Object.freeze({ min: 30, max: 180 }),
  wordChoiceCount: Object.freeze({ min: 2, max: 5 }),
  hintCount: Object.freeze({ min: 0, max: 5 }),
  wordSelectSeconds: Object.freeze({ min: 5, max: 30 }),
});

/** Default room settings. Mirrors RoomSettings.defaults. */
export const DEFAULT_SETTINGS = Object.freeze({
  maxPlayers: 8,
  rounds: 3,
  drawTimeSeconds: 80,
  wordChoiceCount: 3,
  hintCount: 2,
  wordSelectSeconds: 15,
  wordMode: 'choose',
  language: 'en',
  categories: Object.freeze(['random']),
  customWords: Object.freeze([]),
  allowVoteKick: true,
  isPrivate: false,
});

export const config = Object.freeze({
  /** HTTP port. */
  port: envInt('PORT', 3000, 0, 65535),
  /** Interface to bind. 0.0.0.0 makes the server reachable from a phone. */
  host: (process.env.HOST || '').trim() || '0.0.0.0',
  /** "*" or an explicit origin allowlist. */
  corsOrigin: envOrigin('CORS_ORIGIN', '*'),
  /** Logger level: debug | info | warn | error | silent. */
  logLevel: normalizeLevel(process.env.LOG_LEVEL, 'info'),
  /** Whether /stats lists room codes. Off by default: codes are secrets. */
  exposeRoomCodes: envBool('EXPOSE_ROOM_CODES', false),

  timing: Object.freeze({
    /** Lobby to first turn countdown. GameDefaults.startCountdownSeconds. */
    startCountdownMs: envInt('START_COUNTDOWN_MS', 3000, 0, 30000),
    /** How long the round result stays up. GameDefaults.roundEndSeconds. */
    roundEndMs: envInt('ROUND_END_MS', 6000, 0, 60000),
    /** How long final standings stay up before the lobby returns. */
    gameEndMs: envInt('GAME_END_MS', 15000, 0, 120000),
    /** Reconnect grace: a seat is held this long after a socket drops. */
    reconnectGraceMs: envInt('RECONNECT_GRACE_MS', 45000, 0, 600000),
    /** Slack added to the turn deadline. GameDefaults.turnGraceMs. */
    turnGraceMs: envInt('TURN_GRACE_MS', 400, 0, 5000),
    /** Clock broadcast period. AppConstants.timeSyncIntervalSeconds. */
    timeSyncIntervalMs: envInt('TIME_SYNC_INTERVAL_MS', 20000, 1000, 600000),
    /** An empty room is destroyed after this long. */
    idleRoomMs: envInt('IDLE_ROOM_MS', 300000, 1000, 86400000),
    /** How often the reaper looks for idle rooms. */
    reaperIntervalMs: envInt('REAPER_INTERVAL_MS', 30000, 1000, 3600000),
    /** Fraction of the turn elapsed before the first hint lands. */
    firstHintAtFraction: envFloat('FIRST_HINT_FRACTION', 0.45, 0.05, 0.95),
    /** Fraction of the turn after which no further hint lands. */
    lastHintAtFraction: envFloat('LAST_HINT_FRACTION', 0.85, 0.05, 0.99),
  }),

  limits: Object.freeze({
    /** Hard ceiling on concurrent rooms. */
    maxRooms: envInt('MAX_ROOMS', 5000, 1, 1000000),
    /** Players needed before a match may start. */
    minPlayersToStart: envInt('MIN_PLAYERS_TO_START', 2, 2, 12),
    /** AppConstants.minNameLength / maxNameLength. */
    minNameLength: 2,
    maxNameLength: 16,
    /** AppConstants.maxChatLength. */
    maxChatLength: 120,
    /** AppConstants.roomCodeLength. */
    roomCodeLength: 5,
    /** Cap on points accepted in a single c:draw:append. */
    maxPointsPerAppend: envInt('MAX_POINTS_PER_APPEND', 200, 1, 2000),
    /** Cap on points a single stroke may accumulate. */
    maxPointsPerStroke: envInt('MAX_POINTS_PER_STROKE', 4000, 8, 50000),
    /** AppConstants.maxStrokesPerBoard. */
    maxStrokesPerBoard: envInt('MAX_STROKES_PER_BOARD', 4000, 16, 20000),
    /** Strokes kept on the redo stack per board. */
    maxRedoStack: 64,
    /** AppConstants.chatHistoryLimit. */
    chatHistoryLimit: 200,
    /** Custom word list caps. GameDefaults.minCustomWords is 5. */
    minCustomWords: 5,
    maxCustomWords: envInt('MAX_CUSTOM_WORDS', 200, 5, 2000),
    minCustomWordLength: 2,
    maxCustomWordLength: 24,
    /** Longest accepted free-form report reason. */
    maxReportLength: 200,
    /** Socket.IO payload ceiling, in bytes. */
    maxHttpBufferSize: envInt('MAX_HTTP_BUFFER_SIZE', 262144, 4096, 8388608),
  }),

  /** Per-socket token buckets. capacity is burst, refillPerSec sustained. */
  rate: Object.freeze({
    chat: Object.freeze({ capacity: 10, refillPerSec: envFloat('RATE_CHAT_PER_SEC', 5, 0.1, 1000) }),
    draw: Object.freeze({ capacity: 120, refillPerSec: envFloat('RATE_DRAW_PER_SEC', 60, 1, 5000) }),
    room: Object.freeze({ capacity: 20, refillPerSec: envFloat('RATE_ROOM_PER_SEC', 10, 0.1, 1000) }),
    time: Object.freeze({ capacity: 20, refillPerSec: envFloat('RATE_TIME_PER_SEC', 10, 0.1, 1000) }),
  }),

  ranges: RANGES,
  defaultSettings: DEFAULT_SETTINGS,
});

export default config;
