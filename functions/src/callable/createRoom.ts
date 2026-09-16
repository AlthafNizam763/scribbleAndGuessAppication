import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { CallableRequest, onCall } from 'firebase-functions/v2/https';

import { LIMITS } from '../config/constants';
import { RoomDoc } from '../models/types';
import {
  db,
  initialGameState,
  newPlayerDoc,
  playerRef,
  reserveRoomCode,
  roomRef,
  systemMessage,
} from '../services/roomService';
import { logger } from '../utils/logger';
import { requireAuth } from '../utils/permissions';
import { newId } from '../utils/random';
import {
  failPrecondition,
  optionalString,
  requireInt,
  sanitizeDisplayName,
  sanitizeSettings,
} from '../utils/validation';

/**
 * Creates a room and seats its owner (section 10).
 *
 * The room id and the room code are separate on purpose: the id is the
 * permanent Firestore key, while the code is the short, human-readable handle
 * players type. Codes are only unique among *live* rooms, so a finished game's
 * code can be recycled later without ever colliding with an active one.
 */
export const createRoom = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const data = request.data ?? {};

  const displayName = sanitizeDisplayName(data.displayName);
  const avatarId = requireInt(data, 'avatarId', 0, 63);
  const avatarColorIndex = requireInt(data, 'avatarColorIndex', 0, 15);
  const photoUrl = optionalString(data, 'photoUrl', 512);
  const settings = sanitizeSettings(data.settings);

  // One person cannot hoard rooms; each is a live listener target for everyone
  // who joins it, so an unbounded number is a cheap way to burn quota.
  const owned = await db()
    .collection('rooms')
    .where('ownerId', '==', uid)
    .where('status', 'in', ['waiting', 'starting', 'playing', 'round_result'])
    .get();
  if (owned.size >= LIMITS.maxRoomsPerUser) {
    failPrecondition(
      'invalidAction',
      `You already have ${owned.size} open rooms. Close one first.`
    );
  }

  const roomId = newId();
  const roomCode = await reserveRoomCode();
  const now = Timestamp.now();

  const room: RoomDoc = {
    roomId,
    roomCode,
    ownerId: uid,
    status: 'waiting',
    createdAt: now,
    updatedAt: now,
    maxPlayers: settings.maxPlayers,
    currentPlayerCount: 1,
    settings,
    game: initialGameState(settings.rounds),
    bannedUserIds: [],
    closedReason: null,
  };

  await db().runTransaction(async (tx) => {
    tx.set(roomRef(roomId), room);
    tx.set(
      playerRef(roomId, uid),
      newPlayerDoc({
        userId: uid,
        displayName,
        avatarId,
        avatarColorIndex,
        photoUrl,
        isHost: true,
        now,
      })
    );
    systemMessage(tx, roomId, `${displayName} created the room.`);
  });

  logger.info('room.created', { roomId, roomCode, ownerId: uid });
  return { roomId, roomCode };
});

/** Updates a waiting room's rules. Owner only. */
export const updateRoomSettings = onCall(async (request: CallableRequest) => {
  const uid = requireAuth(request);
  const data = request.data ?? {};
  const roomId = String(data.roomId ?? '');
  if (!roomId) failPrecondition('validation', 'A room id is required.');

  const settings = sanitizeSettings(data.settings);

  await db().runTransaction(async (tx) => {
    const snapshot = await tx.get(roomRef(roomId));
    if (!snapshot.exists) {
      failPrecondition('roomNotFound', 'That room no longer exists.');
    }
    const room = snapshot.data() as RoomDoc;
    if (room.ownerId !== uid) {
      failPrecondition('notHost', 'Only the room owner can change settings.');
    }
    if (room.status !== 'waiting') {
      failPrecondition(
        'gameInProgress',
        'Settings can only change before the game starts.'
      );
    }
    // Shrinking the room below its current occupancy would strand players, so
    // the floor is however many are already seated.
    if (settings.maxPlayers < room.currentPlayerCount) {
      failPrecondition(
        'validation',
        `There are already ${room.currentPlayerCount} players in the room.`
      );
    }

    tx.update(roomRef(roomId), {
      settings,
      maxPlayers: settings.maxPlayers,
      'game.totalRounds': settings.rounds,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});
