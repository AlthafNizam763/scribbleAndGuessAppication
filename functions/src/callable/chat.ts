import { CallableRequest, onCall } from 'firebase-functions/v2/https';

import { LIMITS } from '../config/constants';
import { PlayerDoc, RoundSecretDoc } from '../models/types';
import { submitGuess as submitGuessEngine } from '../services/gameService';
import {
  db,
  readPlayer,
  readRoom,
  secretRef,
  writeMessage,
} from '../services/roomService';
import { evaluateGuess } from '../services/wordService';
import { requireAuth } from '../utils/permissions';
import { PlayerRateFields, consume, persist } from '../utils/rateLimit';
import { failPrecondition, sanitizeMessage } from '../utils/validation';

/**
 * Chat and guessing (sections 25, 31, 32).
 *
 * These two callables are separate because they have different consequences: a
 * guess can score points and end a round, a chat line cannot. Keeping them
 * apart means the scoring path is small enough to reason about, and it means
 * chat can stay open to players who have already guessed without giving them a
 * second bite at the points.
 */

function roomIdOf(request: CallableRequest): string {
  const roomId = String((request.data ?? {}).roomId ?? '');
  if (!roomId) failPrecondition('validation', 'A room id is required.');
  return roomId;
}

/**
 * Posts a chat message.
 *
 * The interesting guard here is the last one: while a round is live, nobody —
 * not a player who has already guessed, and above all not the drawer — may
 * post the answer as chat. Without that check the drawer could simply type the
 * word, and every "secret word" protection elsewhere in the system would be
 * worth nothing (section 18).
 */
export const sendMessage = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const roomId = roomIdOf(request);
  const text = sanitizeMessage((request.data ?? {}).message);

  await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    const player = await readPlayer(tx, roomId, uid);
    if (!player) {
      failPrecondition('invalidAction', 'You are not in this room.');
    }
    if (player.isMuted) {
      failPrecondition('invalidAction', 'You have been muted in this room.');
    }

    const now = Date.now();
    const rate = consume({
      current: (player as PlayerDoc & PlayerRateFields).chatRate,
      nowMs: now,
      windowMs: LIMITS.chatRateWindowMs,
      max: LIMITS.chatRateMax,
      message: 'You are sending messages too quickly.',
    });

    // While a word is live, chat must not be able to carry it.
    if (room.game.roundStatus === 'drawing') {
      const snapshot = await tx.get(secretRef(roomId, room.game.turnIndex));
      if (snapshot.exists) {
        const secret = snapshot.data() as RoundSecretDoc;
        if (secret.word) {
          const verdict = evaluateGuess(text, secret.word, secret.aliases);
          if (verdict === 'correct') {
            failPrecondition(
              'invalidAction',
              'You cannot say that while the round is running.'
            );
          }
        }
      }
    }

    persist(tx, roomId, uid, 'chatRate', rate);
    writeMessage(tx, roomId, {
      userId: uid,
      displayName: player.displayName,
      message: text,
      type: 'chat',
    });
  });

  return { ok: true };
});

/**
 * Submits a guess (section 25).
 *
 * Rate limiting runs here, before the engine, so a client cannot brute-force
 * the answer one letter at a time: the window allows a human typing quickly
 * and refuses a script.
 */
export const submitGuess = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const roomId = roomIdOf(request);
  const text = sanitizeMessage((request.data ?? {}).guess);

  await db().runTransaction(async (tx) => {
    const player = await readPlayer(tx, roomId, uid);
    if (!player) {
      failPrecondition('invalidAction', 'You are not in this room.');
    }
    const rate = consume({
      current: (player as PlayerDoc & PlayerRateFields).guessRate,
      nowMs: Date.now(),
      windowMs: LIMITS.guessRateWindowMs,
      max: LIMITS.guessRateMax,
      message: 'You are guessing too quickly. Take a breath!',
    });
    persist(tx, roomId, uid, 'guessRate', rate);
  });

  const outcome = await submitGuessEngine(roomId, uid, text);

  // The verdict goes back to the guesser alone. A "close" result in particular
  // is never broadcast: telling the room that someone is one letter away is
  // itself a hint (section 27).
  return {
    verdict: outcome.verdict,
    points: outcome.points,
    roundOver: outcome.roundOver,
  };
});
