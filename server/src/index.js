/**
 * Scribble & Guess — realtime drawing relay.
 *
 * This process does exactly one job: move pencil strokes between the people in
 * a room, fast. It is *not* the game server. Rooms, rounds, the drawer
 * rotation, the word, the timer and every point are owned by Cloud Functions
 * and Firestore; this relay only ever reads from Firestore, and only to answer
 * one question — "is this uid allowed to draw right now?" (§51).
 *
 * It exists because drawing is the one channel Firestore is the wrong tool for.
 * A stroke is tens of points a second per drawer; a document write per point
 * would be unusably slow and absurdly expensive (§22). So the pencil gets its
 * own websocket, and everything that decides who wins stays on Firebase.
 */

import http from 'node:http';

import cors from 'cors';
import express from 'express';
import { Server } from 'socket.io';

import { RoomWatcher, initFirebase, verifyIdToken } from './auth.js';
import { BoardStore } from './boards.js';
import { config } from './config.js';
import { newId } from './ids.js';
import { logger } from './logger.js';
import * as ev from './protocol.js';
import { createLimiter } from './rateLimit.js';

initFirebase();

const app = express();
app.use(cors({ origin: config.corsOrigin }));

const boards = new BoardStore();
const watcher = new RoomWatcher();

/** Liveness, for a load balancer or an uptime check. */
app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    uptimeSeconds: Math.round(process.uptime()),
    rooms: watcher.rooms.size,
    boards: boards.boards.size,
  });
});

const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: config.corsOrigin },
  maxHttpBufferSize: config.limits.maxHttpBufferSize,
  transports: ['websocket'],
});

io.on('connection', (socket) => {
  /** Set once the handshake succeeds. Nothing else is accepted before then. */
  let uid = null;
  let roomId = null;
  const limiter = createLimiter();

  /**
   * The handshake: prove who you are, and which room you are in.
   *
   * Both are verified server-side. The token is checked against Firebase, and
   * membership against the room's own player collection — so a valid token for
   * a room you are not in gets you nothing.
   */
  socket.on(ev.CLIENT_HELLO, async (payload, ack) => {
    const respond = typeof ack === 'function' ? ack : () => {};
    try {
      const verified = await verifyIdToken(payload?.idToken);
      if (!verified) {
        respond({ ok: false, error: { code: 'invalidAction', message: 'Sign-in required.' } });
        socket.disconnect(true);
        return;
      }

      const requestedRoom = String(payload?.roomId ?? '').trim();
      if (requestedRoom.length === 0) {
        // A client may connect before it has a room; it re-handshakes later.
        uid = verified;
        respond({ ok: true, serverTimeMs: Date.now() });
        return;
      }

      if (!(await watcher.isMember(requestedRoom, verified))) {
        respond({ ok: false, error: { code: 'invalidAction', message: 'You are not in that room.' } });
        return;
      }

      uid = verified;
      roomId = requestedRoom;
      socket.join(roomId);
      watcher.watch(roomId, socket.id);

      // A late joiner, or someone who just reconnected, needs the board as it
      // stands — not just the strokes drawn from this moment on (§36).
      socket.emit(ev.SERVER_DRAW_SNAPSHOT, boards.get(roomId).snapshot());

      respond({ ok: true, serverTimeMs: Date.now() });
      logger.debug('socket joined', { roomId, uid });
    } catch (error) {
      logger.error('handshake failed', error);
      respond({ ok: false, error: { code: 'serverError', message: 'Handshake failed.' } });
    }
  });

  /** Answers a clock probe, so the client can measure its offset (§29). */
  socket.on(ev.CLIENT_TIME_PING, (payload, ack) => {
    if (typeof ack !== 'function') return;
    ack({ ok: true, sentAtMs: payload?.sentAtMs ?? 0, serverTimeMs: Date.now() });
  });

  /**
   * Guards a drawing event.
   *
   * Four things have to hold: the socket handshook, it is in a room, it is
   * within its rate budget, and Firestore says this uid is the current drawer
   * in the drawing phase. A non-drawer's events are dropped silently — they
   * are either a bug or an attack, and neither deserves a reply.
   */
  const guard = () => {
    if (uid === null || roomId === null) return null;
    if (!limiter.allow('draw')) return null;
    if (!watcher.canDraw(roomId, uid)) return null;
    return boards.get(roomId);
  };

  socket.on(ev.CLIENT_DRAW_BEGIN, (payload) => {
    const board = guard();
    if (!board) return;

    const points = normalizePoints(payload?.p);
    const stroke = {
      id: String(payload?.id ?? newId()),
      a: uid,
      p: points,
      c: Number.isFinite(payload?.c) ? payload.c : 0xff1a1a1a,
      w: Number.isFinite(payload?.w) ? payload.w : 4,
      t: payload?.t === 'eraser' ? 'eraser' : 'pen',
      ts: Date.now(),
    };
    if (!board.begin(stroke)) return;
    socket.to(roomId).emit(ev.SERVER_DRAW_BEGIN, stroke);
  });

  socket.on(ev.CLIENT_DRAW_APPEND, (payload) => {
    const board = guard();
    if (!board) return;

    const strokeId = String(payload?.id ?? '');
    const points = normalizePoints(payload?.p);
    if (strokeId.length === 0 || points.length === 0) return;
    if (!board.append(strokeId, points)) return;

    socket.to(roomId).emit(ev.SERVER_DRAW_APPEND, { id: strokeId, p: points });
  });

  socket.on(ev.CLIENT_DRAW_END, (payload) => {
    const board = guard();
    if (!board) return;
    const strokeId = String(payload?.id ?? '');
    board.end(strokeId);
    socket.to(roomId).emit(ev.SERVER_DRAW_END, { id: strokeId });
  });

  socket.on(ev.CLIENT_DRAW_UNDO, () => {
    const board = guard();
    if (!board) return;
    const removed = board.undo(uid);
    if (removed === null) return;
    // Only the id travels: every client already holds the stroke (§24).
    io.to(roomId).emit(ev.SERVER_DRAW_UNDO, { id: removed });
  });

  socket.on(ev.CLIENT_DRAW_REDO, () => {
    const board = guard();
    if (!board) return;
    const restored = board.redoLast(uid);
    if (restored === null) return;
    io.to(roomId).emit(ev.SERVER_DRAW_REDO, restored);
  });

  socket.on(ev.CLIENT_DRAW_CLEAR, () => {
    const board = guard();
    if (!board) return;
    board.clear();
    io.to(roomId).emit(ev.SERVER_DRAW_CLEAR, {});
  });

  socket.on('disconnect', (reason) => {
    if (roomId !== null) watcher.unwatch(roomId, socket.id);
    logger.debug('socket left', { roomId, uid, reason });
  });
});

/**
 * Coerces a wire point list into `[[x, y], ...]` with normalised coordinates.
 *
 * Coordinates are 0..1 so a drawing made on a phone renders correctly on a
 * tablet (§21); anything outside that range, or not a number, is dropped
 * rather than clamped, because it can only be a malformed or hostile payload.
 */
function normalizePoints(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const entry of raw) {
    if (!Array.isArray(entry) || entry.length < 2) continue;
    const x = Number(entry[0]);
    const y = Number(entry[1]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
    if (x < 0 || x > 1 || y < 0 || y > 1) continue;
    out.push([x, y]);
    if (out.length >= config.limits.maxPointsPerAppend) break;
  }
  return out;
}

server.listen(config.port, config.host, () => {
  logger.info('drawing relay listening', {
    host: config.host,
    port: config.port,
  });
});

/** Shuts down cleanly so in-flight frames are not cut mid-write. */
function shutdown(signal) {
  logger.info('shutting down', { signal });
  io.close(() => {
    watcher.dispose();
    boards.dispose();
    server.close(() => process.exit(0));
  });
  // Never hang forever waiting for a stuck socket.
  setTimeout(() => process.exit(0), 5000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
