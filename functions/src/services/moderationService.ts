import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { LIMITS } from '../config/constants';
import { PlayerDoc, RoomDoc, VoteDoc } from '../models/types';
import { logger } from '../utils/logger';
import { newId } from '../utils/random';
import { failPrecondition } from '../utils/validation';
import {
  db,
  playerRef,
  readPlayer,
  readRoom,
  removePlayer,
  roomRef,
  systemMessage,
} from './roomService';

/**
 * Moderation: kick, ban, mute, report and vote-kick (sections 33-34).
 *
 * Every one of these is server-side, and every one re-checks the caller's
 * authority inside the transaction rather than trusting a check made before
 * it. That matters because host status can change between a client rendering
 * a "Kick" button and the request arriving.
 */

/** How long a vote-kick ballot stays open. */
const VOTE_WINDOW_MS = 60_000;

/** Removes a player from a room. Owner only. */
export async function kickPlayer(
  roomId: string,
  callerId: string,
  targetId: string
): Promise<void> {
  await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    assertOwner(room, callerId);
    assertNotSelf(callerId, targetId, 'kick');
    await removePlayer(tx, roomId, room, targetId, 'kicked');
  });
  logger.info('moderation.kick', { roomId, callerId, targetId });
}

/**
 * Removes a player and blocks them from rejoining (section 33).
 *
 * The uid goes onto the room's ban list, which `joinRoom` checks, so a banned
 * player cannot return with a fresh room code lookup.
 */
export async function banPlayer(
  roomId: string,
  callerId: string,
  targetId: string
): Promise<void> {
  await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    assertOwner(room, callerId);
    assertNotSelf(callerId, targetId, 'ban');

    tx.update(roomRef(roomId), {
      bannedUserIds: FieldValue.arrayUnion(targetId),
    });
    await removePlayer(tx, roomId, room, targetId, 'banned');
  });
  logger.info('moderation.ban', { roomId, callerId, targetId });
}

/** Silences or unsilences a player in chat. Owner only. */
export async function mutePlayer(
  roomId: string,
  callerId: string,
  targetId: string,
  muted: boolean
): Promise<void> {
  await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    assertOwner(room, callerId);
    assertNotSelf(callerId, targetId, 'mute');

    const target = await readPlayer(tx, roomId, targetId);
    if (!target) {
      failPrecondition('invalidAction', 'That player is not in the room.');
    }

    tx.update(playerRef(roomId, targetId), { isMuted: muted });
    systemMessage(
      tx,
      roomId,
      `${target.displayName} was ${muted ? 'muted' : 'unmuted'}.`
    );
  });
  logger.info('moderation.mute', { roomId, callerId, targetId, muted });
}

/**
 * Files a report against a player.
 *
 * Reports are written to a collection no client can read, so a report is never
 * visible to the person reported, and the reporter's identity is retained for
 * abuse triage but never surfaced in the room.
 */
export async function reportPlayer(args: {
  roomId: string;
  reporterId: string;
  targetId: string;
  reason: string;
}): Promise<void> {
  const { roomId, reporterId, targetId, reason } = args;
  if (reporterId === targetId) {
    failPrecondition('invalidAction', 'You cannot report yourself.');
  }

  const id = newId();
  await db()
    .collection('reports')
    .doc(id)
    .set({
      reportId: id,
      roomId,
      reporterId,
      targetId,
      reason: reason.slice(0, LIMITS.maxReportLength),
      createdAt: Timestamp.now(),
      status: 'open',
    });
  logger.info('moderation.report', { roomId, reporterId, targetId });
}

/**
 * Casts a vote to remove a player (section 34).
 *
 * One ballot per target, one vote per player, enforced inside the transaction
 * so a client cannot stuff it by firing several requests at once. The
 * threshold is a strict majority of everyone eligible to vote - that is,
 * everyone but the target - so a room of three cannot be hijacked by one
 * determined player.
 */
export async function voteKick(
  roomId: string,
  voterId: string,
  targetId: string
): Promise<{ votes: number; needed: number; removed: boolean }> {
  const outcome = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (!room.settings.allowVoteKick) {
      failPrecondition('invalidAction', 'Vote-kick is disabled in this room.');
    }
    assertNotSelf(voterId, targetId, 'vote to kick');

    const voter = await readPlayer(tx, roomId, voterId);
    if (!voter) {
      failPrecondition('invalidAction', 'You are not in this room.');
    }
    const target = await readPlayer(tx, roomId, targetId);
    if (!target) {
      failPrecondition('invalidAction', 'That player is not in the room.');
    }
    // The owner cannot be voted out; they would just be able to reopen the
    // room, and it turns vote-kick into a way to hijack someone's game.
    if (room.ownerId === targetId) {
      failPrecondition('invalidAction', 'The host cannot be vote-kicked.');
    }

    const voteReference = roomRef(roomId).collection('votes').doc(targetId);
    const snapshot = await tx.get(voteReference);
    const now = Date.now();

    const existing = snapshot.exists ? (snapshot.data() as VoteDoc) : null;
    const isLive =
      existing !== null && (existing.expiresAt?.toMillis() ?? 0) > now;

    const voterIds = isLive ? [...existing.voterIds] : [];
    if (voterIds.includes(voterId)) {
      failPrecondition('invalidAction', 'You already voted.');
    }
    voterIds.push(voterId);

    const players = await tx.get(roomRef(roomId).collection('players'));
    const eligible = Math.max(1, players.size - 1);
    const needed = Math.floor(eligible / 2) + 1;

    if (voterIds.length >= needed) {
      tx.delete(voteReference);
      await removePlayer(tx, roomId, room, targetId, 'kicked');
      return { votes: voterIds.length, needed, removed: true };
    }

    const ballot: VoteDoc = {
      targetUserId: targetId,
      targetName: target.displayName,
      voterIds,
      createdAt: isLive ? existing.createdAt : Timestamp.fromMillis(now),
      expiresAt: Timestamp.fromMillis(
        isLive ? existing.expiresAt.toMillis() : now + VOTE_WINDOW_MS
      ),
    };
    tx.set(voteReference, ballot);

    systemMessage(
      tx,
      roomId,
      `${voterIds.length}/${needed} voted to remove ${target.displayName}.`
    );
    return { votes: voterIds.length, needed, removed: false };
  });

  logger.info('moderation.voteKick', { roomId, voterId, targetId, ...outcome });
  return outcome;
}

/** Hands the host badge to another player. Owner only. */
export async function transferHost(
  roomId: string,
  callerId: string,
  targetId: string
): Promise<void> {
  await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    assertOwner(room, callerId);
    assertNotSelf(callerId, targetId, 'transfer the host badge to');

    const target = await readPlayer(tx, roomId, targetId);
    if (!target) {
      failPrecondition('invalidAction', 'That player is not in the room.');
    }

    tx.update(roomRef(roomId), {
      ownerId: targetId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(playerRef(roomId, callerId), { isHost: false });
    tx.update(playerRef(roomId, targetId), { isHost: true });
    systemMessage(tx, roomId, `${target.displayName} is now the host.`);
  });
  logger.info('moderation.transferHost', { roomId, callerId, targetId });
}

/** Asserts `callerId` owns the room. */
function assertOwner(room: RoomDoc, callerId: string): void {
  if (room.ownerId !== callerId) {
    failPrecondition('notHost', 'Only the room owner can do that.');
  }
}

/** Rejects self-targeted moderation, which is never meaningful. */
function assertNotSelf(
  callerId: string,
  targetId: string,
  verb: string
): void {
  if (callerId === targetId) {
    failPrecondition('invalidAction', `You cannot ${verb} yourself.`);
  }
}

/** Whether `player` may speak right now. */
export function canSpeak(player: PlayerDoc): boolean {
  return !player.isMuted;
}
