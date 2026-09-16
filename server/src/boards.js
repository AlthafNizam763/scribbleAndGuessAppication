/**
 * The shared drawing board of each room, held in memory.
 *
 * Boards are deliberately *not* persisted. A stroke is only meaningful while
 * its round is being played, the round is over in under two minutes, and
 * writing thousands of points to a database to serve a picture nobody will
 * look at again would be the single most expensive thing the product does
 * (§22). If the relay restarts mid-round the board is lost, the drawer redraws,
 * and the game — whose real state lives in Firestore — carries on.
 */

import { config } from './config.js';

/** A board that has seen no traffic for this long is dropped. */
const IDLE_BOARD_MS = 10 * 60 * 1000;

/** One room's strokes, plus the undo stack. */
class Board {
  constructor() {
    /** @type {Array<object>} committed strokes, in paint order. */
    this.strokes = [];
    /** @type {Array<object>} strokes removed by undo, most recent last. */
    this.redo = [];
    /** Id of the stroke currently being appended to, if any. */
    this.liveStrokeId = null;
    this.touchedAt = Date.now();
  }

  touch() {
    this.touchedAt = Date.now();
  }

  /** Starts a stroke, respecting the per-board cap. */
  begin(stroke) {
    if (this.strokes.length >= config.limits.maxStrokesPerBoard) return false;
    this.strokes.push(stroke);
    // Any new mark invalidates the redo stack, exactly as in a drawing app.
    this.redo = [];
    this.liveStrokeId = stroke.id;
    this.touch();
    return true;
  }

  /** Appends points to the live stroke. */
  append(strokeId, points) {
    const stroke = this.strokes.find((s) => s.id === strokeId);
    if (!stroke) return false;
    if (stroke.p.length + points.length > config.limits.maxPointsPerStroke) {
      return false;
    }
    stroke.p.push(...points);
    this.touch();
    return true;
  }

  /** Closes the live stroke. */
  end(strokeId) {
    if (this.liveStrokeId === strokeId) this.liveStrokeId = null;
    this.touch();
    return true;
  }

  /** Removes the last stroke by `authorId`, pushing it onto the redo stack. */
  undo(authorId) {
    for (let i = this.strokes.length - 1; i >= 0; i--) {
      if (this.strokes[i].a !== authorId) continue;
      const [removed] = this.strokes.splice(i, 1);
      this.redo.push(removed);
      if (this.redo.length > config.limits.maxRedoStack) this.redo.shift();
      this.touch();
      return removed.id;
    }
    return null;
  }

  /** Restores the most recently undone stroke by `authorId`. */
  redoLast(authorId) {
    for (let i = this.redo.length - 1; i >= 0; i--) {
      if (this.redo[i].a !== authorId) continue;
      const [restored] = this.redo.splice(i, 1);
      this.strokes.push(restored);
      this.touch();
      return restored;
    }
    return null;
  }

  /** Empties the board. */
  clear() {
    this.strokes = [];
    this.redo = [];
    this.liveStrokeId = null;
    this.touch();
  }

  /** The whole board, for a late joiner or a reconnect (§36). */
  snapshot() {
    return { strokes: this.strokes };
  }
}

/** Every live board, keyed by room id. */
export class BoardStore {
  constructor() {
    /** @type {Map<string, Board>} */
    this.boards = new Map();
    this.reaper = setInterval(() => this.reap(), 60_000);
    // A housekeeping timer must never hold the process open.
    if (typeof this.reaper.unref === 'function') this.reaper.unref();
  }

  /** The board for `roomId`, created on first use. */
  get(roomId) {
    let board = this.boards.get(roomId);
    if (!board) {
      board = new Board();
      this.boards.set(roomId, board);
    }
    return board;
  }

  /** Forgets a room's board. */
  drop(roomId) {
    this.boards.delete(roomId);
  }

  /** Drops boards nobody has touched in a while. */
  reap() {
    const cutoff = Date.now() - IDLE_BOARD_MS;
    for (const [roomId, board] of this.boards) {
      if (board.touchedAt < cutoff) this.boards.delete(roomId);
    }
  }

  dispose() {
    clearInterval(this.reaper);
    this.boards.clear();
  }
}
