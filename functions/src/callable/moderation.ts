import { CallableRequest, onCall } from 'firebase-functions/v2/https';

import { LIMITS } from '../config/constants';
import {
  banPlayer as banPlayerService,
  kickPlayer as kickPlayerService,
  mutePlayer as mutePlayerService,
  reportPlayer as reportPlayerService,
  transferHost as transferHostService,
  voteKick as voteKickService,
} from '../services/moderationService';
import { requireAuth } from '../utils/permissions';
import {
  failPrecondition,
  optionalBool,
  requireString,
} from '../utils/validation';

/**
 * Moderation callables (sections 33-34).
 *
 * Every one is a thin wrapper: the authority checks live in
 * `services/moderationService.ts` and run inside the transaction that performs
 * the action, so a host who loses the badge mid-request cannot still use it.
 */

function roomIdOf(request: CallableRequest): string {
  const roomId = String((request.data ?? {}).roomId ?? '');
  if (!roomId) failPrecondition('validation', 'A room id is required.');
  return roomId;
}

function targetIdOf(request: CallableRequest): string {
  return requireString(request.data ?? {}, 'targetUserId', 128);
}

/** Removes a player from the room. Owner only. */
export const kickPlayer = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  await kickPlayerService(roomIdOf(request), uid, targetIdOf(request));
  return { ok: true };
});

/** Removes a player and blocks them from rejoining. Owner only. */
export const banPlayer = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  await banPlayerService(roomIdOf(request), uid, targetIdOf(request));
  return { ok: true };
});

/** Silences or unsilences a player in chat. Owner only. */
export const mutePlayer = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const muted = optionalBool(request.data ?? {}, 'muted', true);
  await mutePlayerService(roomIdOf(request), uid, targetIdOf(request), muted);
  return { ok: true, muted };
});

/** Files a report against a player. Any member may report. */
export const reportPlayer = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const reason = requireString(
    request.data ?? {},
    'reason',
    LIMITS.maxReportLength
  );
  await reportPlayerService({
    roomId: roomIdOf(request),
    reporterId: uid,
    targetId: targetIdOf(request),
    reason,
  });
  return { ok: true };
});

/** Casts a vote to remove a player (section 34). */
export const voteKick = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  return voteKickService(roomIdOf(request), uid, targetIdOf(request));
});

/** Hands the host badge to another player. Owner only. */
export const transferHost = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  await transferHostService(roomIdOf(request), uid, targetIdOf(request));
  return { ok: true };
});
