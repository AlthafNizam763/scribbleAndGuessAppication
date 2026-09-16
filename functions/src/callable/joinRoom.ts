import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { CallableRequest, onCall } from 'firebase-functions/v2/https';

import { RoomDoc } from '../models/types';
import {
  db,
  findRoomByCode,
  newPlayerDoc,
  playerRef,
  roomRef,
  systemMessage,
} from '../services/roomService';
import { logger } from '../utils/logger';
import { requireAuth } from '../utils/permissions';
import { isValidRoomCode, normalizeRoomCode } from '../utils/random';
import {
  failPrecondition,
  optionalString,
  requireInt,
  sanitizeDisplayName,
} from '../utils/validation';

/**
 * Joins a room by code (section 11).
 *
 * The capacity check and the seat write happen in one transaction, which is
 * what stops two players both taking the last seat: the second transaction
 * re-reads the roster, sees the room is full, and fails.
 *
 * Someone already in the room is treated as reconnecting rather than rejected,
 * so tapping "join" again after a dropped connection restores their seat and
 * score instead of refusing them (section 36).
 */
export const joinRoom = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const data = request.data ?? {};

  const rawCode = normalizeRoomCode(data.roomCode);
  if (!isValidRoomCode(rawCode)) {
    failPrecondition('invalidCode', 'That room code is not valid.');
  }

  const displayName = sanitizeDisplayName(data.displayName);
  const avatarId = requireInt(data, 'avatarId', 0, 63);
  const avatarColorIndex = requireInt(data, 'avatarColorIndex', 0, 15);
  const photoUrl = optionalString(data, 'photoUrl', 512);

  const { roomId } = await findRoomByCode(rawCode);

  const result = await db().runTransaction(async (tx) => {
    const snapshot = await tx.get(roomRef(roomId));
    if (!snapshot.exists) {
      failPrecondition('roomNotFound', 'That room no longer exists.');
    }
    const room = snapshot.data() as RoomDoc;

    if (room.status === 'closed' || room.status === 'finished') {
      failPrecondition('roomNotFound', 'That game has already ended.');
    }
    if (room.bannedUserIds.includes(uid)) {
      failPrecondition('banned', 'You have been banned from this room.');
    }

    const existing = await tx.get(playerRef(roomId, uid));
    if (existing.exists) {
      tx.update(playerRef(roomId, uid), {
        isConnected: true,
        lastSeenAt: FieldValue.serverTimestamp(),
        displayName,
        avatarId,
        avatarColorIndex,
        photoUrl,
      });
      return { roomId, roomCode: room.roomCode, rejoined: true };
    }

    const players = await tx.get(roomRef(roomId).collection('players'));
    if (players.size >= room.settings.maxPlayers) {
      failPrecondition('roomFull', 'That room is full.');
    }

    // Two players called "Rahul" on one scoreboard is a real usability problem
    // during a guessing game, so later arrivals are numbered, not turned away.
    const taken = players.docs.map((d) => String(d.data().displayName ?? ''));
    const uniqueName = disambiguate(displayName, taken);

    const now = Timestamp.now();
    tx.set(
      playerRef(roomId, uid),
      newPlayerDoc({
        userId: uid,
        displayName: uniqueName,
        avatarId,
        avatarColorIndex,
        photoUrl,
        isHost: false,
        now,
      })
    );
    tx.update(roomRef(roomId), {
      currentPlayerCount: players.size + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    systemMessage(tx, roomId, `${uniqueName} joined.`);

    return { roomId, roomCode: room.roomCode, rejoined: false };
  });

  logger.info('room.joined', { roomId, uid, rejoined: result.rejoined });
  return result;
});

/** Appends a numeric suffix until the name is unique in the room. */
function disambiguate(name: string, taken: readonly string[]): string {
  if (!taken.includes(name)) return name;
  for (let n = 2; n < 100; n++) {
    const candidate = `${name} ${n}`;
    if (!taken.includes(candidate)) return candidate;
  }
  return name;
}
