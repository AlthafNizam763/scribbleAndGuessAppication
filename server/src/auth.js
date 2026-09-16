/**
 * Firebase authentication and drawer authorisation for the drawing relay.
 *
 * This is the file that makes §51 true. A socket is not trusted because it
 * says who it is: it presents a Firebase ID token, the Admin SDK verifies the
 * signature, and the uid that comes out is the only identity the relay will
 * ever use for that connection. Whether that uid may *draw* is a separate
 * question, answered by Firestore — the same room document the Cloud Functions
 * write — rather than by anything the client sent.
 */

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import { logger } from './logger.js';

let ready = false;

/**
 * Initialises the Admin SDK once.
 *
 * Credentials come from `GOOGLE_APPLICATION_CREDENTIALS` (a service-account
 * file) or, on Google infrastructure, the metadata server. Running against the
 * emulator needs no credentials at all — `FIRESTORE_EMULATOR_HOST` and
 * `FIREBASE_AUTH_EMULATOR_HOST` are enough.
 */
export function initFirebase() {
  if (ready || getApps().length > 0) {
    ready = true;
    return;
  }

  const projectId =
    process.env.FIREBASE_PROJECT_ID || process.env.GCLOUD_PROJECT || undefined;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;

  try {
    if (raw) {
      // A JSON service account passed inline, which is how most container
      // platforms inject one.
      initializeApp({ credential: cert(JSON.parse(raw)), projectId });
    } else {
      initializeApp({ projectId });
    }
    ready = true;
    logger.info('firebase admin ready', { projectId: projectId ?? '(default)' });
  } catch (error) {
    logger.error('firebase admin init failed', error);
    throw error;
  }
}

/**
 * Verifies a Firebase ID token and returns its uid.
 *
 * Returns `null` for anything that does not verify — expired, forged, wrong
 * project, or absent. The caller refuses the connection on `null`; it never
 * falls back to a client-supplied id.
 *
 * @param {unknown} idToken
 * @returns {Promise<string|null>}
 */
export async function verifyIdToken(idToken) {
  if (typeof idToken !== 'string' || idToken.length === 0) return null;
  try {
    const decoded = await getAuth().verifyIdToken(idToken);
    return decoded.uid ?? null;
  } catch (error) {
    logger.warn('id token rejected', { reason: error?.code ?? String(error) });
    return null;
  }
}

/**
 * Watches a room and reports who may currently draw.
 *
 * One Firestore listener per active room, shared by every socket in it, so a
 * twelve-player room costs one subscription rather than twelve. The listener
 * is torn down when the last socket leaves.
 *
 * Reading the drawer from Firestore rather than accepting it from the client
 * is the entire point: the Cloud Functions are the only writer of
 * `game.currentDrawerId`, so the relay and the game engine can never disagree
 * about whose strokes are legitimate.
 */
export class RoomWatcher {
  constructor() {
    /** @type {Map<string, {unsubscribe: () => void, drawerId: string|null, phase: string|null, members: Set<string>}>} */
    this.rooms = new Map();
  }

  /** Starts (or joins) the watch for `roomId` on behalf of `socketId`. */
  watch(roomId, socketId) {
    let entry = this.rooms.get(roomId);
    if (entry) {
      entry.members.add(socketId);
      return entry;
    }

    entry = {
      drawerId: null,
      phase: null,
      members: new Set([socketId]),
      unsubscribe: () => {},
    };
    this.rooms.set(roomId, entry);

    try {
      entry.unsubscribe = getFirestore()
        .collection('rooms')
        .doc(roomId)
        .onSnapshot(
          (snapshot) => {
            const game = snapshot.exists ? (snapshot.data()?.game ?? {}) : {};
            entry.drawerId = game.currentDrawerId ?? null;
            entry.phase = game.roundStatus ?? null;
          },
          (error) => {
            logger.error('room watch failed', error, { roomId });
            // Fail closed: an unreadable room means nobody is authorised.
            entry.drawerId = null;
          },
        );
    } catch (error) {
      logger.error('could not watch room', error, { roomId });
    }
    return entry;
  }

  /** Drops `socketId`, tearing the listener down when the room empties. */
  unwatch(roomId, socketId) {
    const entry = this.rooms.get(roomId);
    if (!entry) return;
    entry.members.delete(socketId);
    if (entry.members.size === 0) {
      entry.unsubscribe();
      this.rooms.delete(roomId);
    }
  }

  /**
   * Whether `uid` may draw in `roomId` right now.
   *
   * Both conditions matter. Being the drawer is not enough if the round is not
   * in its drawing phase, or a drawer could keep scribbling over the round
   * result everyone else is reading.
   */
  canDraw(roomId, uid) {
    const entry = this.rooms.get(roomId);
    if (!entry) return false;
    if (entry.drawerId === null || entry.drawerId !== uid) return false;
    return entry.phase === 'drawing';
  }

  /** Confirms a player is actually a member of the room. */
  async isMember(roomId, uid) {
    try {
      const doc = await getFirestore()
        .collection('rooms')
        .doc(roomId)
        .collection('players')
        .doc(uid)
        .get();
      return doc.exists;
    } catch (error) {
      logger.error('membership check failed', error, { roomId, uid });
      return false;
    }
  }

  /** Releases every listener. */
  dispose() {
    for (const entry of this.rooms.values()) entry.unsubscribe();
    this.rooms.clear();
  }
}
