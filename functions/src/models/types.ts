import { Timestamp } from 'firebase-admin/firestore';

import type { RateState } from '../utils/rateLimit';

import {
  Category,
  Difficulty,
  Language,
  MessageType,
  RoomStatus,
  RoundStatus,
  WordMode,
} from '../config/constants';

/**
 * The Firestore document shapes, exactly as they are written and read.
 *
 * These interfaces are the contract with `lib/models/*.dart` on the client and
 * with `firestore.rules`. A field added here must be added in all three.
 */

/** `users/{userId}` — the public profile (§7). */
export interface UserDoc {
  userId: string;
  displayName: string;
  avatarId: number;
  avatarColorIndex: number;
  photoUrl: string | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  lastSeenAt: Timestamp;
  /** Aggregates. Server-owned: the rules forbid a client from writing these. */
  gamesPlayed: number;
  gamesWon: number;
  totalScore: number;
}

/** The `settings` map on a room (§13). */
export interface RoomSettings {
  maxPlayers: number;
  rounds: number;
  drawTimeSeconds: number;
  wordsToChoose: number;
  hintsEnabled: boolean;
  hintCount: number;
  wordSelectSeconds: number;
  wordMode: WordMode;
  language: Language;
  categories: string[];
  allowVoteKick: boolean;
  isPrivate: boolean;
}

/**
 * The `game` map on a room (§8).
 *
 * Everything here is written only by Cloud Functions. `maskedWord` is the
 * sanitised view of the answer that guessers are allowed to see; the answer
 * itself never appears in this document.
 */
export interface GameState {
  currentRound: number;
  totalRounds: number;
  /** Index into `drawOrder` for the current turn. */
  turnIndex: number;
  /** The order players take the pencil in, fixed when the game starts (§16). */
  drawOrder: string[];
  currentDrawerId: string | null;
  roundStatus: RoundStatus;
  roundStartedAt: Timestamp | null;
  roundEndsAt: Timestamp | null;
  /** e.g. `_ _ E _ A _ _ _`. Safe for every player to see. */
  maskedWord: string;
  /** Number of maskable letters, so the UI can size the blanks. */
  wordLength: number;
  /** How many hints have landed this turn. */
  hintsRevealed: number;
  /** Set only once the round is over, for the reveal screen (§38). */
  revealedWord: string | null;
  /** Correct guessers this turn, in order, for the order bonus. */
  correctOrder: string[];
}

/** `rooms/{roomId}` (§8). */
export interface RoomDoc {
  roomId: string;
  roomCode: string;
  ownerId: string;
  status: RoomStatus;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  maxPlayers: number;
  currentPlayerCount: number;
  settings: RoomSettings;
  game: GameState;
  bannedUserIds: string[];
  /** Set when the room is closed, so the client can explain why (§43). */
  closedReason: string | null;
}

/** `rooms/{roomId}/players/{userId}` (§9). */
export interface PlayerDoc {
  userId: string;
  displayName: string;
  avatarId: number;
  avatarColorIndex: number;
  photoUrl: string | null;
  joinedAt: Timestamp;
  isReady: boolean;
  isConnected: boolean;
  lastSeenAt: Timestamp;
  /** Server-owned from here down (§9). */
  score: number;
  correctGuesses: number;
  hasGuessedCorrectly: boolean;
  /** Points earned this turn, shown on the round-result screen. */
  roundScore: number;
  isMuted: boolean;
  isHost: boolean;
  /** Fixed-window chat/guess rate counters. See `utils/rateLimit.ts`. */
  chatRate?: RateState;
  guessRate?: RateState;
}

/**
 * `rooms/{roomId}/secret/{roundNumber}` — never readable by any client (§18).
 */
export interface RoundSecretDoc {
  roundNumber: number;
  turnIndex: number;
  drawerId: string;
  /** The words offered to the drawer. */
  choices: WordChoice[];
  /** The chosen answer, or null while the drawer is still choosing. */
  word: string | null;
  /** Alternative spellings that also count as correct (§26). */
  aliases: string[];
  difficulty: Difficulty;
  /** Indices of the answer revealed so far by hints. */
  revealedIndices: number[];
}

/** One of the words offered to a drawer (§19). */
export interface WordChoice {
  wordId: string;
  word: string;
  category: Category;
  difficulty: Difficulty;
  aliases: string[];
}

/** `rooms/{roomId}/rounds/{roundNumber}` — the public record (§37). */
export interface RoundResultDoc {
  roundNumber: number;
  turnIndex: number;
  drawerId: string;
  drawerName: string;
  word: string;
  difficulty: Difficulty;
  startedAt: Timestamp;
  endedAt: Timestamp;
  /** Why the round stopped, for the result copy. */
  endReason: 'timeout' | 'all_guessed' | 'drawer_left' | 'skipped';
  awards: ScoreAward[];
}

/** One player's points from one round (§28). */
export interface ScoreAward {
  userId: string;
  displayName: string;
  points: number;
  /** 1-based position among correct guessers; 0 for the drawer or a miss. */
  guessOrder: number;
  role: 'drawer' | 'guesser';
}

/** `rooms/{roomId}/messages/{messageId}` (§31). */
export interface MessageDoc {
  messageId: string;
  userId: string | null;
  displayName: string;
  message: string;
  type: MessageType;
  createdAt: Timestamp;
}

/** `words/{wordId}` (§17). */
export interface WordDoc {
  wordId: string;
  word: string;
  category: Category;
  difficulty: Difficulty;
  language: Language;
  aliases: string[];
}

/** `rooms/{roomId}/votes/{targetUserId}` — a vote-kick ballot (§34). */
export interface VoteDoc {
  targetUserId: string;
  targetName: string;
  voterIds: string[];
  createdAt: Timestamp;
  expiresAt: Timestamp;
}

/** `leaderboard/{userId}` — aggregated all-time standings (§39). */
export interface LeaderboardDoc {
  userId: string;
  displayName: string;
  avatarId: number;
  avatarColorIndex: number;
  totalScore: number;
  gamesPlayed: number;
  gamesWon: number;
  updatedAt: Timestamp;
}
