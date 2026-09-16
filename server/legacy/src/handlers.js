/**
 * Socket event wiring: payload validation, permission checks and rate limits.
 *
 * Three rules hold for every handler in this file:
 *   1. Nothing from the client is trusted. Every field is type-checked,
 *      clamped and length-capped before it reaches the game engine.
 *   2. Every permission is checked here: host-only actions compare against
 *      `room.hostId`, drawing events require being the current drawer during
 *      the drawing phase, and word selection requires being the drawer during
 *      word selection.
 *   3. No exception escapes. Every body runs inside a wrapper that answers a
 *      failed ack with `{ok: false, error}` and keeps the process alive.
 */

import { clampRange, config, DEFAULT_SETTINGS, RANGES } from './config.js';
import { EngineError } from './GameEngine.js';
import { newId, normalizeRoomCode } from './ids.js';
import { logger } from './logger.js';
import {
  CHAT_TYPE,
  CLIENT_CHAT_SEND,
  CLIENT_DRAW_APPEND,
  CLIENT_DRAW_BEGIN,
  CLIENT_DRAW_CLEAR,
  CLIENT_DRAW_END,
  CLIENT_DRAW_REDO,
  CLIENT_DRAW_UNDO,
  CLIENT_GAME_PLAY_AGAIN,
  CLIENT_GAME_SELECT_WORD,
  CLIENT_GAME_START,
  CLIENT_HELLO,
  CLIENT_ROOM_BAN,
  CLIENT_ROOM_CREATE,
  CLIENT_ROOM_JOIN,
  CLIENT_ROOM_KICK,
  CLIENT_ROOM_LEAVE,
  CLIENT_ROOM_MUTE,
  CLIENT_ROOM_READY,
  CLIENT_ROOM_REPORT,
  CLIENT_ROOM_SETTINGS,
  CLIENT_ROOM_TRANSFER_HOST,
  CLIENT_ROOM_VOTE_KICK,
  CLIENT_TIME_PING,
  DRAW_TOOL,
  ERROR_CODE,
  LANGUAGES,
  PHASE,
  ROOM_STATUS,
  SERVER_DRAW_APPEND,
  SERVER_DRAW_BEGIN,
  SERVER_DRAW_CLEAR,
  SERVER_DRAW_END,
  SERVER_DRAW_REDO,
  SERVER_DRAW_SNAPSHOT,
  SERVER_DRAW_UNDO,
  SERVER_ERROR,
  SERVER_TIME_SYNC,
  SERVER_YOU_KICKED,
  WORD_CATEGORIES,
  WORD_MODE,
} from './protocol.js';
import { createLimiter } from './rateLimit.js';
import { RoomError } from './RoomManager.js';
import { errorAck, failureJson, okAck, roomJson, strokeJson } from './serialize.js';

const log = logger.child('socket');

// ---------------------------------------------------------------------------
// Validation helpers - every one of them is total: they never throw.
// ---------------------------------------------------------------------------

/** Control characters, which must never reach another client. */
const CONTROL_CHARS = /[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028\u2029\uFEFF]/g;
/** Letters, digits, spaces, dots, hyphens and underscores. `Validators`. */
const NAME_PATTERN = /^[\p{L}\p{N} ._-]+$/u;

/** Trims, strips control characters and caps `value` at `maxCodePoints`. */
export function sanitizeText(value, maxCodePoints) {
  if (typeof value !== 'string') return '';
  const cleaned = value.replace(CONTROL_CHARS, ' ').replace(/\s+/g, ' ').trim();
  const points = [...cleaned];
  return points.length <= maxCodePoints ? cleaned : points.slice(0, maxCodePoints).join('');
}

/** A finite integer clamped to `[min, max]`, or `fallback`. */
export function sanitizeInt(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(number)));
}

/** A boolean, or `fallback` for anything that is not one. */
export function sanitizeBool(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (value === 1 || value === 'true') return true;
  if (value === 0 || value === 'false') return false;
  return fallback;
}

/** A display name that satisfies the client's own validator. */
export function sanitizeName(value) {
  const text = sanitizeText(value, config.limits.maxNameLength);
  const points = [...text];
  if (points.length < config.limits.minNameLength) return '';
  if (!NAME_PATTERN.test(text)) return '';
  return text;
}

/**
 * A player profile. Returns `null` when the name cannot be salvaged, which the
 * callers turn into a validation failure.
 */
export function sanitizeProfile(raw) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const name = sanitizeName(source.name);
  if (!name) return null;
  const id = typeof source.id === 'string' && source.id.trim().length > 0 && source.id.trim().length <= 64
    ? source.id.trim()
    : null;
  return {
    id,
    name,
    avatarId: sanitizeInt(source.avatarId, 0, 11, 0),
    avatarColorIndex: sanitizeInt(source.avatarColorIndex, 0, 7, 0),
  };
}

/**
 * Room settings, clamped to the ranges `RoomSettings.validate()` enforces on
 * the client. Unknown fields are dropped; nothing is ever taken verbatim.
 *
 * @returns {{settings: object, problems: string[]}}
 */
export function sanitizeSettings(raw, base = DEFAULT_SETTINGS) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const pick = (key) => (source[key] === undefined ? base[key] : source[key]);

  const categories = [];
  const rawCategories = Array.isArray(source.categories) ? source.categories : base.categories;
  for (const entry of rawCategories ?? []) {
    const name = typeof entry === 'string' ? entry.trim() : '';
    if (WORD_CATEGORIES.includes(name) && !categories.includes(name)) categories.push(name);
  }
  if (categories.length === 0) categories.push('random');

  const customWords = [];
  const rawWords = Array.isArray(source.customWords) ? source.customWords : base.customWords;
  for (const entry of rawWords ?? []) {
    if (customWords.length >= config.limits.maxCustomWords) break;
    const word = sanitizeText(entry, config.limits.maxCustomWordLength);
    if ([...word].length < config.limits.minCustomWordLength) continue;
    if (customWords.some((existing) => existing.toLowerCase() === word.toLowerCase())) continue;
    customWords.push(word);
  }

  const language = typeof pick('language') === 'string' && LANGUAGES.includes(pick('language'))
    ? pick('language')
    : 'en';
  const wordMode = Object.values(WORD_MODE).includes(pick('wordMode')) ? pick('wordMode') : WORD_MODE.choose;

  const settings = {
    maxPlayers: clampRange(Number(pick('maxPlayers')), RANGES.maxPlayers, DEFAULT_SETTINGS.maxPlayers),
    rounds: clampRange(Number(pick('rounds')), RANGES.rounds, DEFAULT_SETTINGS.rounds),
    drawTimeSeconds: clampRange(Number(pick('drawTimeSeconds')), RANGES.drawTimeSeconds, DEFAULT_SETTINGS.drawTimeSeconds),
    wordChoiceCount: clampRange(Number(pick('wordChoiceCount')), RANGES.wordChoiceCount, DEFAULT_SETTINGS.wordChoiceCount),
    hintCount: clampRange(Number(pick('hintCount')), RANGES.hintCount, DEFAULT_SETTINGS.hintCount),
    wordSelectSeconds: clampRange(
      Number(pick('wordSelectSeconds')),
      RANGES.wordSelectSeconds,
      DEFAULT_SETTINGS.wordSelectSeconds,
    ),
    wordMode,
    language,
    categories,
    customWords,
    allowVoteKick: sanitizeBool(pick('allowVoteKick'), DEFAULT_SETTINGS.allowVoteKick),
    isPrivate: sanitizeBool(pick('isPrivate'), DEFAULT_SETTINGS.isPrivate),
  };

  // Mirrors the human-readable problems of `RoomSettings.validate()`. After
  // clamping only the custom-word rule can still fail.
  const problems = [];
  if (settings.wordMode === WORD_MODE.custom && settings.customWords.length < config.limits.minCustomWords) {
    problems.push(`Custom mode needs at least ${config.limits.minCustomWords} custom words.`);
  }
  return { settings, problems };
}

/** Normalized points, clamped to the 0..1 canvas box and capped in length. */
export function sanitizePoints(raw, cap) {
  const out = [];
  if (!Array.isArray(raw)) return out;
  for (const entry of raw) {
    if (out.length >= cap) break;
    let x;
    let y;
    if (Array.isArray(entry)) {
      x = Number(entry[0]);
      y = Number(entry[1]);
    } else if (entry && typeof entry === 'object') {
      x = Number(entry.x);
      y = Number(entry.y);
    } else {
      continue;
    }
    if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
    out.push({ x: Math.min(1, Math.max(0, x)), y: Math.min(1, Math.max(0, y)) });
  }
  return out;
}

/** A stroke whose author and timestamp are decided by the server, not the client. */
export function sanitizeStroke(raw, authorId) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const id = typeof source.id === 'string' && source.id.trim().length > 0 && source.id.trim().length <= 64
    ? source.id.trim()
    : newId();
  return {
    id,
    authorId,
    points: sanitizePoints(source.p ?? source.points, config.limits.maxPointsPerAppend),
    colorValue: sanitizeInt(source.c ?? source.colorValue, -2147483648, 4294967295, 0xff1a1a1a),
    width: Math.min(64, Math.max(0.5, Number(source.w ?? source.width) || 4)),
    tool: DRAW_TOOL[source.t ?? source.tool] ?? DRAW_TOOL.pen,
    timestampMs: Date.now(),
  };
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

/** Replies through `ack` if the client supplied one. Never throws. */
function respond(ack, payload) {
  if (typeof ack !== 'function') return;
  try {
    ack(payload);
  } catch (error) {
    log.warn('ack callback threw', error);
  }
}

/** Turns any thrown value into a `Failure`-shaped ack payload. */
function toErrorAck(error) {
  if (error instanceof EngineError || error instanceof RoomError) {
    return errorAck(error.code, error.message);
  }
  log.error('handler failed', error);
  return errorAck(ERROR_CODE.serverError, 'Something went wrong on the server.');
}

/**
 * Registers one guarded handler.
 *
 * @param {import('socket.io').Socket} socket
 * @param {string} event
 * @param {string} bucket rate-limit class: chat | draw | room | time
 * @param {(payload: object, ctx: object) => object|undefined} body
 */
function on(socket, event, bucket, body) {
  socket.on(event, (...args) => {
    const ack = typeof args[args.length - 1] === 'function' ? args.pop() : null;
    const payload = args[0] && typeof args[0] === 'object' ? args[0] : {};
    try {
      if (!socket.data.limiter.allow(bucket)) {
        // Over-limit events are dropped, never queued.
        respond(ack, errorAck(ERROR_CODE.invalidAction, 'Slow down.'));
        return;
      }
      const result = body(payload, ack);
      if (result !== undefined) respond(ack, result);
    } catch (error) {
      respond(ack, toErrorAck(error));
    }
  });
}

/**
 * Attaches every protocol handler to one socket.
 *
 * @param {import('socket.io').Server} io
 * @param {import('./RoomManager.js').RoomManager} manager
 * @param {import('socket.io').Socket} socket
 */
export function attachHandlers(io, manager, socket) {
  socket.data.limiter = createLimiter();
  socket.data.playerId = null;
  socket.data.roomCode = null;

  /** The room this socket is seated in, or null. */
  const currentRoom = () => (socket.data.roomCode ? manager.getRoom(socket.data.roomCode) : null);

  /** The room + player pair, or a thrown `RoomError` when not seated. */
  const requireSeat = () => {
    const room = currentRoom();
    const player = room?.playerById(socket.data.playerId ?? '');
    if (!room || !player) throw new RoomError(ERROR_CODE.invalidAction, 'You are not in a room.');
    return { room, player };
  };

  /** Asserts the caller owns the room. */
  const requireHost = () => {
    const seat = requireSeat();
    if (!seat.room.isHost(seat.player.id)) {
      throw new RoomError(ERROR_CODE.notHost, 'Only the host can do that.');
    }
    return seat;
  };

  /** Binds this socket to a seat and joins the Socket.IO room. */
  const bindSeat = (room, player) => {
    socket.data.playerId = player.id;
    socket.data.roomCode = room.code;
    player.socketId = socket.id;
    player.connection = 'connected';
    socket.join(room.code);
  };

  /** Detaches this socket from its seat. */
  const unbindSeat = (room) => {
    if (room) socket.leave(room.code);
    socket.data.roomCode = null;
  };

  /** Sends the full picture to one player: room, game and board. */
  const sendFullState = (room, playerId) => {
    room.sendStateTo(playerId);
    room.engine?.sendStateTo(playerId);
    room.emitTo(playerId, SERVER_DRAW_SNAPSHOT, { strokes: room.board.strokes.map(strokeJson) });
  };

  /** Removes a player and tells them why. */
  const evict = (room, targetId, reason) => {
    const target = room.playerById(targetId);
    if (!target) return;
    const targetSocket = target.socketId ? io.sockets.sockets.get(target.socketId) : null;
    room.emitTo(targetId, SERVER_YOU_KICKED, { reason });
    manager.removePlayer(room, targetId, { reason });
    if (targetSocket) {
      targetSocket.leave(room.code);
      targetSocket.data.roomCode = null;
    }
  };

  // -- handshake ------------------------------------------------------------

  on(socket, CLIENT_HELLO, 'time', (payload) => {
    const profile = sanitizeProfile(payload.profile ?? payload);
    if (!profile) {
      return errorAck(ERROR_CODE.validation, 'That name is not allowed.');
    }
    const playerId = profile.id ?? newId();
    socket.data.playerId = playerId;
    socket.data.profile = { ...profile, id: playerId };

    // Reconnect: a seat held open inside the grace window is rebound to this
    // socket and the player gets the whole picture again.
    const room = manager.roomOfPlayer(playerId);
    const seat = room?.playerById(playerId);
    if (room && seat) {
      manager.rebind(room, playerId, socket.id);
      bindSeat(room, seat);
      room.broadcastState();
      sendFullState(room, playerId);
      room.engine?.onPlayerReconnected(playerId);
      log.info(`room ${room.code}: ${seat.name} reconnected`);
    }
    return okAck({ serverTimeMs: Date.now(), playerId });
  });

  on(socket, CLIENT_TIME_PING, 'time', (payload) => ({
    t0: sanitizeInt(payload.t0, 0, Number.MAX_SAFE_INTEGER, 0),
    t1: Date.now(),
  }));

  // -- room lifecycle -------------------------------------------------------

  on(socket, CLIENT_ROOM_CREATE, 'room', (payload) => {
    const profile = sanitizeProfile(payload.profile ?? socket.data.profile);
    if (!profile) return errorAck(ERROR_CODE.validation, 'That name is not allowed.');
    const { settings, problems } = sanitizeSettings(payload.settings);
    if (problems.length > 0) return errorAck(ERROR_CODE.validation, problems[0]);

    const existing = currentRoom();
    if (existing) {
      manager.removePlayer(existing, socket.data.playerId, { reason: 'left' });
      unbindSeat(existing);
    }

    const identified = { ...profile, id: profile.id ?? socket.data.playerId ?? newId() };
    const { room, player } = manager.createRoom({ settings, profile: identified });
    bindSeat(room, player);
    room.broadcastState();
    room.engine.sendStateTo(player.id);
    room.systemMessage(`${player.name} created the room.`);
    return okAck({ room: roomJson(room), playerId: player.id });
  });

  on(socket, CLIENT_ROOM_JOIN, 'room', (payload) => {
    const profile = sanitizeProfile(payload.profile ?? socket.data.profile);
    if (!profile) return errorAck(ERROR_CODE.validation, 'That name is not allowed.');
    const code = normalizeRoomCode(payload.code);

    const existing = currentRoom();
    if (existing && existing.code !== code) {
      manager.removePlayer(existing, socket.data.playerId, { reason: 'left' });
      unbindSeat(existing);
    }

    const identified = { ...profile, id: profile.id ?? socket.data.playerId ?? newId() };
    const { room, player, rejoined } = manager.joinRoom({ code, profile: identified });
    bindSeat(room, player);
    if (!rejoined) {
      room.pushChat({
        senderId: player.id,
        senderName: player.name,
        text: `${player.name} joined.`,
        type: CHAT_TYPE.playerJoined,
      });
    }
    room.broadcastState();
    sendFullState(room, player.id);
    return okAck({ room: roomJson(room), playerId: player.id });
  });

  on(socket, CLIENT_ROOM_LEAVE, 'room', () => {
    const room = currentRoom();
    if (!room) return okAck();
    manager.removePlayer(room, socket.data.playerId, { reason: 'left' });
    unbindSeat(room);
    return okAck();
  });

  on(socket, CLIENT_ROOM_READY, 'room', (payload) => {
    const { room, player } = requireSeat();
    player.isReady = sanitizeBool(payload.ready, false);
    room.broadcastState();
    return okAck();
  });

  on(socket, CLIENT_ROOM_SETTINGS, 'room', (payload) => {
    const { room } = requireHost();
    if (room.status !== ROOM_STATUS.waiting || room.engine?.isActive()) {
      return errorAck(ERROR_CODE.gameInProgress, 'Settings can only change in the lobby.');
    }
    const { settings, problems } = sanitizeSettings(payload.settings, room.settings);
    if (problems.length > 0) return errorAck(ERROR_CODE.validation, problems[0]);
    if (settings.maxPlayers < room.players.size) settings.maxPlayers = room.players.size;
    room.settings = settings;
    room.broadcastState();
    return okAck();
  });

  // -- moderation -----------------------------------------------------------

  on(socket, CLIENT_ROOM_KICK, 'room', (payload) => {
    const { room, player } = requireHost();
    const targetId = sanitizeText(payload.playerId, 64);
    if (!targetId || targetId === player.id) {
      return errorAck(ERROR_CODE.invalidAction, 'Pick somebody else.');
    }
    if (!room.playerById(targetId)) return errorAck(ERROR_CODE.invalidAction, 'They are not in this room.');
    evict(room, targetId, 'kicked');
    return okAck();
  });

  on(socket, CLIENT_ROOM_BAN, 'room', (payload) => {
    const { room, player } = requireHost();
    const targetId = sanitizeText(payload.playerId, 64);
    if (!targetId || targetId === player.id) {
      return errorAck(ERROR_CODE.invalidAction, 'Pick somebody else.');
    }
    room.bannedIds.add(targetId);
    if (room.playerById(targetId)) evict(room, targetId, 'banned');
    else room.broadcastState();
    return okAck();
  });

  on(socket, CLIENT_ROOM_MUTE, 'room', (payload) => {
    const { room } = requireHost();
    const targetId = sanitizeText(payload.playerId, 64);
    const target = room.playerById(targetId);
    if (!target) return errorAck(ERROR_CODE.invalidAction, 'They are not in this room.');
    target.isMuted = sanitizeBool(payload.muted, true);
    room.broadcastState();
    return okAck();
  });

  on(socket, CLIENT_ROOM_TRANSFER_HOST, 'room', (payload) => {
    const { room } = requireHost();
    const targetId = sanitizeText(payload.playerId, 64);
    const target = room.playerById(targetId);
    if (!target) return errorAck(ERROR_CODE.invalidAction, 'They are not in this room.');
    if (room.transferHostTo(targetId)) {
      room.systemMessage(`${target.name} is the new host.`);
      room.broadcastState();
    }
    return okAck();
  });

  on(socket, CLIENT_ROOM_VOTE_KICK, 'room', (payload) => {
    const { room, player } = requireSeat();
    if (!room.settings.allowVoteKick) {
      return errorAck(ERROR_CODE.invalidAction, 'Vote kicking is off in this room.');
    }
    const targetId = sanitizeText(payload.playerId, 64);
    const target = room.playerById(targetId);
    if (!target || target.id === player.id) {
      return errorAck(ERROR_CODE.invalidAction, 'Pick somebody else.');
    }
    if (room.isHost(target.id)) return errorAck(ERROR_CODE.invalidAction, 'The host cannot be vote kicked.');
    const { votes, needed, passed } = room.voteKick(player.id, target.id);
    if (passed) {
      room.systemMessage(`${target.name} was vote kicked.`);
      evict(room, target.id, 'voteKicked');
    } else {
      room.systemMessage(`${votes}/${needed} votes to kick ${target.name}.`);
    }
    return okAck({ votes, needed, passed });
  });

  on(socket, CLIENT_ROOM_REPORT, 'room', (payload) => {
    const { room, player } = requireSeat();
    const targetId = sanitizeText(payload.playerId, 64);
    if (!room.playerById(targetId)) return errorAck(ERROR_CODE.invalidAction, 'They are not in this room.');
    const reason = sanitizeText(payload.reason, config.limits.maxReportLength);
    room.addReport(player.id, targetId, reason);
    log.warn(`report in ${room.code}: ${player.id} -> ${targetId}: ${reason}`);
    return okAck();
  });

  // -- game control ---------------------------------------------------------

  on(socket, CLIENT_GAME_START, 'room', () => {
    const { room } = requireHost();
    room.engine.start();
    return okAck();
  });

  on(socket, CLIENT_GAME_PLAY_AGAIN, 'room', () => {
    const { room } = requireHost();
    room.engine.playAgain();
    return okAck();
  });

  on(socket, CLIENT_GAME_SELECT_WORD, 'room', (payload) => {
    const { room, player } = requireSeat();
    // Drawer-only, word-selection-only. Both are enforced by the engine too.
    room.engine.selectWord(player.id, sanitizeInt(payload.index, 0, 16, 0));
    return okAck();
  });

  // -- drawing --------------------------------------------------------------

  /**
   * Every draw event needs the sender to be the current drawer during the
   * drawing phase. Anything else is dropped without a word to the client.
   */
  const drawingSeat = () => {
    const room = currentRoom();
    const player = room?.playerById(socket.data.playerId ?? '');
    if (!room || !player) return null;
    if (!room.engine?.isDrawingPhase()) return null;
    if (!room.engine.isDrawer(player.id)) return null;
    return { room, player };
  };

  on(socket, CLIENT_DRAW_BEGIN, 'draw', (payload) => {
    const seat = drawingSeat();
    if (!seat) return undefined;
    const stroke = sanitizeStroke(payload.stroke, seat.player.id);
    if (!seat.room.addStroke(stroke)) return undefined;
    seat.room.board.liveStrokeId = stroke.id;
    seat.room.broadcastExcept(seat.player.id, SERVER_DRAW_BEGIN, { stroke: strokeJson(stroke) });
    return undefined;
  });

  on(socket, CLIENT_DRAW_APPEND, 'draw', (payload) => {
    const seat = drawingSeat();
    if (!seat) return undefined;
    const strokeId = sanitizeText(payload.strokeId, 64);
    const stroke = seat.room.strokeById(strokeId);
    if (!stroke || stroke.authorId !== seat.player.id) return undefined;
    const points = sanitizePoints(payload.points, config.limits.maxPointsPerAppend);
    if (points.length === 0) return undefined;
    const overflow = stroke.points.length + points.length > config.limits.maxPointsPerStroke;
    if (overflow) return undefined;
    stroke.points.push(...points);
    seat.room.broadcastExcept(seat.player.id, SERVER_DRAW_APPEND, {
      strokeId,
      points: points.map((point) => [point.x, point.y]),
    });
    return undefined;
  });

  on(socket, CLIENT_DRAW_END, 'draw', (payload) => {
    const seat = drawingSeat();
    if (!seat) return undefined;
    const strokeId = sanitizeText(payload.strokeId, 64);
    if (!seat.room.strokeById(strokeId)) return undefined;
    if (seat.room.board.liveStrokeId === strokeId) seat.room.board.liveStrokeId = null;
    seat.room.broadcastExcept(seat.player.id, SERVER_DRAW_END, { strokeId });
    return undefined;
  });

  on(socket, CLIENT_DRAW_UNDO, 'draw', () => {
    const seat = drawingSeat();
    if (!seat) return undefined;
    const removed = seat.room.undoStroke(seat.player.id);
    if (!removed) return undefined;
    seat.room.broadcastExcept(seat.player.id, SERVER_DRAW_UNDO, { strokeId: removed.id });
    return undefined;
  });

  on(socket, CLIENT_DRAW_REDO, 'draw', () => {
    const seat = drawingSeat();
    if (!seat) return undefined;
    const restored = seat.room.redoStroke(seat.player.id);
    if (!restored) return undefined;
    seat.room.broadcastExcept(seat.player.id, SERVER_DRAW_REDO, { stroke: strokeJson(restored) });
    return undefined;
  });

  on(socket, CLIENT_DRAW_CLEAR, 'draw', () => {
    const seat = drawingSeat();
    if (!seat) return undefined;
    seat.room.clearBoard();
    seat.room.broadcastExcept(seat.player.id, SERVER_DRAW_CLEAR, {});
    return undefined;
  });

  // -- chat and guessing ----------------------------------------------------

  on(socket, CLIENT_CHAT_SEND, 'chat', (payload) => {
    const { room, player } = requireSeat();
    const text = sanitizeText(payload.text, config.limits.maxChatLength);
    if (text.length === 0) return okAck();
    // Muted players are dropped silently: they must not learn they are muted.
    room.engine.handleChat(player, text);
    return okAck();
  });

  // -- teardown -------------------------------------------------------------

  socket.on('disconnect', (reason) => {
    try {
      const room = currentRoom();
      const playerId = socket.data.playerId;
      if (!room || !playerId) return;
      const player = room.playerById(playerId);
      if (!player || player.socketId !== socket.id) return;
      log.debug(`room ${room.code}: ${player.name} dropped (${reason})`);
      manager.markDisconnected(room, playerId);
    } catch (error) {
      log.error('disconnect handler failed', error);
    }
  });

  socket.on('error', (error) => {
    log.warn(`socket ${socket.id} error`, error);
    try {
      socket.emit(SERVER_ERROR, { error: failureJson(ERROR_CODE.serverError, 'Socket error.') });
    } catch {
      // The socket is already gone; nothing to do.
    }
  });
}

/**
 * Wires the server up: per-socket handlers plus the periodic clock broadcast.
 *
 * @param {import('socket.io').Server} io
 * @param {import('./RoomManager.js').RoomManager} manager
 * @returns {() => void} a teardown function
 */
export function registerHandlers(io, manager) {
  io.on('connection', (socket) => {
    log.debug(`socket ${socket.id} connected`);
    try {
      attachHandlers(io, manager, socket);
    } catch (error) {
      log.error('failed to attach handlers', error);
      socket.disconnect(true);
    }
  });

  const sync = setInterval(() => {
    io.emit(SERVER_TIME_SYNC, { serverTimeMs: Date.now() });
  }, config.timing.timeSyncIntervalMs);
  if (typeof sync.unref === 'function') sync.unref();

  return () => clearInterval(sync);
}

/** Exposed for tests: the phases in which the board accepts drawing events. */
export const DRAWABLE_PHASES = Object.freeze([PHASE.drawing]);

export default registerHandlers;
