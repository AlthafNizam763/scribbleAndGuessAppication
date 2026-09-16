import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { BoardStore } from '../src/boards.js';
import { config } from '../src/config.js';
import { TokenBucket } from '../src/rateLimit.js';

/**
 * Tests for the drawing relay's own state.
 *
 * The game rules are no longer this process's business — they live in
 * `functions/` now. What is left here is the board: stroke order, undo/redo
 * ownership, the caps that stop one client exhausting memory, and the rate
 * bucket that stops it flooding the room.
 */

const stroke = (id, author = 'alice') => ({
  id,
  a: author,
  p: [[0.1, 0.1]],
  c: 0xff000000,
  w: 4,
  t: 'pen',
  ts: 0,
});

describe('board: strokes', () => {
  it('keeps strokes in paint order', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a'));
    board.begin(stroke('b'));
    assert.deepEqual(board.strokes.map((s) => s.id), ['a', 'b']);
  });

  it('appends points to a live stroke', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a'));
    assert.ok(board.append('a', [[0.2, 0.2], [0.3, 0.3]]));
    assert.equal(board.strokes[0].p.length, 3);
  });

  it('ignores appends to a stroke that does not exist', () => {
    const board = new BoardStore().get('room');
    assert.equal(board.append('ghost', [[0.5, 0.5]]), false);
  });

  it('refuses to grow a stroke past the cap', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a'));
    const huge = Array.from({ length: config.limits.maxPointsPerStroke }, () => [0.5, 0.5]);
    assert.equal(board.append('a', huge), false);
  });

  it('caps the number of strokes on a board', () => {
    const board = new BoardStore().get('room');
    for (let i = 0; i < config.limits.maxStrokesPerBoard; i++) {
      assert.ok(board.begin(stroke(`s${i}`)));
    }
    assert.equal(board.begin(stroke('one-too-many')), false);
  });
});

describe('board: undo and redo', () => {
  it('undoes the drawer own last stroke', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a'));
    board.begin(stroke('b'));
    assert.equal(board.undo('alice'), 'b');
    assert.deepEqual(board.strokes.map((s) => s.id), ['a']);
  });

  it('never undoes somebody else stroke', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a', 'alice'));
    // A different drawer took over; alice's undo must not reach into it.
    assert.equal(board.undo('bob'), null);
    assert.equal(board.strokes.length, 1);
  });

  it('restores an undone stroke', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a'));
    board.undo('alice');
    const restored = board.redoLast('alice');
    assert.equal(restored.id, 'a');
    assert.equal(board.strokes.length, 1);
  });

  it('drops the redo stack once a new stroke lands', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a'));
    board.undo('alice');
    board.begin(stroke('b'));
    assert.equal(board.redo.length, 0);
    assert.equal(board.redoLast('alice'), null);
  });

  it('returns null when there is nothing to undo', () => {
    const board = new BoardStore().get('room');
    assert.equal(board.undo('alice'), null);
  });
});

describe('board: clear and snapshot', () => {
  it('empties everything on clear', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a'));
    board.undo('alice');
    board.clear();
    assert.equal(board.strokes.length, 0);
    assert.equal(board.redo.length, 0);
    assert.equal(board.liveStrokeId, null);
  });

  it('hands a late joiner the whole board', () => {
    const board = new BoardStore().get('room');
    board.begin(stroke('a'));
    board.begin(stroke('b'));
    assert.equal(board.snapshot().strokes.length, 2);
  });
});

describe('board store', () => {
  it('gives each room its own board', () => {
    const store = new BoardStore();
    store.get('one').begin(stroke('a'));
    assert.equal(store.get('two').strokes.length, 0);
    store.dispose();
  });

  it('reaps boards nobody has touched', () => {
    const store = new BoardStore();
    const board = store.get('stale');
    board.touchedAt = Date.now() - 60 * 60 * 1000;
    store.reap();
    assert.equal(store.boards.has('stale'), false);
    store.dispose();
  });
});

describe('rate limiting', () => {
  it('allows a burst up to capacity, then refuses', () => {
    let now = 0;
    const bucket = new TokenBucket({
      capacity: 3,
      refillPerSec: 1,
      now: () => now,
    });
    assert.ok(bucket.take());
    assert.ok(bucket.take());
    assert.ok(bucket.take());
    assert.equal(bucket.take(), false);
  });

  it('refills over time', () => {
    let now = 0;
    const bucket = new TokenBucket({
      capacity: 2,
      refillPerSec: 1,
      now: () => now,
    });
    bucket.take();
    bucket.take();
    assert.equal(bucket.take(), false);
    now += 1000;
    assert.ok(bucket.take());
  });
});
