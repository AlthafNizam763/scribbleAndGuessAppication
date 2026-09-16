import { CallableRequest, onCall } from 'firebase-functions/v2/https';

import { heartbeat as heartbeatService } from '../services/presenceService';
import { requireAuth } from '../utils/permissions';
import { failPrecondition } from '../utils/validation';

/**
 * Presence heartbeat (section 35).
 *
 * Clients call this on a slow timer while they are in a room. It is
 * deliberately the cheapest callable in the product — one read, usually one
 * field write — because it is also the most frequent.
 */
export const heartbeat = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const roomId = String((request.data ?? {}).roomId ?? '');
  if (!roomId) failPrecondition('validation', 'A room id is required.');

  const result = await heartbeatService(roomId, uid);
  return { ok: result.accepted, serverTimeMs: Date.now() };
});

/**
 * Returns the server's clock.
 *
 * The client uses this to measure its offset from server time so it can render
 * a countdown that agrees with the deadline the server will actually enforce
 * (section 29). Rendering the round timer from an unadjusted device clock is
 * how players end up seeing "3 seconds left" after the round has already
 * closed.
 */
export const getServerTime = onCall(async () => {
  return { serverTimeMs: Date.now() };
});
