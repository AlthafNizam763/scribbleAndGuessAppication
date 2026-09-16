import { CallableRequest, onCall } from 'firebase-functions/v2/https';

import { RoundSecretDoc } from '../models/types';
import {
  beginNextTurn,
  endTurn,
  startGame as startGameEngine,
  selectWord as selectWordEngine,
} from '../services/gameService';
import { db, readRoom, secretRef } from '../services/roomService';
import { logger } from '../utils/logger';
import { requireAuth } from '../utils/permissions';
import { failPrecondition, requireInt } from '../utils/validation';

/**
 * The game-flow callables (sections 15, 19, 37, 38, 40).
 *
 * Each one is a thin, validated entry point onto the engine in
 * `services/gameService.ts`. None of them decides anything: the client says
 * what it wants to happen, and the engine decides whether it may (section 50).
 */

/** Reads the caller's room id, or fails. */
function roomIdOf(request: CallableRequest): string {
  const roomId = String((request.data ?? {}).roomId ?? '');
  if (!roomId) failPrecondition('validation', 'A room id is required.');
  return roomId;
}

/** Starts the match. Owner only (section 15). */
export const startGame = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const roomId = roomIdOf(request);
  await startGameEngine(roomId, uid);
  return { ok: true };
});

/**
 * Returns the words the drawer may choose between (section 19).
 *
 * This is the *only* path by which word choices reach a client, and it hands
 * them to the current drawer alone — the `secret` subcollection they are
 * stored in is unreadable to every client, including this one (section 18).
 */
export const getWordChoices = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const roomId = roomIdOf(request);

  const room = await db().runTransaction((tx) => readRoom(tx, roomId));
  if (room.game.currentDrawerId !== uid) {
    failPrecondition('notDrawer', 'Only the drawer can see the words.');
  }
  if (room.game.roundStatus !== 'word_selection') {
    failPrecondition('invalidAction', 'The word has already been chosen.');
  }

  const snapshot = await secretRef(roomId, room.game.turnIndex).get();
  if (!snapshot.exists) {
    failPrecondition('serverError', 'This round is no longer available.');
  }
  const secret = snapshot.data() as RoundSecretDoc;

  // Only the words themselves — never the ids or aliases, which would give a
  // determined drawer a way to fingerprint the bank.
  return {
    turnIndex: secret.turnIndex,
    choices: secret.choices.map((c) => ({
      word: c.word,
      category: c.category,
      difficulty: c.difficulty,
    })),
    endsAtMs: room.game.roundEndsAt?.toMillis() ?? null,
  };
});

/** Records the drawer's choice and opens the drawing phase (section 19). */
export const selectWord = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const roomId = roomIdOf(request);
  const index = requireInt(request.data ?? {}, 'choiceIndex', 0, 9);

  const result = await selectWordEngine(roomId, uid, index);
  return { word: result.word, endsAtMs: result.endsAtMs };
});

/**
 * Ends the current round (section 37).
 *
 * Callable by any player, but it only does anything once the server's own
 * clock says the deadline has passed. That is what lets a client whose timer
 * hits zero nudge the round along without ever being able to cut one short:
 * the deadline is the server's, not theirs (section 29).
 */
export const endRound = onCall(async (request: CallableRequest) => {
  requireAuth(request);
  const roomId = roomIdOf(request);

  const room = await db().runTransaction((tx) => readRoom(tx, roomId));
  const endsAt = room.game.roundEndsAt?.toMillis() ?? 0;
  if (Date.now() < endsAt) {
    // Not an error: the caller's clock was simply a little fast.
    return { ok: false, reason: 'not_due' };
  }

  await endTurn(roomId, room.game.turnIndex, 'timeout');
  return { ok: true };
});

/**
 * Moves on to the next turn (section 38).
 *
 * Same rule as `endRound`: the intermission has to have actually elapsed, so
 * no client can skip past the round result everyone else is still reading.
 */
export const nextRound = onCall(async (request: CallableRequest) => {
  requireAuth(request);
  const roomId = roomIdOf(request);

  const room = await db().runTransaction((tx) => readRoom(tx, roomId));
  if (room.game.roundStatus !== 'round_result') {
    return { ok: false, reason: 'not_in_result' };
  }
  const endsAt = room.game.roundEndsAt?.toMillis() ?? 0;
  if (Date.now() < endsAt) {
    return { ok: false, reason: 'not_due' };
  }

  await beginNextTurn(roomId);
  return { ok: true };
});

/**
 * Plays the same room again (section 40).
 *
 * Keeps the room code, the players and the settings; resets the rotation, the
 * scores and every per-round flag. Implemented by re-entering `startGame`,
 * which already does exactly that reset, so there is only one code path that
 * can begin a match.
 */
export const restartGame = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const roomId = roomIdOf(request);

  const room = await db().runTransaction((tx) => readRoom(tx, roomId));
  if (room.ownerId !== uid) {
    failPrecondition('notHost', 'Only the room owner can restart the game.');
  }
  if (room.status !== 'finished') {
    failPrecondition('invalidAction', 'The current game has not finished yet.');
  }

  await startGameEngine(roomId, uid);
  logger.info('game.restarted', { roomId, uid });
  return { ok: true };
});
