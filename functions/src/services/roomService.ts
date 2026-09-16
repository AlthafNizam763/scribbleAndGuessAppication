import {
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
  getFirestore,
} from 'firebase-admin/firestore';

import { LIMITS, TIMING } from '../config/constants';
import {
  GameState,
  MessageDoc,
  PlayerDoc,
  RoomDoc,
  RoomSettings,
} from '../models/types';
import { logger } from '../utils/logger';
import { newId, newRoomCode } from '../utils/random';
import { failNotFound, failPrecondition } from '../utils/validation';

/**
 * Room lifecycle: creating, finding, joining, leaving and closing.
 *
 * Everything that could be raced by two clients at once - claiming the last
 * seat, taking a room code, handing over the host badge when the owner quits -
 * happens inside a Firestore transaction (section 55).
 */

export function db(): Firestore {
  return getFirestore();
}

/** `rooms/{roomId}` */
export function roomRef(roomId: string): DocumentReference {
  return db().collection('rooms').doc(roomId);
}

/** `rooms/{roomId}/players/{userId}` */
export function playerRef(roomId: string, userId: string): DocumentReference {
  return roomRef(roomId).collection('players').doc(userId);
}

/** `rooms/{roomId}/secret/{roundNumber}` */
export function secretRef(roomId: string, turnIndex: number): DocumentReference {
  return roomRef(roomId).collection('secret').doc(String(turnIndex));
}

/** `rooms/{roomId}/rounds/{turnIndex}` */
export function roundRef(roomId: string, turnIndex: number): DocumentReference {
  return roomRef(roomId).collection('rounds').doc(String(turnIndex));
}

/** Reads a room inside a transaction, or fails. */
export async function readRoom(
  tx: Transaction,
  roomId: string
): Promise<RoomDoc> {
  const snapshot = await tx.get(roomRef(roomId));
  if (!snapshot.exists) {
    failNotFound('roomNotFound', 'That room no longer exists.');
  }
  return snapshot.data() as RoomDoc;
}

/** Reads a player inside a transaction, or undefined when absent. */
export async function readPlayer(
  tx: Transaction,
  roomId: string,
  userId: string
): Promise<PlayerDoc | undefined> {
  const snapshot = await tx.get(playerRef(roomId, userId));
  return snapshot.exists ? (snapshot.data() as PlayerDoc) : undefined;
}

/** Finds a room by its code, or fails. Codes are unique among live rooms. */
export async function findRoomByCode(
  code: string
): Promise<{ roomId: string; room: RoomDoc }> {
  const snapshot = await db()
    .collection('rooms')
    .where('roomCode', '==', code)
    .where('status', 'in', ['waiting', 'starting', 'playing', 'round_result'])
    .limit(1)
    .get();

  if (snapshot.empty) {
    failNotFound('roomNotFound', 'No room found for that code.');
  }
  const doc = snapshot.docs[0];
  return { roomId: doc.id, room: doc.data() as RoomDoc };
}

/**
 * Reserves a room code that no live room is using.
 *
 * Codes are short enough to read aloud, which means collisions are possible;
 * this retries a bounded number of times rather than trusting one draw.
 */
export async function reserveRoomCode(): Promise<string> {
  for (let attempt = 0; attempt < LIMITS.roomCodeAttempts; attempt++) {
    const code = newRoomCode();
    const existing = await db()
      .collection('rooms')
      .where('roomCode', '==', code)
      .where('status', 'in', [
        'waiting',
        'starting',
        'playing',
        'round_result',
        'finished',
      ])
      .limit(1)
      .get();
    if (existing.empty) return code;
  }
  failPrecondition('serverError', 'Could not allocate a room code. Try again.');
}

/** The game state a fresh room starts life in. */
export function initialGameState(totalRounds: number): GameState {
  return {
    currentRound: 0,
    totalRounds,
    turnIndex: -1,
    drawOrder: [],
    currentDrawerId: null,
    roundStatus: 'waiting',
    roundStartedAt: null,
    roundEndsAt: null,
    maskedWord: '',
    wordLength: 0,
    hintsRevealed: 0,
    revealedWord: null,
    correctOrder: [],
  };
}

/** Builds the player document for someone joining a room. */
export function newPlayerDoc(args: {
  userId: string;
  displayName: string;
  avatarId: number;
  avatarColorIndex: number;
  photoUrl: string | null;
  isHost: boolean;
  now: Timestamp;
}): PlayerDoc {
  return {
    userId: args.userId,
    displayName: args.displayName,
    avatarId: args.avatarId,
    avatarColorIndex: args.avatarColorIndex,
    photoUrl: args.photoUrl,
    joinedAt: args.now,
    isReady: false,
    isConnected: true,
    lastSeenAt: args.now,
    score: 0,
    correctGuesses: 0,
    hasGuessedCorrectly: false,
    roundScore: 0,
    isMuted: false,
    isHost: args.isHost,
  };
}

/**
 * Appends a message to a room's feed.
 *
 * System lines (joins, leaves, hints, results) all funnel through here so they
 * are indistinguishable from chat on the client, which keeps the chat panel a
 * single ordered list rather than several interleaved sources.
 */
export function writeMessage(
  tx: Transaction,
  roomId: string,
  message: Omit<MessageDoc, 'messageId' | 'createdAt'> & {
    createdAt?: Timestamp;
  }
): void {
  const id = newId();
  const ref = roomRef(roomId).collection('messages').doc(id);
  tx.set(ref, {
    ...message,
    messageId: id,
    createdAt: message.createdAt ?? Timestamp.now(),
  });
}

/** A system line, the most common kind of generated message. */
export function systemMessage(
  tx: Transaction,
  roomId: string,
  text: string
): void {
  writeMessage(tx, roomId, {
    userId: null,
    displayName: 'System',
    message: text,
    type: 'system',
  });
}

/**
 * Removes a player and repairs the room around them.
 *
 * Leaving is the messiest operation in the product: the leaver might be the
 * owner, might be the current drawer, and might be the last person in the
 * room. All three are handled here so every caller - quitting, being kicked,
 * being banned, timing out - gets identical behaviour.
 */
export async function removePlayer(
  tx: Transaction,
  roomId: string,
  room: RoomDoc,
  userId: string,
  reason: 'left' | 'kicked' | 'banned' | 'timeout'
): Promise<{ roomClosed: boolean; drawerLeft: boolean }> {
  const player = await readPlayer(tx, roomId, userId);
  if (!player) return { roomClosed: false, drawerLeft: false };

  const remaining = await tx.get(
    roomRef(roomId).collection('players').orderBy('joinedAt')
  );
  const others = remaining.docs
    .map((d) => d.data() as PlayerDoc)
    .filter((p) => p.userId !== userId);

  tx.delete(playerRef(roomId, userId));

  const drawerLeft = room.game.currentDrawerId === userId;

  // Last one out closes the room.
  if (others.length === 0) {
    tx.update(roomRef(roomId), {
      status: 'closed',
      currentPlayerCount: 0,
      closedReason: 'Everyone left.',
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { roomClosed: true, drawerLeft };
  }

  const update: Record<string, unknown> = {
    currentPlayerCount: others.length,
    updatedAt: FieldValue.serverTimestamp(),
  };

  // The badge passes to whoever has been here longest, so a room is never
  // left without someone able to start the next game.
  if (room.ownerId === userId) {
    const heir = others[0];
    update.ownerId = heir.userId;
    tx.update(playerRef(roomId, heir.userId), { isHost: true });
    systemMessage(tx, roomId, `${heir.displayName} is now the host.`);
  }

  // A player who leaves mid-game is dropped from the rotation, but the
  // already-taken turns keep their indices so the round counter stays honest.
  if (room.game.drawOrder.includes(userId)) {
    update['game.drawOrder'] = room.game.drawOrder.filter((id) => id !== userId);
  }

  tx.update(roomRef(roomId), update);

  const verb =
    reason === 'kicked'
      ? 'was kicked'
      : reason === 'banned'
        ? 'was banned'
        : reason === 'timeout'
          ? 'timed out'
          : 'left';
  systemMessage(tx, roomId, `${player.displayName} ${verb}.`);

  return { roomClosed: false, drawerLeft };
}

/** Closes a room for good. */
export async function closeRoom(
  roomId: string,
  reason: string
): Promise<void> {
  await roomRef(roomId).update({
    status: 'closed',
    closedReason: reason,
    updatedAt: FieldValue.serverTimestamp(),
  });
  logger.info('room.closed', { roomId, reason });
}

/** Whether a room has gone quiet long enough to be reaped (section 56). */
export function isIdle(room: RoomDoc, now: number): boolean {
  const updated = room.updatedAt?.toMillis?.() ?? 0;
  return room.currentPlayerCount <= 0 && now - updated > TIMING.idleRoomMs;
}

/** Applies new settings to a waiting room. */
export function applySettings(
  tx: Transaction,
  roomId: string,
  settings: RoomSettings
): void {
  tx.update(roomRef(roomId), {
    settings,
    maxPlayers: settings.maxPlayers,
    'game.totalRounds': settings.rounds,
    updatedAt: FieldValue.serverTimestamp(),
  });
}
