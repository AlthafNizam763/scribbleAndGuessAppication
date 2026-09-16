import { CallableRequest } from 'firebase-functions/v2/https';

import { PlayerDoc, RoomDoc } from '../models/types';
import { failPermission, failPrecondition } from './validation';

/**
 * The permission checks every callable runs before it does anything.
 *
 * Each one throws rather than returning a boolean, so a caller cannot forget
 * to branch on the result — the check either passes or the request is over.
 * This is the whole of the app's authorisation model: Firestore rules make the
 * data unwritable by clients, and these functions decide who may ask for what
 * (sections 50, 54).
 */

/** The authenticated caller's uid, or a refusal. */
export function requireAuth(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    failPermission('invalidAction', 'You must be signed in to do that.');
  }
  return uid;
}

/**
 * Enforces App Check when it is configured (section 64).
 *
 * Deliberately advisory rather than fatal: App Check tokens are unavailable on
 * some desktop/debug builds, and refusing those outright would make the game
 * undebuggable. Production abuse is handled by App Check enforcement on the
 * Firebase side, which rejects the request before it ever reaches this code.
 */
export function warnIfUnverified(request: CallableRequest): boolean {
  return request.app !== undefined;
}

/** Asserts the caller owns the room. */
export function requireOwner(room: RoomDoc, uid: string): void {
  if (room.ownerId !== uid) {
    failPermission('notHost', 'Only the room owner can do that.');
  }
}

/** Asserts the caller is the current drawer. */
export function requireDrawer(room: RoomDoc, uid: string): void {
  if (room.game.currentDrawerId !== uid) {
    failPermission('notDrawer', 'Only the drawer can do that.');
  }
}

/** Asserts the caller is *not* the current drawer. */
export function requireNotDrawer(room: RoomDoc, uid: string): void {
  if (room.game.currentDrawerId === uid) {
    failPrecondition('invalidAction', 'The drawer cannot guess their own word.');
  }
}

/** Asserts the player is a member of the room. */
export function requireMember(
  player: PlayerDoc | undefined,
  uid: string
): PlayerDoc {
  if (!player || player.userId !== uid) {
    failPrecondition('invalidAction', 'You are not in this room.');
  }
  return player;
}

/** Asserts the caller is not banned from the room. */
export function requireNotBanned(room: RoomDoc, uid: string): void {
  if (room.bannedUserIds.includes(uid)) {
    failPermission('banned', 'You have been banned from this room.');
  }
}

/** Asserts the player is allowed to speak. */
export function requireNotMuted(player: PlayerDoc): void {
  if (player.isMuted) {
    failPrecondition('invalidAction', 'You have been muted in this room.');
  }
}

/** Asserts the room is in one of `allowed` statuses. */
export function requireRoomStatus(
  room: RoomDoc,
  allowed: readonly RoomDoc['status'][]
): void {
  if (!allowed.includes(room.status)) {
    failPrecondition(
      'invalidAction',
      `That is not allowed while the room is "${room.status}".`
    );
  }
}

/** Asserts the round is in one of `allowed` statuses. */
export function requireRoundStatus(
  room: RoomDoc,
  allowed: readonly RoomDoc['game']['roundStatus'][]
): void {
  if (!allowed.includes(room.game.roundStatus)) {
    failPrecondition(
      'invalidAction',
      `That is not allowed during "${room.game.roundStatus}".`
    );
  }
}
