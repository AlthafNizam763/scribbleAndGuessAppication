import { getFunctions } from 'firebase-admin/functions';

import { logger } from '../utils/logger';

/**
 * Wakes the game engine up at an exact moment.
 *
 * The round clock has to be server-authoritative (section 29): a client that
 * simply stops calling `endRound` must not be able to freeze a round forever,
 * and a client that calls it early must not be able to cut one short. So every
 * deadline the game cares about - each hint, the end of the turn, the gap
 * before the next one - is enqueued here as a Cloud Task with an explicit
 * `scheduleTime`, and the queue calls us back.
 *
 * `sweepGames` in `index.ts` is the safety net: if a task is ever lost, the
 * sweep notices the overdue deadline within a minute and finishes the turn.
 * The engine is idempotent, so a task and the sweep both firing is harmless.
 */

/** What the engine should do when it wakes. */
export type TickKind = 'hint' | 'end' | 'next';

export interface TickPayload {
  roomId: string;
  /** Pins the tick to one turn, so a stale task cannot disturb a later one. */
  turnIndex: number;
  kind: TickKind;
}

/**
 * Enqueues a game tick for `atMs`.
 *
 * Failures are logged and swallowed rather than thrown: a missed task degrades
 * to the one-minute sweep, whereas letting the error escape would fail the
 * player's action (their guess, their word choice) for a reason that has
 * nothing to do with them.
 */
export async function scheduleTick(
  payload: TickPayload,
  atMs: number
): Promise<void> {
  try {
    const queue = getFunctions().taskQueue<TickPayload>('gameTick');
    await queue.enqueue(payload, {
      scheduleTime: new Date(Math.max(Date.now(), atMs)),
    });
  } catch (error) {
    logger.error('scheduler.enqueueFailed', error, {
      roomId: payload.roomId,
      turnIndex: payload.turnIndex,
      kind: payload.kind,
    });
  }
}
