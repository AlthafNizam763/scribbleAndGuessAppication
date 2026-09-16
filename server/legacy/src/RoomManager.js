/**
 * The room registry: creation with unique codes, joining and leaving, the
 * reconnect grace window, host succession and idle-room reaping.
 *
 * Every timer it starts is owned by a `TimerBag`, so a destroyed room provably
 * leaves nothing behind.
 */

import { config } from './config.js';
import { GameEngine } from './GameEngine.js';
import { isValidRoomCode, newId, newRoomCode, normalizeRoomCode } from './ids.js';
import { logger } from './logger.js';
import { CHAT_TYPE, CONNECTION, ERROR_CODE, ROOM_STATUS, SERVER_ROOM_CLOSED } from './protocol.js';
import { createPlayer, Room, TimerBag } from './Room.js';

const log = logger.child('rooms');

/** A rule violation a handler should turn into an error ack. */
export class RoomError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'RoomError';
    this.code = code;
  }
}

export class RoomManager {
  /**
   * @param {import('socket.io').Server} io
   */
  constructor(io) {
    this.io = io;
    /** @type {Map<string, Room>} code -> room */
    this.rooms = new Map();
    /** @type {Map<string, string>} playerId -> room code, for reconnects. */
    this.playerIndex = new Map();
    this.timers = new TimerBag();
    this.startedAtMs = Date.now();
    this.stopped = false;
  }

  /** Starts the idle-room reaper. */
  start() {
    this.timers.every('reaper', () => this.reapIdleRooms(), config.timing.reaperIntervalMs);
  }

  /** Stops every timer this manager and its rooms own. */
  stop() {
    this.stopped = true;
    this.timers.clearAll();
    for (const room of [...this.rooms.values()]) room.destroy();
    this.rooms.clear();
    this.playerIndex.clear();
  }

  // -------------------------------------------------------------------------
  // Lookup
  // -------------------------------------------------------------------------

  /** The room with `code`, or `undefined`. Codes are case-insensitive. */
  getRoom(code) {
    return this.rooms.get(normalizeRoomCode(code));
  }

  /** The room `playerId` is seated in, or `undefined`. */
  roomOfPlayer(playerId) {
    const code = this.playerIndex.get(playerId);
    return code ? this.rooms.get(code) : undefined;
  }

  /** A code no live room is using. */
  #allocateCode() {
    for (let attempt = 0; attempt < 64; attempt++) {
      const code = newRoomCode();
      if (!this.rooms.has(code)) return code;
    }
    throw new RoomError(ERROR_CODE.serverError, 'Could not allocate a room code.');
  }

  // -------------------------------------------------------------------------
  // Creating and joining
  // -------------------------------------------------------------------------

  /**
   * Creates a room owned by `profile`.
   * @param {{settings: object, profile: {id?: string, name: string, avatarId: number, avatarColorIndex: number}}} args
   * @returns {{room: Room, player: object}}
   */
  createRoom({ settings, profile }) {
    if (this.rooms.size >= config.limits.maxRooms) {
      throw new RoomError(ERROR_CODE.serverError, 'The server is full; try again shortly.');
    }
    const code = this.#allocateCode();
    const playerId = profile.id && String(profile.id).trim() ? String(profile.id).trim() : newId();
    const room = new Room({ code, hostId: playerId, settings, io: this.io });
    room.engine = new GameEngine(room);
    const player = createPlayer({
      id: playerId,
      name: profile.name,
      avatarId: profile.avatarId,
      avatarColorIndex: profile.avatarColorIndex,
      isHost: true,
      joinedAtMs: Date.now(),
    });
    player.isReady = true;
    room.addPlayer(player);
    this.rooms.set(code, room);
    this.playerIndex.set(playerId, code);
    log.info(`created room ${code} for ${player.name}`);
    return { room, player };
  }

  /**
   * Seats `profile` in the room with `code`.
   * @returns {{room: Room, player: object, rejoined: boolean}}
   */
  joinRoom({ code, profile }) {
    const normalized = normalizeRoomCode(code);
    if (!isValidRoomCode(normalized)) {
      throw new RoomError(ERROR_CODE.invalidCode, 'That room code does not look right.');
    }
    const room = this.rooms.get(normalized);
    if (!room) {
      throw new RoomError(ERROR_CODE.roomNotFound, 'No room with that code.');
    }
    const wantedId = profile.id && String(profile.id).trim() ? String(profile.id).trim() : null;

    // A seat held open for this player (reconnect or a second join attempt).
    const existing = wantedId ? room.playerById(wantedId) : null;
    if (existing) {
      existing.name = profile.name;
      existing.avatarId = profile.avatarId;
      existing.avatarColorIndex = profile.avatarColorIndex;
      existing.connection = CONNECTION.connected;
      existing.lastSeenMs = Date.now();
      room.timers.cancel(`grace:${existing.id}`);
      this.playerIndex.set(existing.id, room.code);
      return { room, player: existing, rejoined: true };
    }

    if (room.isBanned(wantedId ?? '')) {
      throw new RoomError(ERROR_CODE.banned, 'You are banned from this room.');
    }
    if (room.isFull()) {
      throw new RoomError(ERROR_CODE.roomFull, 'That room is full.');
    }
    if (room.status === ROOM_STATUS.inGame) {
      throw new RoomError(ERROR_CODE.gameInProgress, 'That game already started.');
    }
    if (room.isNameTaken(profile.name)) {
      throw new RoomError(ERROR_CODE.nameTaken, 'Somebody in that room already uses this name.');
    }

    const player = createPlayer({
      id: wantedId ?? newId(),
      name: profile.name,
      avatarId: profile.avatarId,
      avatarColorIndex: profile.avatarColorIndex,
      isHost: false,
      joinedAtMs: Date.now(),
    });
    room.addPlayer(player);
    this.playerIndex.set(player.id, room.code);
    log.info(`${player.name} joined room ${room.code} (${room.players.size}/${room.settings.maxPlayers})`);
    return { room, player, rejoined: false };
  }

  // -------------------------------------------------------------------------
  // Leaving
  // -------------------------------------------------------------------------

  /**
   * Removes a player for good and repairs the room around the hole they left:
   * host succession, an interrupted turn, and destruction when nobody is left.
   *
   * @param {Room} room
   * @param {string} playerId
   * @param {{reason?: string, announce?: boolean}} [options]
   */
  removePlayer(room, playerId, { reason = 'left', announce = true } = {}) {
    const player = room.playerById(playerId);
    if (!player) return null;
    const wasHost = room.isHost(playerId);
    room.removePlayer(playerId);
    if (this.playerIndex.get(playerId) === room.code) this.playerIndex.delete(playerId);

    if (announce) {
      room.pushChat({
        senderId: player.id,
        senderName: player.name,
        text: `${player.name} left.`,
        type: CHAT_TYPE.playerLeft,
      });
    }

    if (room.isEmpty()) {
      this.destroyRoom(room.code, reason);
      return player;
    }

    if (wasHost) {
      const heir = room.longestPresentConnected();
      if (heir && room.transferHostTo(heir.id)) {
        room.systemMessage(`${heir.name} is the new host.`);
      }
    }

    room.engine?.onPlayerGone(playerId);
    room.broadcastState();
    return player;
  }

  /**
   * Marks a player as reconnecting and starts the grace timer that will
   * remove them if they do not come back.
   */
  markDisconnected(room, playerId) {
    const player = room.playerById(playerId);
    if (!player) return;
    player.connection = CONNECTION.reconnecting;
    player.socketId = null;
    player.isReady = false;
    player.lastSeenMs = Date.now();
    room.broadcastState();
    room.engine?.onPlayerDisconnected(playerId);
    room.timers.set(
      `grace:${playerId}`,
      () => {
        const stillHere = room.playerById(playerId);
        if (!stillHere || stillHere.connection === CONNECTION.connected) return;
        log.info(`room ${room.code}: reconnect window expired for ${stillHere.name}`);
        this.removePlayer(room, playerId, { reason: 'timeout' });
      },
      config.timing.reconnectGraceMs,
    );
  }

  /** Rebinds a returning player to a new socket. */
  rebind(room, playerId, socketId) {
    const player = room.playerById(playerId);
    if (!player) return null;
    room.timers.cancel(`grace:${playerId}`);
    player.socketId = socketId;
    player.connection = CONNECTION.connected;
    player.lastSeenMs = Date.now();
    this.playerIndex.set(playerId, room.code);
    room.touch();
    return player;
  }

  /** Closes a room and clears every timer it owns. */
  destroyRoom(code, reason = 'closed') {
    const room = this.rooms.get(normalizeRoomCode(code));
    if (!room) return false;
    room.broadcast(SERVER_ROOM_CLOSED, { reason });
    for (const playerId of room.players.keys()) {
      if (this.playerIndex.get(playerId) === room.code) this.playerIndex.delete(playerId);
    }
    room.destroy();
    this.rooms.delete(room.code);
    log.info(`destroyed room ${room.code} (${reason})`);
    return true;
  }

  /** Destroys rooms that have had nobody connected for `idleRoomMs`. */
  reapIdleRooms(now = Date.now()) {
    let reaped = 0;
    for (const room of [...this.rooms.values()]) {
      const connected = room.connectedPlayers().length;
      if (connected > 0) {
        room.touch();
        continue;
      }
      if (now - room.lastActivityMs >= config.timing.idleRoomMs) {
        this.destroyRoom(room.code, 'idle');
        reaped++;
      }
    }
    return reaped;
  }

  // -------------------------------------------------------------------------
  // Diagnostics
  // -------------------------------------------------------------------------

  /** A snapshot for the `/stats` endpoint. Room codes are opt-in only. */
  stats() {
    let players = 0;
    let connected = 0;
    let inGame = 0;
    const rooms = [];
    for (const room of this.rooms.values()) {
      players += room.players.size;
      connected += room.connectedPlayers().length;
      if (room.status === ROOM_STATUS.inGame) inGame++;
      rooms.push({
        ...(config.exposeRoomCodes ? { code: room.code } : {}),
        players: room.players.size,
        connected: room.connectedPlayers().length,
        status: room.status,
        phase: room.engine?.state.phase ?? 'lobby',
        round: room.engine?.state.currentRound ?? 0,
        totalRounds: room.engine?.state.totalRounds ?? 0,
        timers: room.timers.size + (room.engine?.timers.size ?? 0),
        ageMs: Date.now() - room.createdAtMs,
      });
    }
    return {
      uptimeMs: Date.now() - this.startedAtMs,
      rooms: this.rooms.size,
      roomsInGame: inGame,
      players,
      connectedPlayers: connected,
      detail: rooms,
    };
  }
}

export default RoomManager;
