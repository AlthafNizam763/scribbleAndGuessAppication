import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { TIMING } from '../config/constants';
import { PlayerDoc, RoomDoc } from '../models/types';
import { logger } from '../utils/logger';
import { db, playerRef, readRoom, removePlayer, roomRef } from './roomService';

/**
 * Presence and reconnection (sections 35-36).
 *
 * Presence is deliberately coarse. Writing "still here" every second would
 * cost a Firestore write per player per second and buy nothing a 15-second
 * heartbeat does not, so clients beat slowly and the server infers absence
 * from a stale timestamp rather than from a disconnect event it may never see
 * (a phone in a tunnel does not get to send a goodbye).
 */

/**
 * Records that a player is still present.
 *
 * Cheap by design: a single field write, and only when the previous heartbeat
 * is old enough to be worth replacing.
 */
export async function heartbeat(
  roomId: string,
  userId: string
): Promise<{ accepted: boolean }> {
  const reference = playerRef(roomId, userId);
  const snapshot = await reference.get();
  if (!snapshot.exists) return { accepted: false };

  const player = snapshot.data() as PlayerDoc;
  const last = player.lastSeenAt?.toMillis() ?? 0;
  const now = Date.now();

  // Debounce: skip the write when a recent one already says the same thing.
  if (player.isConnected && now - last < TIMING.heartbeatIntervalMs / 2) {
    return { accepted: true };
  }

  await reference.update({
    lastSeenAt: Timestamp.fromMillis(now),
    isConnected: true,
  });
  return { accepted: true };
}

/** Marks a player as disconnected without giving up their seat. */
export async function markDisconnected(
  roomId: string,
  userId: string
): Promise<void> {
  try {
    await playerRef(roomId, userId).update({ isConnected: false });
  } catch (error) {
    logger.error('presence.markDisconnectedFailed', error, { roomId, userId });
  }
}

/**
 * Drops players who have gone quiet for longer than the grace period.
 *
 * Returns whether the room still has a live drawer, so the caller can decide
 * to cut the round short. A seat is held for
 * {@link TIMING.reconnectGraceMs} - long enough to survive a lift, a tunnel or
 * an app switch - because taking someone's seat and score away for a
 * ten-second blip is a far worse failure than a slightly stale player list.
 */
export async function reapDisconnected(roomId: string): Promise<{
  removed: string[];
  drawerLost: boolean;
}> {
  const removed: string[] = [];
  let drawerLost = false;

  const outcome = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (room.status === 'closed') return { removed: [], drawerLost: false };

    const snapshot = await tx.get(roomRef(roomId).collection('players'));
    const now = Date.now();
    const stale: PlayerDoc[] = [];

    for (const doc of snapshot.docs) {
      const player = doc.data() as PlayerDoc;
      const last = player.lastSeenAt?.toMillis() ?? 0;
      const silentFor = now - last;

      // The drawer gets a shorter leash: the whole room is waiting on them.
      const grace =
        player.userId === room.game.currentDrawerId
          ? TIMING.drawerGraceMs
          : TIMING.reconnectGraceMs;

      if (silentFor > grace) stale.push(player);
      else if (player.isConnected && silentFor > TIMING.presenceTimeoutMs) {
        tx.update(playerRef(roomId, player.userId), { isConnected: false });
      }
    }

    for (const player of stale) {
      const result = await removePlayer(
        tx,
        roomId,
        room,
        player.userId,
        'timeout'
      );
      removed.push(player.userId);
      if (result.drawerLeft) drawerLost = true;
      if (result.roomClosed) break;
    }

    return { removed, drawerLost };
  });

  if (outcome.removed.length > 0) {
    logger.info('presence.reaped', { roomId, ...outcome });
  }
  return outcome;
}

/**
 * Restores a returning player's seat.
 *
 * Reconnection is not a rejoin: the player document was never deleted, so the
 * score, the guessed-flag and the position in the draw order are all still
 * there. All that has to happen is flipping the connection flag back.
 */
export async function reconnect(
  roomId: string,
  userId: string
): Promise<{ restored: boolean; room: RoomDoc | null }> {
  return db().runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef(roomId));
    if (!roomSnap.exists) return { restored: false, room: null };
    const room = roomSnap.data() as RoomDoc;
    if (room.status === 'closed') return { restored: false, room };

    const playerSnap = await tx.get(playerRef(roomId, userId));
    if (!playerSnap.exists) return { restored: false, room };

    tx.update(playerRef(roomId, userId), {
      isConnected: true,
      lastSeenAt: FieldValue.serverTimestamp(),
    });
    return { restored: true, room };
  });
}
