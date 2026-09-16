/**
 * Room state: the seated players, the host-configured settings, the shared
 * drawing board, chat history and every moderation decision.
 *
 * A Room owns no game logic - that is `GameEngine` - but it owns the data the
 * engine mutates and every outbound emit, including the per-recipient fan-out
 * the word-secrecy rule depends on.
 */

import { config } from './config.js';
import { newId } from './ids.js';
import { CHAT_TYPE, CONNECTION, ROOM_STATUS, SERVER_CHAT_MESSAGE, SERVER_ROOM_STATE } from './protocol.js';
import { chatMessageJson, roomJson } from './serialize.js';

/**
 * A named collection of timers.
 *
 * Every `setTimeout` / `setInterval` in the server is created through a bag so
 * that destroying a room or ending a turn provably cancels all of them - no
 * leaked timers, ever. Setting a name twice cancels the previous timer first.
 */
export class TimerBag {
  constructor() {
    /** @type {Map<string, {handle: NodeJS.Timeout, repeating: boolean}>} */
    this.entries = new Map();
  }

  /** Schedules a one-shot timer under `name`, replacing any previous one. */
  set(name, fn, ms) {
    this.cancel(name);
    const handle = setTimeout(() => {
      this.entries.delete(name);
      fn();
    }, Math.max(0, Math.trunc(ms) || 0));
    if (typeof handle.unref === 'function') handle.unref();
    this.entries.set(name, { handle, repeating: false });
    return name;
  }

  /** Schedules a repeating timer under `name`, replacing any previous one. */
  every(name, fn, ms) {
    this.cancel(name);
    const handle = setInterval(fn, Math.max(1, Math.trunc(ms) || 1));
    if (typeof handle.unref === 'function') handle.unref();
    this.entries.set(name, { handle, repeating: true });
    return name;
  }

  /** Cancels the timer registered under `name`, if any. */
  cancel(name) {
    const entry = this.entries.get(name);
    if (!entry) return false;
    if (entry.repeating) clearInterval(entry.handle);
    else clearTimeout(entry.handle);
    this.entries.delete(name);
    return true;
  }

  /** Cancels every timer whose name starts with `prefix`. */
  cancelPrefix(prefix) {
    for (const name of [...this.entries.keys()]) {
      if (name.startsWith(prefix)) this.cancel(name);
    }
  }

  /** Cancels everything. Called on room destruction. */
  clearAll() {
    for (const name of [...this.entries.keys()]) this.cancel(name);
  }

  /** How many timers are live. Used by /stats and by the tests. */
  get size() {
    return this.entries.size;
  }
}

/**
 * Creates the server-side record of a seated player.
 * Field names match `lib/models/player.dart` one for one.
 */
export function createPlayer({
  id,
  name,
  avatarId = 0,
  avatarColorIndex = 0,
  isHost = false,
  socketId = null,
  joinedAtMs = Date.now(),
}) {
  return {
    id,
    name,
    avatarId,
    avatarColorIndex,
    score: 0,
    roundScore: 0,
    isHost,
    isReady: false,
    isDrawing: false,
    hasGuessed: false,
    guessOrder: null,
    isMuted: false,
    connection: CONNECTION.connected,
    // Server-only bookkeeping, never serialized.
    socketId,
    joinedAtMs,
    lastSeenMs: joinedAtMs,
  };
}

/** One room and everyone in it. */
export class Room {
  /**
   * @param {{code: string, hostId: string, settings: object, io: import('socket.io').Server, now?: number}} options
   */
  constructor({ code, hostId, settings, io, now = Date.now() }) {
    this.code = code;
    this.hostId = hostId;
    this.settings = settings;
    this.io = io;
    this.status = ROOM_STATUS.waiting;
    this.createdAtMs = now;
    this.lastActivityMs = now;

    /** @type {Map<string, ReturnType<typeof createPlayer>>} */
    this.players = new Map();
    /** Seating order, which is also turn order. */
    this.order = [];
    /** @type {Set<string>} */
    this.bannedIds = new Set();
    /** @type {Map<string, Set<string>>} target id -> voter ids */
    this.voteKicks = new Map();
    /** @type {{playerId: string, reporterId: string, reason: string, atMs: number}[]} */
    this.reports = [];

    /** The shared drawing board. */
    this.board = { strokes: [], redo: [], liveStrokeId: null };
    /** @type {object[]} bounded chat history, newest last. */
    this.chat = [];

    /** Room-scoped timers (reconnect grace, and whatever the engine adds). */
    this.timers = new TimerBag();
    /** @type {import('./GameEngine.js').GameEngine | null} */
    this.engine = null;
    this.destroyed = false;
  }

  // -------------------------------------------------------------------------
  // Membership
  // -------------------------------------------------------------------------

  /** Players in seating order. */
  orderedPlayers() {
    const out = [];
    for (const id of this.order) {
      const player = this.players.get(id);
      if (player) out.push(player);
    }
    return out;
  }

  /** The seated player with `id`, or `undefined`. */
  playerById(id) {
    return this.players.get(id);
  }

  /** Players holding a live socket. */
  connectedPlayers() {
    return this.orderedPlayers().filter((player) => player.connection === CONNECTION.connected);
  }

  /** Players holding a live socket, excluding `id`. */
  connectedOthers(id) {
    return this.connectedPlayers().filter((player) => player.id !== id);
  }

  /** Whether every seat is taken. */
  isFull() {
    return this.players.size >= this.settings.maxPlayers;
  }

  /** Whether the room has nobody left at all. */
  isEmpty() {
    return this.players.size === 0;
  }

  /** Whether `id` is the host. */
  isHost(id) {
    return Boolean(id) && id === this.hostId;
  }

  /** Whether `id` is banned from this room. */
  isBanned(id) {
    return this.bannedIds.has(id);
  }

  /** How many seated players pressed ready. */
  readyCount() {
    let count = 0;
    for (const player of this.players.values()) {
      if (player.isReady) count++;
    }
    return count;
  }

  /** Whether `name` is already taken by another seated player. */
  isNameTaken(name, exceptId = null) {
    const wanted = String(name).trim().toLowerCase();
    for (const player of this.players.values()) {
      if (player.id === exceptId) continue;
      if (player.name.trim().toLowerCase() === wanted) return true;
    }
    return false;
  }

  /** Seats `player`, appending to the turn order. */
  addPlayer(player) {
    this.players.set(player.id, player);
    if (!this.order.includes(player.id)) this.order.push(player.id);
    this.touch();
    return player;
  }

  /** Removes `id` from the room, dropping its votes. */
  removePlayer(id) {
    const player = this.players.get(id);
    if (!player) return null;
    this.players.delete(id);
    this.order = this.order.filter((entry) => entry !== id);
    this.voteKicks.delete(id);
    for (const voters of this.voteKicks.values()) voters.delete(id);
    this.timers.cancel(`grace:${id}`);
    this.touch();
    return player;
  }

  /**
   * The connected player who has been here longest, excluding `exceptId`.
   * This is who inherits the host role.
   */
  longestPresentConnected(exceptId = null) {
    let best = null;
    for (const player of this.orderedPlayers()) {
      if (player.id === exceptId) continue;
      if (player.connection !== CONNECTION.connected) continue;
      if (best === null || player.joinedAtMs < best.joinedAtMs) best = player;
    }
    if (best) return best;
    // Nobody is connected: fall back to the longest-present seat of any state.
    for (const player of this.orderedPlayers()) {
      if (player.id === exceptId) continue;
      if (best === null || player.joinedAtMs < best.joinedAtMs) best = player;
    }
    return best;
  }

  /** Moves the host crown to `playerId`. Returns whether anything changed. */
  transferHostTo(playerId) {
    const next = this.players.get(playerId);
    if (!next || next.id === this.hostId) return false;
    const previous = this.players.get(this.hostId);
    if (previous) previous.isHost = false;
    next.isHost = true;
    this.hostId = next.id;
    this.touch();
    return true;
  }

  // -------------------------------------------------------------------------
  // Moderation
  // -------------------------------------------------------------------------

  /**
   * Records a vote-kick from `voterId` against `targetId`.
   * @returns {{votes: number, needed: number, passed: boolean}}
   */
  voteKick(voterId, targetId) {
    let voters = this.voteKicks.get(targetId);
    if (!voters) {
      voters = new Set();
      this.voteKicks.set(targetId, voters);
    }
    voters.add(voterId);
    const eligible = this.connectedOthers(targetId).length;
    const needed = Math.max(2, Math.floor(eligible / 2) + 1);
    this.touch();
    return { votes: voters.size, needed, passed: voters.size >= needed };
  }

  /** Files a report. Kept in memory only; a real deployment would persist it. */
  addReport(reporterId, playerId, reason) {
    this.reports.push({ reporterId, playerId, reason, atMs: Date.now() });
    if (this.reports.length > 200) this.reports.shift();
    this.touch();
  }

  // -------------------------------------------------------------------------
  // Board
  // -------------------------------------------------------------------------

  /** Empties the board and its redo stack. */
  clearBoard() {
    this.board.strokes = [];
    this.board.redo = [];
    this.board.liveStrokeId = null;
  }

  /** Appends a stroke, honouring the per-board cap. */
  addStroke(stroke) {
    if (this.board.strokes.length >= config.limits.maxStrokesPerBoard) return false;
    this.board.strokes.push(stroke);
    this.board.redo = [];
    return true;
  }

  /** Finds a live stroke by id. */
  strokeById(strokeId) {
    return this.board.strokes.find((stroke) => stroke.id === strokeId);
  }

  /** Removes the last stroke authored by `authorId`, pushing it onto redo. */
  undoStroke(authorId) {
    for (let i = this.board.strokes.length - 1; i >= 0; i--) {
      if (this.board.strokes[i].authorId !== authorId) continue;
      const [removed] = this.board.strokes.splice(i, 1);
      this.board.redo.push(removed);
      if (this.board.redo.length > config.limits.maxRedoStack) this.board.redo.shift();
      return removed;
    }
    return null;
  }

  /** Restores the last undone stroke of `authorId`. */
  redoStroke(authorId) {
    for (let i = this.board.redo.length - 1; i >= 0; i--) {
      if (this.board.redo[i].authorId !== authorId) continue;
      const [restored] = this.board.redo.splice(i, 1);
      if (this.board.strokes.length >= config.limits.maxStrokesPerBoard) return null;
      this.board.strokes.push(restored);
      return restored;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Emission
  // -------------------------------------------------------------------------

  /** Marks the room as active, keeping the reaper away. */
  touch() {
    this.lastActivityMs = Date.now();
  }

  /** Sends `payload` to every socket in the room. */
  broadcast(event, payload) {
    if (this.destroyed) return;
    this.io.to(this.code).emit(event, payload);
  }

  /** Sends `payload` to one player, if they hold a live socket. */
  emitTo(playerId, event, payload) {
    if (this.destroyed) return;
    const player = this.players.get(playerId);
    if (!player?.socketId) return;
    this.io.to(player.socketId).emit(event, payload);
  }

  /** Sends to everyone but `playerId`. */
  broadcastExcept(playerId, event, payload) {
    for (const player of this.players.values()) {
      if (player.id === playerId) continue;
      this.emitTo(player.id, event, payload);
    }
  }

  /**
   * Builds a payload per recipient and sends each one only to that player.
   *
   * This is how the game state reaches the room: the drawer's payload carries
   * the word, everybody else's does not, and there is no code path where one
   * player's payload could be broadcast to another.
   *
   * @param {string} event
   * @param {(playerId: string) => object} build
   */
  broadcastPerRecipient(event, build) {
    for (const player of this.players.values()) {
      if (!player.socketId) continue;
      this.emitTo(player.id, event, build(player.id));
    }
  }

  /** Broadcasts the full room snapshot. */
  broadcastState() {
    this.broadcast(SERVER_ROOM_STATE, { room: roomJson(this) });
  }

  /** Sends the full room snapshot to a single player. */
  sendStateTo(playerId) {
    this.emitTo(playerId, SERVER_ROOM_STATE, { room: roomJson(this) });
  }

  /**
   * Appends a chat row to the history and broadcasts it.
   * @param {{senderId?: string, senderName?: string, text: string, type: string}} message
   */
  pushChat(message) {
    const row = chatMessageJson({
      id: newId(),
      senderId: message.senderId ?? '',
      senderName: message.senderName ?? '',
      text: message.text ?? '',
      type: message.type ?? CHAT_TYPE.chat,
      timestampMs: Date.now(),
    });
    this.chat.push(row);
    if (this.chat.length > config.limits.chatHistoryLimit) this.chat.shift();
    this.broadcast(SERVER_CHAT_MESSAGE, { message: row });
    this.touch();
    return row;
  }

  /** Sends a chat row to exactly one player, without touching the history. */
  sendChatTo(playerId, message) {
    const row = chatMessageJson({
      id: newId(),
      senderId: message.senderId ?? '',
      senderName: message.senderName ?? '',
      text: message.text ?? '',
      type: message.type ?? CHAT_TYPE.chat,
      timestampMs: Date.now(),
    });
    this.emitTo(playerId, SERVER_CHAT_MESSAGE, { message: row });
    return row;
  }

  /** Convenience for a server announcement. */
  systemMessage(text) {
    return this.pushChat({ senderId: '', senderName: '', text, type: CHAT_TYPE.system });
  }

  /** Cancels every timer this room and its engine own. */
  destroy() {
    this.destroyed = true;
    this.engine?.destroy();
    this.timers.clearAll();
    this.players.clear();
    this.order = [];
    this.chat = [];
    this.clearBoard();
  }
}

export default Room;
