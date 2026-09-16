import { Transaction } from 'firebase-admin/firestore';

import { playerRef } from '../services/roomService';
import { failPrecondition } from './validation';

/**
 * A fixed-window rate limiter kept on the player document (section 32).
 *
 * Per-instance counters are useless here: Cloud Functions scale horizontally,
 * so a client that opens enough connections lands on enough instances to make
 * an in-memory limit meaningless. The counter therefore lives in Firestore,
 * next to the player, and is updated inside the same transaction that accepts
 * the message — which makes the check and the write atomic, so a burst of
 * simultaneous requests cannot all read the same low count and pass.
 *
 * A fixed window (rather than a token bucket) is deliberate: it costs one
 * number and one timestamp, and the failure mode — a player briefly getting
 * double the allowance across a window boundary — is harmless for chat.
 */

export interface RateState {
  windowStartMs: number;
  count: number;
}

/** The rate counters a player document may carry. */
export interface PlayerRateFields {
  chatRate?: RateState;
  guessRate?: RateState;
}

/**
 * Consumes one unit of a player's allowance, or refuses the request.
 *
 * Returns the new state, which the caller must write as part of its own
 * transaction — that is what keeps the check atomic.
 */
export function consume(args: {
  current: RateState | undefined;
  nowMs: number;
  windowMs: number;
  max: number;
  message: string;
}): RateState {
  const { current, nowMs, windowMs, max, message } = args;

  const withinWindow =
    current !== undefined && nowMs - current.windowStartMs < windowMs;

  if (!withinWindow) {
    return { windowStartMs: nowMs, count: 1 };
  }
  if (current.count >= max) {
    failPrecondition('invalidAction', message);
  }
  return { windowStartMs: current.windowStartMs, count: current.count + 1 };
}

/** Writes a consumed rate state back onto the player document. */
export function persist(
  tx: Transaction,
  roomId: string,
  userId: string,
  field: 'chatRate' | 'guessRate',
  state: RateState
): void {
  tx.update(playerRef(roomId, userId), { [field]: state });
}
