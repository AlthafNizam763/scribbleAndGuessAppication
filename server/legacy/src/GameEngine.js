/**
 * The authoritative round/turn lifecycle.
 *
 *   lobby -> starting -> [ wordSelection -> drawing -> roundEnd ] * turns -> gameEnd
 *
 * A game runs `settings.rounds` rounds, and every round gives every seated
 * player exactly one drawing turn, so `rounds: 3` with 4 players is 12 turns.
 * `currentRound` is one-based; `turnIndex` is the 0-based seat inside a round.
 *
 * Everything that decides the outcome of a game lives here and nowhere else:
 * the clock, the phase transitions, correct-answer detection, hint scheduling
 * and every point awarded. The client is never trusted with any of it.
 */

import { config } from './config.js';
import { evaluate, normalize } from './guess.js';
import { maskWord, nextHintIndices } from './hints.js';
import { newId, systemRandom } from './ids.js';
import { logger } from './logger.js';
import {
  CHAT_TYPE,
  ERROR_CODE,
  PHASE,
  ROOM_STATUS,
  SERVER_DRAW_CLEAR,
  SERVER_GAME_END,
  SERVER_GAME_HINT,
  SERVER_GAME_ROUND_END,
  SERVER_GAME_ROUND_START,
  SERVER_GAME_STATE,
  SERVER_GAME_WORD_CHOICES,
  VERDICT,
  WORD_MODE,
} from './protocol.js';
import { TimerBag } from './Room.js';
import { scoring } from './scoring.js';
import { gameStateJson, gameResultJson, roundResultJson, standingsFrom, wordItemJson } from './serialize.js';
import { pickChoices, poolFor } from './words.js';

const log = logger.child('game');

/** A rule violation a handler should turn into an error ack. */
export class EngineError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'EngineError';
    this.code = code;
  }
}

/** Timer names, so cancellation is never a guessing game. */
const TIMER = Object.freeze({
  countdown: 'countdown',
  wordSelect: 'wordSelect',
  turnEnd: 'turnEnd',
  roundEnd: 'roundEnd',
  gameEnd: 'gameEnd',
  hintPrefix: 'hint:',
});

/** The state of a game that has not started. Mirrors `GameState.initial`. */
function lobbyState(roomCode) {
  return {
    roomCode,
    phase: PHASE.lobby,
    currentRound: 0,
    totalRounds: 0,
    turnIndex: 0,
    drawerId: null,
    word: null,
    wordItem: null,
    maskedWord: '',
    wordLength: 0,
    hintIndices: [],
    turnStartMs: 0,
    turnEndMs: 0,
    correctGuesserIds: [],
    roundScores: {},
    wordChoices: [],
  };
}

export class GameEngine {
  /**
   * @param {import('./Room.js').Room} room
   * @param {{random?: {nextInt: (max: number) => number}}} [options]
   */
  constructor(room, { random = systemRandom } = {}) {
    this.room = room;
    this.random = random;
    this.timers = new TimerBag();
    this.state = lobbyState(room.code);
    /** Lower-cased words already drawn this game. */
    this.usedWords = new Set();
    /** Seat order captured when the game started. */
    this.turnOrder = [];
    /** Ids that could have guessed this turn, captured when drawing began. */
    this.eligibleGuessers = new Set();
    this.destroyed = false;
  }

  // -------------------------------------------------------------------------
  // Snapshots
  // -------------------------------------------------------------------------

  /**
   * The game state as `recipientId` is allowed to see it.
   *
   * SECURITY: this is the ONLY way a game state leaves the server. The
   * serializer decides from the recipient id whether `word` and `wordChoices`
   * may be included, so a caller cannot leak the word by mistake.
   */
  stateFor(recipientId) {
    return gameStateJson(this.state, recipientId);
  }

  /** Sends a per-recipient `s:game:state` to everyone in the room. */
  broadcastState() {
    this.room.broadcastPerRecipient(SERVER_GAME_STATE, (playerId) => ({ game: this.stateFor(playerId) }));
  }

  /** Sends `s:game:state` to a single player. */
  sendStateTo(playerId) {
    this.room.emitTo(playerId, SERVER_GAME_STATE, { game: this.stateFor(playerId) });
  }

  /** Whether a turn is currently being drawn. */
  isDrawingPhase() {
    return this.state.phase === PHASE.drawing;
  }

  /** Whether `playerId` is the drawer of the current turn. */
  isDrawer(playerId) {
    return Boolean(playerId) && playerId === this.state.drawerId;
  }

  /** Whether the room is between the lobby and the results screen. */
  isActive() {
    return this.state.phase !== PHASE.lobby && this.state.phase !== PHASE.gameEnd;
  }

  // -------------------------------------------------------------------------
  // Starting a game
  // -------------------------------------------------------------------------

  /**
   * Whether the room may start right now. Mirrors `RoomStateMachine.canStart`:
   * enough players, still waiting, and everyone but the host ready.
   */
  canStart() {
    if (this.room.status !== ROOM_STATUS.waiting) return false;
    if (this.room.connectedPlayers().length < config.limits.minPlayersToStart) return false;
    for (const player of this.room.orderedPlayers()) {
      if (this.room.isHost(player.id)) continue;
      if (player.connection !== 'connected') continue;
      if (!player.isReady) return false;
    }
    return true;
  }

  /**
   * Starts a match. Throws `EngineError` when the room is not startable.
   * @param {{requireReady?: boolean}} [options]
   */
  start({ requireReady = true } = {}) {
    if (this.isActive()) {
      throw new EngineError(ERROR_CODE.gameInProgress, 'A game is already running in this room.');
    }
    if (this.room.connectedPlayers().length < config.limits.minPlayersToStart) {
      throw new EngineError(
        ERROR_CODE.invalidAction,
        `At least ${config.limits.minPlayersToStart} connected players are needed to start.`,
      );
    }
    if (requireReady && !this.canStart()) {
      throw new EngineError(ERROR_CODE.invalidAction, 'Everyone but the host must be ready.');
    }

    this.timers.clearAll();
    this.usedWords.clear();
    this.turnOrder = this.room.connectedPlayers().map((player) => player.id);
    this.room.status = ROOM_STATUS.inGame;
    for (const player of this.room.players.values()) {
      player.score = 0;
      player.roundScore = 0;
      player.hasGuessed = false;
      player.guessOrder = null;
      player.isDrawing = false;
      player.isReady = false;
    }

    this.state = lobbyState(this.room.code);
    this.state.phase = PHASE.starting;
    this.state.totalRounds = this.room.settings.rounds;
    this.state.currentRound = 0;
    this.state.turnIndex = 0;

    this.room.clearBoard();
    this.room.broadcast(SERVER_DRAW_CLEAR, {});
    this.room.broadcastState();
    this.broadcastState();
    this.room.systemMessage('The game is starting!');

    this.timers.set(TIMER.countdown, () => this.#beginRound(1), config.timing.startCountdownMs);
    log.info(`room ${this.room.code}: game starting (${this.turnOrder.length} seats, ${this.state.totalRounds} rounds)`);
    return true;
  }

  /** Restarts with the same players. Ready flags are not required. */
  playAgain() {
    if (this.isActive()) {
      throw new EngineError(ERROR_CODE.gameInProgress, 'A game is already running in this room.');
    }
    return this.start({ requireReady: false });
  }

  // -------------------------------------------------------------------------
  // Round and turn lifecycle
  // -------------------------------------------------------------------------

  #beginRound(round) {
    if (this.destroyed) return;
    this.state.currentRound = round;
    this.state.turnIndex = 0;
    this.#beginTurn();
  }

  /**
   * Opens the word-selection phase for the seat at `turnIndex`, skipping seats
   * whose player has left or dropped.
   */
  #beginTurn() {
    if (this.destroyed) return;
    const drawer = this.#resolveDrawer();
    if (!drawer) {
      // Every remaining seat of this round is empty: move the game on.
      this.#advance();
      return;
    }
    if (this.room.connectedPlayers().length < config.limits.minPlayersToStart) {
      this.#abort('Not enough players left to continue.');
      return;
    }

    this.timers.clearAll();
    this.room.clearBoard();
    this.room.broadcast(SERVER_DRAW_CLEAR, {});

    for (const player of this.room.players.values()) {
      player.hasGuessed = false;
      player.guessOrder = null;
      player.roundScore = 0;
      player.isDrawing = player.id === drawer.id;
    }

    this.state.phase = PHASE.wordSelection;
    this.state.drawerId = drawer.id;
    this.state.word = null;
    this.state.wordItem = null;
    this.state.maskedWord = '';
    this.state.wordLength = 0;
    this.state.hintIndices = [];
    this.state.turnStartMs = 0;
    this.state.turnEndMs = 0;
    this.state.correctGuesserIds = [];
    this.state.roundScores = {};
    this.state.wordChoices = this.#buildChoices();
    this.eligibleGuessers = new Set();

    this.room.broadcastState();
    this.broadcastState();

    if (this.state.wordChoices.length === 0) {
      // No words at all: nothing can be drawn, so skip straight past the turn.
      log.warn(`room ${this.room.code}: no words available; skipping turn`);
      this.#endTurn('noWords');
      return;
    }

    if (this.room.settings.wordMode === WORD_MODE.random) {
      // Random mode never asks: the server picks and the turn begins at once.
      this.#commitWord(0);
      return;
    }

    // The offer is drawer-only. Non-drawers never learn the candidate words.
    this.room.emitTo(drawer.id, SERVER_GAME_WORD_CHOICES, {
      choices: this.state.wordChoices.map(wordItemJson),
    });
    this.room.systemMessage(`${drawer.name} is choosing a word.`);

    this.timers.set(
      TIMER.wordSelect,
      () => {
        if (this.state.phase !== PHASE.wordSelection) return;
        this.#commitWord(0);
      },
      this.room.settings.wordSelectSeconds * 1000,
    );
  }

  /** The player who should draw the current seat, or `null` when none can. */
  #resolveDrawer() {
    while (this.state.turnIndex < this.turnOrder.length) {
      const id = this.turnOrder[this.state.turnIndex];
      const player = this.room.playerById(id);
      if (player && player.connection === 'connected') return player;
      this.state.turnIndex += 1;
    }
    return null;
  }

  /** The words offered to this turn's drawer. */
  #buildChoices() {
    const settings = this.room.settings;
    const count = settings.wordMode === WORD_MODE.random ? 1 : settings.wordChoiceCount;
    try {
      return pickChoices({
        pool: poolFor(settings),
        settings,
        usedWords: this.usedWords,
        count,
        random: this.random,
      });
    } catch (error) {
      log.error(`room ${this.room.code}: word selection failed`, error);
      return [];
    }
  }

  /**
   * The drawer picked a word. Validates the caller and the index, then starts
   * the drawing phase.
   */
  selectWord(playerId, index) {
    if (this.state.phase !== PHASE.wordSelection) {
      throw new EngineError(ERROR_CODE.invalidAction, 'No word is being chosen right now.');
    }
    if (!this.isDrawer(playerId)) {
      throw new EngineError(ERROR_CODE.notDrawer, 'Only the drawer picks the word.');
    }
    const choices = this.state.wordChoices;
    if (choices.length === 0) {
      throw new EngineError(ERROR_CODE.invalidAction, 'There is nothing to choose from.');
    }
    const wanted = Number.isFinite(index) ? Math.trunc(index) : 0;
    const clamped = Math.min(choices.length - 1, Math.max(0, wanted));
    this.#commitWord(clamped);
    return true;
  }

  /** Locks in choice `index` and opens the drawing phase. */
  #commitWord(index) {
    if (this.destroyed) return;
    const chosen = this.state.wordChoices[index] ?? this.state.wordChoices[0];
    if (!chosen) {
      this.#endTurn('noWords');
      return;
    }
    this.timers.cancel(TIMER.wordSelect);

    const word = String(chosen.text);
    this.usedWords.add(word.trim().toLowerCase());

    const now = Date.now();
    this.state.phase = PHASE.drawing;
    this.state.word = word;
    this.state.wordItem = chosen;
    this.state.wordLength = word.length;
    this.state.hintIndices = [];
    this.state.maskedWord = maskWord(word, []);
    this.state.turnStartMs = now;
    this.state.turnEndMs = now + this.room.settings.drawTimeSeconds * 1000;
    this.state.correctGuesserIds = [];
    this.state.roundScores = {};
    this.state.wordChoices = [];

    this.eligibleGuessers = new Set(
      this.room.connectedPlayers().filter((player) => player.id !== this.state.drawerId).map((player) => player.id),
    );

    this.room.clearBoard();
    this.room.broadcast(SERVER_DRAW_CLEAR, {});
    this.room.broadcastPerRecipient(SERVER_GAME_ROUND_START, (playerId) => ({ game: this.stateFor(playerId) }));
    this.broadcastState();
    this.room.broadcastState();

    this.#scheduleHints();
    const drawMs = this.state.turnEndMs - now + config.timing.turnGraceMs;
    this.timers.set(TIMER.turnEnd, () => this.#endTurn('timeUp'), drawMs);
    log.debug(`room ${this.room.code}: drawing started, ${this.room.settings.drawTimeSeconds}s`);
  }

  /**
   * Spreads `settings.hintCount` reveals evenly across the turn, between
   * `firstHintAtFraction` and `lastHintAtFraction` of the clock.
   */
  #scheduleHints() {
    const total = this.room.settings.hintCount;
    if (total <= 0) return;
    const drawMs = this.room.settings.drawTimeSeconds * 1000;
    const first = config.timing.firstHintAtFraction;
    const last = Math.max(first, config.timing.lastHintAtFraction);
    for (let hintNumber = 1; hintNumber <= total; hintNumber++) {
      const fraction = total === 1 ? first : first + ((last - first) * (hintNumber - 1)) / (total - 1);
      this.timers.set(
        `${TIMER.hintPrefix}${hintNumber}`,
        () => this.#revealHint(hintNumber, total),
        Math.round(drawMs * fraction),
      );
    }
  }

  /** Reveals the letters of hint number `hintNumber`. */
  #revealHint(hintNumber, totalHints) {
    if (this.destroyed || this.state.phase !== PHASE.drawing || !this.state.word) return;
    const indices = nextHintIndices({
      word: this.state.word,
      current: this.state.hintIndices,
      totalHints,
      hintNumber,
      random: this.random,
    });
    if (indices.length === this.state.hintIndices.length) return;
    this.state.hintIndices = indices;
    this.state.maskedWord = maskWord(this.state.word, indices);
    // Cumulative indices plus the new mask - the mask never spells the word,
    // because cells are joined with spaces.
    this.room.broadcast(SERVER_GAME_HINT, {
      hintIndices: [...indices],
      maskedWord: this.state.maskedWord,
    });
    this.room.pushChat({ text: 'A letter was revealed.', type: CHAT_TYPE.hint });
    this.broadcastState();
  }

  // -------------------------------------------------------------------------
  // Guessing
  // -------------------------------------------------------------------------

  /** Players who may still guess this turn. */
  #remainingGuessers() {
    if (this.state.phase !== PHASE.drawing) return [];
    return this.room
      .connectedPlayers()
      .filter((player) => player.id !== this.state.drawerId && !player.hasGuessed);
  }

  /**
   * Handles one chat line, which doubles as a guess while a turn is drawn.
   *
   * @returns {{action: 'chat'|'guess'|'correct'|'close'|'dropped'}}
   */
  handleChat(player, text) {
    const room = this.room;
    if (player.isMuted) return { action: 'dropped' };

    const drawing = this.state.phase === PHASE.drawing && Boolean(this.state.word);
    const isDrawer = this.isDrawer(player.id);

    if (!drawing) {
      room.pushChat({ senderId: player.id, senderName: player.name, text, type: CHAT_TYPE.chat });
      return { action: 'chat' };
    }

    if (isDrawer || player.hasGuessed) {
      // People who already know the word may chat, but never spoil it.
      if (this.#wouldSpoil(text)) {
        room.sendChatTo(player.id, { text: 'No spoilers, please!', type: CHAT_TYPE.system });
        return { action: 'dropped' };
      }
      room.pushChat({ senderId: player.id, senderName: player.name, text, type: CHAT_TYPE.chat });
      return { action: 'chat' };
    }

    const verdict = evaluate(text, this.state.word);
    if (verdict === VERDICT.correct) {
      this.#awardGuess(player);
      return { action: 'correct' };
    }
    if (verdict === VERDICT.close) {
      // Only this player learns they were close; the guess is never broadcast.
      room.sendChatTo(player.id, { text: "You're close!", type: CHAT_TYPE.closeGuess });
      return { action: 'close' };
    }
    room.pushChat({ senderId: player.id, senderName: player.name, text, type: CHAT_TYPE.guess });
    return { action: 'guess' };
  }

  /** Whether a message from someone who knows the word would give it away. */
  #wouldSpoil(text) {
    if (!this.state.word) return false;
    if (evaluate(text, this.state.word) !== VERDICT.wrong) return true;
    const word = normalize(this.state.word);
    return word.length > 0 && normalize(text).includes(word);
  }

  /** Scores a correct guess and, when everybody has answered, ends the turn. */
  #awardGuess(player) {
    const settings = this.room.settings;
    const msRemaining = Math.max(0, this.state.turnEndMs - Date.now());
    const msTotal = settings.drawTimeSeconds * 1000;
    const guessOrder = this.state.correctGuesserIds.length + 1;
    const points = scoring.guesserPoints({
      msRemaining,
      msTotal,
      guessOrder,
      difficulty: this.state.wordItem?.difficulty ?? 'medium',
    });

    player.hasGuessed = true;
    player.guessOrder = guessOrder;
    player.roundScore = points;
    player.score += points;
    this.state.correctGuesserIds.push(player.id);
    this.state.roundScores[player.id] = points;

    // The word is deliberately absent from this line: it is broadcast to the
    // whole room, including players who have not guessed yet.
    this.room.pushChat({
      senderId: player.id,
      senderName: player.name,
      text: `${player.name} guessed the word!`,
      type: CHAT_TYPE.correctGuess,
    });
    this.room.broadcastState();
    this.broadcastState();

    if (this.#remainingGuessers().length === 0) {
      this.#endTurn('allGuessed');
    }
  }

  // -------------------------------------------------------------------------
  // Ending a turn, a round and the game
  // -------------------------------------------------------------------------

  /** Closes the turn, scores the drawer and shows the result. */
  #endTurn(reason) {
    if (this.destroyed) return;
    if (this.state.phase !== PHASE.drawing && this.state.phase !== PHASE.wordSelection) return;
    this.timers.cancel(TIMER.turnEnd);
    this.timers.cancel(TIMER.wordSelect);
    this.timers.cancelPrefix(TIMER.hintPrefix);

    const drawer = this.state.drawerId ? this.room.playerById(this.state.drawerId) : null;
    const word = this.state.word ?? '';
    const correctGuessers = this.state.correctGuesserIds.length;
    const eligible = new Set(this.eligibleGuessers);
    for (const id of this.state.correctGuesserIds) eligible.add(id);
    const totalGuessers = Math.max(eligible.size, correctGuessers);

    if (drawer && word) {
      const points = scoring.drawerPoints({
        correctGuessers,
        totalGuessers,
        difficulty: this.state.wordItem?.difficulty ?? 'medium',
      });
      drawer.roundScore = points;
      drawer.score += points;
      this.state.roundScores[drawer.id] = points;
    }

    // Reveal the word to everybody: `roundEnd` flips the serializer's gate.
    this.state.phase = PHASE.roundEnd;
    this.state.maskedWord = word ? maskWord(word, [...Array(word.length).keys()]) : '';
    for (const player of this.room.players.values()) player.isDrawing = false;

    const totals = {};
    for (const player of this.room.orderedPlayers()) totals[player.id] = player.score;
    const result = roundResultJson({
      round: this.state.currentRound,
      word,
      drawerId: this.state.drawerId ?? '',
      scoreDeltas: { ...this.state.roundScores },
      totals,
      correctOrder: [...this.state.correctGuesserIds],
    });

    this.room.broadcastPerRecipient(SERVER_GAME_ROUND_END, (playerId) => ({
      result,
      game: this.stateFor(playerId),
    }));
    this.room.broadcastState();
    if (word) this.room.systemMessage(`The word was "${word}".`);
    log.debug(`room ${this.room.code}: turn ended (${reason}), ${correctGuessers}/${totalGuessers} guessed`);

    this.timers.set(TIMER.roundEnd, () => this.#advance(), config.timing.roundEndMs);
  }

  /** Moves to the next seat, the next round, or the end of the game. */
  #advance() {
    if (this.destroyed) return;
    if (this.room.connectedPlayers().length < config.limits.minPlayersToStart) {
      this.#abort('Not enough players left to continue.');
      return;
    }
    if (this.state.turnIndex + 1 < this.turnOrder.length) {
      this.state.turnIndex += 1;
      this.#beginTurn();
      return;
    }
    if (this.state.currentRound < this.state.totalRounds) {
      this.#beginRound(this.state.currentRound + 1);
      return;
    }
    this.#endGame();
  }

  /** Publishes the final standings and hands the room back to the lobby. */
  #endGame() {
    if (this.destroyed) return;
    this.timers.clearAll();
    this.state.phase = PHASE.gameEnd;
    this.state.drawerId = null;
    this.state.wordChoices = [];
    for (const player of this.room.players.values()) {
      player.isDrawing = false;
      player.isReady = false;
      player.hasGuessed = false;
      player.guessOrder = null;
    }

    const result = gameResultJson({
      roomCode: this.room.code,
      standings: standingsFrom(this.room.orderedPlayers()),
      totalRounds: this.state.totalRounds,
    });
    this.room.broadcast(SERVER_GAME_END, { result });

    // The room is immediately joinable and playable again: `c:game:playAgain`
    // only needs the host, because every ready flag has just been cleared.
    this.room.status = ROOM_STATUS.waiting;
    this.room.broadcastState();
    this.broadcastState();
    const winner = result.standings[0];
    if (winner) this.room.systemMessage(`${winner.name} wins with ${winner.score} points!`);
    log.info(`room ${this.room.code}: game over`);

    this.timers.set(TIMER.gameEnd, () => this.#resetToLobby(), config.timing.gameEndMs);
  }

  /** Drops back to a clean lobby once the results have been on screen. */
  #resetToLobby() {
    if (this.destroyed || this.state.phase !== PHASE.gameEnd) return;
    this.state = lobbyState(this.room.code);
    this.usedWords.clear();
    this.turnOrder = [];
    this.eligibleGuessers = new Set();
    for (const player of this.room.players.values()) {
      player.score = 0;
      player.roundScore = 0;
    }
    this.room.status = ROOM_STATUS.waiting;
    this.room.clearBoard();
    this.room.broadcast(SERVER_DRAW_CLEAR, {});
    this.room.broadcastState();
    this.broadcastState();
  }

  /** Ends a game that can no longer be played. */
  #abort(reason) {
    if (!this.isActive()) return;
    this.timers.clearAll();
    this.room.systemMessage(reason);
    this.#endGame();
  }

  // -------------------------------------------------------------------------
  // Membership changes
  // -------------------------------------------------------------------------

  /** A player's socket dropped; the seat is held during the grace window. */
  onPlayerDisconnected(playerId) {
    if (!this.isActive()) return;
    if (this.state.phase === PHASE.drawing && !this.isDrawer(playerId)) {
      if (this.#remainingGuessers().length === 0) this.#endTurn('allGuessed');
    }
  }

  /** A player came back inside the grace window. */
  onPlayerReconnected(playerId) {
    this.sendStateTo(playerId);
  }

  /** A player left for good (leave, kick, ban or an expired grace window). */
  onPlayerGone(playerId) {
    if (!this.isActive()) return;
    this.eligibleGuessers.delete(playerId);
    if (this.room.connectedPlayers().length < config.limits.minPlayersToStart) {
      this.#abort('Not enough players left to continue.');
      return;
    }
    if (this.isDrawer(playerId)) {
      this.#endTurn('drawerLeft');
      return;
    }
    if (this.state.phase === PHASE.drawing && this.#remainingGuessers().length === 0) {
      this.#endTurn('allGuessed');
    }
  }

  /** Cancels every timer this engine owns. */
  destroy() {
    this.destroyed = true;
    this.timers.clearAll();
  }
}

/** Builds a fresh, never-started game state for a room. Exposed for tests. */
export function initialGameState(roomCode) {
  return lobbyState(roomCode);
}

/** A stable id for a chat row the engine itself emits. Exposed for tests. */
export function engineMessageId() {
  return newId();
}

export default GameEngine;
