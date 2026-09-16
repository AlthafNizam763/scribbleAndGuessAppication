import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onTaskDispatched } from 'firebase-functions/v2/tasks';

import { TIMING } from './config/constants';
import { RoomDoc } from './models/types';
import {
  beginNextTurn,
  applyDueHints,
  endTurn,
} from './services/gameService';
import { reapDisconnected } from './services/presenceService';
import { closeRoom } from './services/roomService';
import { TickPayload } from './services/schedulerService';
import { logger } from './utils/logger';

// The admin app must exist before any service module touches Firestore.
initializeApp();

// europe/us choice belongs in deployment config; the concurrency and instance
// caps here are what keep a runaway loop from becoming a runaway bill.
setGlobalOptions({
  region: 'us-central1',
  maxInstances: 20,
  concurrency: 40,
});

// ---------------------------------------------------------------------------
// Callables (section 54)
// ---------------------------------------------------------------------------

export { createRoom, updateRoomSettings } from './callable/createRoom';
export { joinRoom } from './callable/joinRoom';
export { leaveRoom, updateReadyStatus } from './callable/leaveRoom';
export {
  endRound,
  getWordChoices,
  nextRound,
  restartGame,
  selectWord,
  startGame,
} from './callable/gameFlow';
export { sendMessage, submitGuess } from './callable/chat';
export {
  banPlayer,
  kickPlayer,
  mutePlayer,
  reportPlayer,
  transferHost,
  voteKick,
} from './callable/moderation';
export { getServerTime, heartbeat } from './callable/presence';

// ---------------------------------------------------------------------------
// The authoritative clock (section 29)
// ---------------------------------------------------------------------------

/**
 * Wakes the engine at a scheduled moment: a hint, the end of a turn, or the
 * start of the next one.
 *
 * Enqueued by `schedulerService.scheduleTick` with an exact `scheduleTime`.
 * Every handler it calls is idempotent and guarded on the turn index, so a
 * retried or duplicated task cannot double-score or skip a turn.
 */
export const gameTick = onTaskDispatched<TickPayload>(
  {
    retryConfig: { maxAttempts: 3, minBackoffSeconds: 2 },
    rateLimits: { maxConcurrentDispatches: 40 },
  },
  async (request) => {
    const { roomId, turnIndex, kind } = request.data;
    logger.debug('tick', { roomId, turnIndex, kind });

    try {
      switch (kind) {
        case 'hint':
          await applyDueHints(roomId, turnIndex);
          break;
        case 'end':
          await endTurn(roomId, turnIndex, 'timeout');
          break;
        case 'next':
          await beginNextTurn(roomId);
          break;
      }
    } catch (error) {
      logger.error('tick.failed', error, { roomId, turnIndex, kind });
      throw error;
    }
  }
);

/**
 * The safety net (sections 29, 36, 56).
 *
 * Cloud Tasks are reliable but not guaranteed, and a room whose tick was lost
 * would otherwise sit frozen forever with players staring at a dead timer.
 * Once a minute this sweep looks for rooms whose deadline has passed and
 * finishes what the tick should have done — plus reaps players who have gone
 * silent and closes rooms that have emptied out.
 */
export const sweepGames = onSchedule(
  { schedule: 'every 1 minutes', timeoutSeconds: 120 },
  async () => {
    const db = getFirestore();
    const now = Date.now();

    const active = await db
      .collection('rooms')
      .where('status', 'in', ['waiting', 'starting', 'playing', 'round_result'])
      .limit(200)
      .get();

    for (const doc of active.docs) {
      const room = doc.data() as RoomDoc;
      const roomId = doc.id;

      try {
        // An empty room is closed rather than swept forever.
        const updated = room.updatedAt?.toMillis() ?? 0;
        if (room.currentPlayerCount <= 0 && now - updated > TIMING.idleRoomMs) {
          await closeRoom(roomId, 'The room was empty.');
          continue;
        }

        // Drop players who stopped heartbeating; cut the turn if that took
        // the drawer with them.
        const reaped = await reapDisconnected(roomId);
        if (reaped.drawerLost) {
          await endTurn(roomId, room.game.turnIndex, 'drawer_left');
          continue;
        }

        const endsAt = room.game.roundEndsAt?.toMillis() ?? 0;
        if (endsAt === 0 || now < endsAt + TIMING.turnGraceMs) continue;

        switch (room.game.roundStatus) {
          case 'word_selection':
          case 'drawing':
            await endTurn(roomId, room.game.turnIndex, 'timeout');
            break;
          case 'round_result':
            await beginNextTurn(roomId);
            break;
          case 'starting':
            await beginNextTurn(roomId);
            break;
          default:
            break;
        }
      } catch (error) {
        logger.error('sweep.roomFailed', error, { roomId });
      }
    }
  }
);

/**
 * Deletes the remains of games that finished long ago (section 56).
 *
 * Rooms are kept for a day so a player can still open a result screen, then
 * removed with their messages, rounds and secrets. Runs hourly because it is
 * pure housekeeping and nothing waits on it.
 */
export const cleanupRooms = onSchedule(
  { schedule: 'every 60 minutes', timeoutSeconds: 300 },
  async () => {
    const db = getFirestore();
    const cutoff = Date.now() - TIMING.roomRetentionMs;

    const stale = await db
      .collection('rooms')
      .where('status', 'in', ['closed', 'finished'])
      .limit(100)
      .get();

    let deleted = 0;
    for (const doc of stale.docs) {
      const room = doc.data() as RoomDoc;
      if ((room.updatedAt?.toMillis() ?? 0) > cutoff) continue;

      try {
        // recursiveDelete removes the subcollections too, which a plain
        // document delete would silently orphan.
        await db.recursiveDelete(doc.ref);
        deleted++;
      } catch (error) {
        logger.error('cleanup.roomFailed', error, { roomId: doc.id });
      }
    }
    if (deleted > 0) logger.info('cleanup.done', { deleted });
  }
);

