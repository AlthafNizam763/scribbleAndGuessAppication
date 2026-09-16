import { FieldValue } from 'firebase-admin/firestore';
import { CallableRequest, onCall } from 'firebase-functions/v2/https';

import { endTurn } from '../services/gameService';
import {
  db,
  playerRef,
  readRoom,
  removePlayer,
  roomRef,
} from '../services/roomService';
import { logger } from '../utils/logger';
import { requireAuth } from '../utils/permissions';
import { failPrecondition, optionalBool } from '../utils/validation';

/**
 * Leaves a room (section 36).
 *
 * When the leaver is the current drawer the turn cannot continue - nobody else
 * knows the word - so it ends immediately rather than running down a clock
 * nobody is drawing against.
 */
export const leaveRoom = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const roomId = String((request.data ?? {}).roomId ?? '');
  if (!roomId) failPrecondition('validation', 'A room id is required.');

  const outcome = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    const result = await removePlayer(tx, roomId, room, uid, 'left');
    return { ...result, turnIndex: room.game.turnIndex };
  });

  if (outcome.drawerLeft && !outcome.roomClosed) {
    await endTurn(roomId, outcome.turnIndex, 'drawer_left');
  }

  logger.info('room.left', { roomId, uid, roomClosed: outcome.roomClosed });
  return { ok: true, roomClosed: outcome.roomClosed };
});

/**
 * Sets the caller's ready flag in the lobby (section 12).
 *
 * Kept as a callable rather than a direct Firestore write so the room's status
 * is checked server-side: a client cannot mark itself ready during a live
 * round to confuse the lobby's start conditions.
 */
export const updateReadyStatus = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const data = request.data ?? {};
  const roomId = String(data.roomId ?? '');
  if (!roomId) failPrecondition('validation', 'A room id is required.');

  const isReady = optionalBool(data, 'isReady', false);

  await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (room.status !== 'waiting') {
      failPrecondition('invalidAction', 'The game has already started.');
    }
    const player = await tx.get(playerRef(roomId, uid));
    if (!player.exists) {
      failPrecondition('invalidAction', 'You are not in this room.');
    }

    tx.update(playerRef(roomId, uid), { isReady });
    tx.update(roomRef(roomId), { updatedAt: FieldValue.serverTimestamp() });
  });

  return { ok: true, isReady };
});
