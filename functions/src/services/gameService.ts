import { FieldValue, Timestamp, Transaction } from 'firebase-admin/firestore';

import { LIMITS, TIMING } from '../config/constants';
import {
  PlayerDoc,
  RoomDoc,
  RoundResultDoc,
  RoundSecretDoc,
  ScoreAward,
  WordChoice,
} from '../models/types';
import { logger, redactWord } from '../utils/logger';
import { shuffled } from '../utils/random';
import { failPrecondition } from '../utils/validation';
import {
  db,
  playerRef,
  readPlayer,
  readRoom,
  roomRef,
  roundRef,
  secretRef,
  systemMessage,
  writeMessage,
} from './roomService';
import { scheduleTick } from './schedulerService';
import { scoring } from './scoringService';
import {
  evaluateGuess,
  hintDueAtMs,
  letterCount,
  maskWord,
  nextHintIndices,
  pickWordChoices,
} from './wordService';

/**
 * The authoritative game engine (sections 14-40).
 *
 * Every transition below runs inside a Firestore transaction and is written to
 * be idempotent, because the same transition can legitimately be triggered
 * from three directions at once: a player's action, the scheduled tick for the
 * deadline, and the one-minute sweep. Guarding on `turnIndex` and
 * `roundStatus` inside the transaction is what makes a double-fire a no-op
 * instead of a double score.
 */

/** How many turns a whole game runs for: every player draws once per round. */
export function totalTurns(room: RoomDoc): number {
  return room.settings.rounds * Math.max(1, room.game.drawOrder.length);
}

/** The 1-based round a turn belongs to. */
export function roundForTurn(turnIndex: number, playerCount: number): number {
  return Math.floor(turnIndex / Math.max(1, playerCount)) + 1;
}

// ---------------------------------------------------------------------------
// Starting a game (section 15)
// ---------------------------------------------------------------------------

/**
 * Starts a match.
 *
 * The draw order is shuffled once, here, and then never changes: that is what
 * makes the rotation predictable for players ("you're after Rahul") while
 * keeping it out of the client's hands entirely (section 16).
 */
export async function startGame(roomId: string, uid: string): Promise<void> {
  const startedAt = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (room.ownerId !== uid) {
      failPrecondition('notHost', 'Only the room owner can start the game.');
    }
    if (room.status !== 'waiting' && room.status !== 'finished') {
      failPrecondition('gameInProgress', 'The game has already started.');
    }

    const players = await readPlayers(tx, roomId);
    if (players.length < LIMITS.minPlayersToStart) {
      failPrecondition(
        'invalidAction',
        `At least ${LIMITS.minPlayersToStart} players are needed to start.`
      );
    }

    const drawOrder = shuffled(players.map((p) => p.userId));

    // Wipe the slate: a restart reuses the same room and players, so last
    // game's scores and guessed-flags have to go (section 40).
    for (const player of players) {
      tx.update(playerRef(roomId, player.userId), {
        score: 0,
        roundScore: 0,
        correctGuesses: 0,
        hasGuessedCorrectly: false,
        isReady: false,
      });
    }

    tx.update(roomRef(roomId), {
      status: 'starting',
      'game.drawOrder': drawOrder,
      'game.totalRounds': room.settings.rounds,
      'game.currentRound': 0,
      'game.turnIndex': -1,
      'game.roundStatus': 'starting',
      'game.revealedWord': null,
      'game.correctOrder': [],
      updatedAt: FieldValue.serverTimestamp(),
    });

    systemMessage(tx, roomId, 'The game is starting!');
    return Date.now();
  });

  // A short countdown so players can see the lobby resolve into the game.
  await scheduleTick(
    { roomId, turnIndex: -1, kind: 'next' },
    startedAt + TIMING.startCountdownMs
  );
  logger.info('game.started', { roomId });
}

// ---------------------------------------------------------------------------
// Turn setup (sections 16-19)
// ---------------------------------------------------------------------------

/**
 * Opens the next turn, or ends the game when the rotation is exhausted.
 *
 * Word choices are written to `secret/{turnIndex}`, which no client can read;
 * the drawer receives them as the return value of their own callable instead
 * (section 18).
 */
export async function beginNextTurn(roomId: string): Promise<void> {
  const outcome = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (room.status === 'closed' || room.status === 'finished') {
      return { kind: 'noop' as const };
    }

    const players = await readPlayers(tx, roomId);
    if (players.length < LIMITS.minPlayersToStart) {
      // Everyone but one player left mid-game; there is nothing to play.
      return { kind: 'finish' as const, room, players };
    }

    // Skip over anyone who has since left the room.
    const order = room.game.drawOrder.filter((id) =>
      players.some((p) => p.userId === id)
    );
    if (order.length === 0) {
      return { kind: 'finish' as const, room, players };
    }

    const nextTurn = room.game.turnIndex + 1;
    const limit = room.settings.rounds * order.length;
    if (nextTurn >= limit) {
      return { kind: 'finish' as const, room, players };
    }

    const drawerId = order[nextTurn % order.length];
    const drawer = players.find((p) => p.userId === drawerId);
    if (!drawer) {
      return { kind: 'finish' as const, room, players };
    }

    return {
      kind: 'begin' as const,
      room,
      players,
      order,
      nextTurn,
      drawerId,
      drawerName: drawer.displayName,
    };
  });

  if (outcome.kind === 'noop') return;

  if (outcome.kind === 'finish') {
    await finishGame(roomId);
    return;
  }

  // Word selection reads the word bank, which cannot happen inside the
  // transaction above (a Firestore transaction may not run a query after a
  // write, and the bank is large). Picking first, then committing, is safe:
  // the commit re-checks the turn index it is claiming.
  const usedWords = await recentWords(roomId);
  const choices = await pickWordChoices({
    count: outcome.room.settings.wordsToChoose,
    language: outcome.room.settings.language,
    categories: outcome.room.settings.categories,
    exclude: usedWords,
  });

  const now = Date.now();
  const selectDeadline = now + outcome.room.settings.wordSelectSeconds * 1000;

  await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    // Somebody else already opened this turn.
    if (room.game.turnIndex >= outcome.nextTurn) return;

    const secret: RoundSecretDoc = {
      roundNumber: roundForTurn(outcome.nextTurn, outcome.order.length),
      turnIndex: outcome.nextTurn,
      drawerId: outcome.drawerId,
      choices,
      word: null,
      aliases: [],
      difficulty: 'medium',
      revealedIndices: [],
    };
    tx.set(secretRef(roomId, outcome.nextTurn), secret);

    // Everyone starts each turn not having guessed.
    for (const player of outcome.players) {
      tx.update(playerRef(roomId, player.userId), {
        hasGuessedCorrectly: false,
        roundScore: 0,
      });
    }

    tx.update(roomRef(roomId), {
      status: 'playing',
      'game.turnIndex': outcome.nextTurn,
      'game.currentRound': roundForTurn(outcome.nextTurn, outcome.order.length),
      'game.currentDrawerId': outcome.drawerId,
      'game.roundStatus': 'word_selection',
      'game.roundStartedAt': Timestamp.fromMillis(now),
      'game.roundEndsAt': Timestamp.fromMillis(selectDeadline),
      'game.maskedWord': '',
      'game.wordLength': 0,
      'game.hintsRevealed': 0,
      'game.revealedWord': null,
      'game.correctOrder': [],
      updatedAt: FieldValue.serverTimestamp(),
    });

    systemMessage(tx, roomId, `${outcome.drawerName} is choosing a word...`);
  });

  // If the drawer dithers, the turn ends itself rather than hanging.
  await scheduleTick(
    { roomId, turnIndex: outcome.nextTurn, kind: 'end' },
    selectDeadline + TIMING.turnGraceMs
  );

  logger.info('turn.begun', {
    roomId,
    turnIndex: outcome.nextTurn,
    drawerId: outcome.drawerId,
  });
}

/**
 * Records the drawer's choice and starts the drawing phase (section 19).
 *
 * Returns the chosen word so the drawer's own client can display it; it is
 * never written anywhere a guesser can read.
 */
export async function selectWord(
  roomId: string,
  uid: string,
  choiceIndex: number
): Promise<{ word: string; endsAtMs: number }> {
  const result = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (room.game.currentDrawerId !== uid) {
      failPrecondition('notDrawer', 'Only the drawer can choose the word.');
    }
    if (room.game.roundStatus !== 'word_selection') {
      failPrecondition('invalidAction', 'The word has already been chosen.');
    }

    const turnIndex = room.game.turnIndex;
    const snapshot = await tx.get(secretRef(roomId, turnIndex));
    if (!snapshot.exists) {
      failPrecondition('serverError', 'This round is no longer available.');
    }
    const secret = snapshot.data() as RoundSecretDoc;
    if (secret.word !== null) {
      failPrecondition('invalidAction', 'The word has already been chosen.');
    }

    const choice: WordChoice | undefined = secret.choices[choiceIndex];
    if (!choice) {
      failPrecondition('validation', 'That is not one of the offered words.');
    }

    const now = Date.now();
    const endsAt = now + room.settings.drawTimeSeconds * 1000;

    tx.update(secretRef(roomId, turnIndex), {
      word: choice.word,
      aliases: choice.aliases,
      difficulty: choice.difficulty,
      revealedIndices: [],
    });

    tx.update(roomRef(roomId), {
      'game.roundStatus': 'drawing',
      'game.roundStartedAt': Timestamp.fromMillis(now),
      'game.roundEndsAt': Timestamp.fromMillis(endsAt),
      'game.maskedWord': maskWord(choice.word, []),
      'game.wordLength': letterCount(choice.word),
      'game.hintsRevealed': 0,
      updatedAt: FieldValue.serverTimestamp(),
    });

    systemMessage(tx, roomId, 'Word chosen. Start guessing!');

    return { word: choice.word, endsAtMs: endsAt, turnIndex, room };
  });

  await scheduleNextMoment(roomId, result.turnIndex, result.room, {
    startedAtMs: result.endsAtMs - result.room.settings.drawTimeSeconds * 1000,
    endsAtMs: result.endsAtMs,
    hintsRevealed: 0,
  });

  logger.info('turn.wordSelected', {
    roomId,
    turnIndex: result.turnIndex,
    word: redactWord(result.word),
  });

  return { word: result.word, endsAtMs: result.endsAtMs };
}

// ---------------------------------------------------------------------------
// Guessing (sections 25-27)
// ---------------------------------------------------------------------------

export interface GuessOutcome {
  verdict: 'correct' | 'close' | 'wrong';
  points: number;
  /** True when this guess was the one that ended the round. */
  roundOver: boolean;
}

/**
 * Grades a guess and awards points, all server-side.
 *
 * The transaction is what makes two simultaneous correct guesses safe: both
 * read the same `correctOrder`, but only one commits, and the loser retries
 * against the updated list and takes second place (section 55).
 */
export async function submitGuess(
  roomId: string,
  uid: string,
  text: string
): Promise<GuessOutcome> {
  const outcome = await db().runTransaction<GuessOutcome & { turnIndex: number }>(
    async (tx) => {
      const room = await readRoom(tx, roomId);
      if (room.game.roundStatus !== 'drawing') {
        failPrecondition('invalidAction', 'There is no round to guess in.');
      }
      if (room.game.currentDrawerId === uid) {
        failPrecondition('invalidAction', 'The drawer cannot guess.');
      }

      const player = await readPlayer(tx, roomId, uid);
      if (!player) {
        failPrecondition('invalidAction', 'You are not in this room.');
      }
      if (player.isMuted) {
        failPrecondition('invalidAction', 'You have been muted.');
      }
      if (player.hasGuessedCorrectly) {
        failPrecondition('invalidAction', 'You already guessed the word.');
      }

      const turnIndex = room.game.turnIndex;
      const secretSnap = await tx.get(secretRef(roomId, turnIndex));
      if (!secretSnap.exists) {
        failPrecondition('serverError', 'This round is no longer available.');
      }
      const secret = secretSnap.data() as RoundSecretDoc;
      if (!secret.word) {
        failPrecondition('invalidAction', 'The drawer has not chosen yet.');
      }

      const verdict = evaluateGuess(text, secret.word, secret.aliases);

      // A wrong guess is public chat; a close one is a private nudge. Neither
      // reveals anything, so both are cheap.
      if (verdict === 'wrong') {
        writeMessage(tx, roomId, {
          userId: uid,
          displayName: player.displayName,
          message: text,
          type: 'guess',
        });
        return { verdict, points: 0, roundOver: false, turnIndex };
      }

      if (verdict === 'close') {
        return { verdict, points: 0, roundOver: false, turnIndex };
      }

      // Correct. Work out the award from server time only (section 29).
      const endsAt = room.game.roundEndsAt?.toMillis() ?? 0;
      const startedAt = room.game.roundStartedAt?.toMillis() ?? 0;
      const now = Date.now();
      const msRemaining = Math.max(0, endsAt - now);
      const msTotal = Math.max(1, endsAt - startedAt);

      const order = [...room.game.correctOrder];
      if (order.includes(uid)) {
        failPrecondition('invalidAction', 'You already guessed the word.');
      }
      order.push(uid);

      const points = scoring.guesserPoints({
        msRemaining,
        msTotal,
        guessOrder: order.length,
        difficulty: secret.difficulty,
      });

      tx.update(playerRef(roomId, uid), {
        hasGuessedCorrectly: true,
        score: FieldValue.increment(points),
        roundScore: FieldValue.increment(points),
        correctGuesses: FieldValue.increment(1),
      });

      tx.update(roomRef(roomId), {
        'game.correctOrder': order,
        updatedAt: FieldValue.serverTimestamp(),
      });

      writeMessage(tx, roomId, {
        userId: uid,
        displayName: player.displayName,
        message: `${player.displayName} guessed the word!`,
        type: 'correct',
      });

      // The round is over the moment nobody is left to guess.
      const players = await readPlayers(tx, roomId);
      const guessers = players.filter(
        (p) => p.userId !== room.game.currentDrawerId
      );
      const roundOver = order.length >= guessers.length;

      return { verdict, points, roundOver, turnIndex };
    }
  );

  if (outcome.roundOver) {
    await endTurn(roomId, outcome.turnIndex, 'all_guessed');
  }

  return {
    verdict: outcome.verdict,
    points: outcome.points,
    roundOver: outcome.roundOver,
  };
}

// ---------------------------------------------------------------------------
// Hints (section 30)
// ---------------------------------------------------------------------------

/** Reveals any hints that have come due, and schedules the next moment. */
export async function applyDueHints(
  roomId: string,
  turnIndex: number
): Promise<void> {
  const state = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (room.game.turnIndex !== turnIndex) return null;
    if (room.game.roundStatus !== 'drawing') return null;
    if (room.settings.hintCount <= 0) return null;

    const snapshot = await tx.get(secretRef(roomId, turnIndex));
    if (!snapshot.exists) return null;
    const secret = snapshot.data() as RoundSecretDoc;
    if (!secret.word) return null;

    const startedAt = room.game.roundStartedAt?.toMillis() ?? 0;
    const endsAt = room.game.roundEndsAt?.toMillis() ?? 0;
    const turnMs = Math.max(1, endsAt - startedAt);
    const elapsed = Date.now() - startedAt;

    // How many hints *should* have landed by now.
    let due = 0;
    for (let n = 1; n <= room.settings.hintCount; n++) {
      const at = hintDueAtMs(
        n,
        room.settings.hintCount,
        turnMs,
        TIMING.firstHintAtFraction,
        TIMING.lastHintAtFraction
      );
      if (elapsed >= at) due = n;
    }
    if (due <= room.game.hintsRevealed) {
      return { room, startedAt, turnMs, revealed: room.game.hintsRevealed };
    }

    const indices = nextHintIndices({
      word: secret.word,
      current: secret.revealedIndices,
      totalHints: room.settings.hintCount,
      hintNumber: due,
    });

    tx.update(secretRef(roomId, turnIndex), { revealedIndices: indices });
    tx.update(roomRef(roomId), {
      'game.maskedWord': maskWord(secret.word, indices),
      'game.hintsRevealed': due,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { room, startedAt, turnMs, revealed: due };
  });

  if (!state) return;

  await scheduleNextMoment(roomId, turnIndex, state.room, {
    startedAtMs: state.startedAt,
    endsAtMs: state.startedAt + state.turnMs,
    hintsRevealed: state.revealed,
  });
}

/**
 * Books the next wake-up for a live turn: the next hint, or the deadline.
 *
 * Scheduling only the *next* moment rather than every moment up front keeps
 * the queue small and means a round that ends early leaves at most one stale
 * task behind, which the turn-index guard discards.
 */
async function scheduleNextMoment(
  roomId: string,
  turnIndex: number,
  room: RoomDoc,
  turn: { startedAtMs: number; endsAtMs: number; hintsRevealed: number }
): Promise<void> {
  const turnMs = Math.max(1, turn.endsAtMs - turn.startedAtMs);
  const nextHint = turn.hintsRevealed + 1;

  if (room.settings.hintCount >= nextHint) {
    const at =
      turn.startedAtMs +
      hintDueAtMs(
        nextHint,
        room.settings.hintCount,
        turnMs,
        TIMING.firstHintAtFraction,
        TIMING.lastHintAtFraction
      );
    if (at < turn.endsAtMs) {
      await scheduleTick({ roomId, turnIndex, kind: 'hint' }, at);
      return;
    }
  }

  await scheduleTick(
    { roomId, turnIndex, kind: 'end' },
    turn.endsAtMs + TIMING.turnGraceMs
  );
}

// ---------------------------------------------------------------------------
// Ending a turn (sections 37-38)
// ---------------------------------------------------------------------------

/**
 * Closes a turn, scores the drawer, reveals the answer and records the round.
 *
 * Guarded on both `turnIndex` and `roundStatus`, so calling it twice - which
 * happens routinely, when the last guess and the deadline coincide - scores
 * exactly once.
 */
export async function endTurn(
  roomId: string,
  turnIndex: number,
  reason: RoundResultDoc['endReason']
): Promise<void> {
  const ended = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (room.game.turnIndex !== turnIndex) return false;
    if (
      room.game.roundStatus !== 'drawing' &&
      room.game.roundStatus !== 'word_selection'
    ) {
      return false;
    }

    const players = await readPlayers(tx, roomId);
    const snapshot = await tx.get(secretRef(roomId, turnIndex));
    const secret = snapshot.exists
      ? (snapshot.data() as RoundSecretDoc)
      : null;

    const drawerId = room.game.currentDrawerId;
    const drawer = players.find((p) => p.userId === drawerId);
    const word = secret?.word ?? null;
    const difficulty = secret?.difficulty ?? 'medium';

    const awards: ScoreAward[] = [];

    // A turn where the drawer never chose a word scores nobody.
    if (word) {
      const guessers = players.filter((p) => p.userId !== drawerId);
      const correct = room.game.correctOrder;

      for (const [i, userId] of correct.entries()) {
        const player = players.find((p) => p.userId === userId);
        if (!player) continue;
        awards.push({
          userId,
          displayName: player.displayName,
          points: player.roundScore,
          guessOrder: i + 1,
          role: 'guesser',
        });
      }

      if (drawer) {
        const drawerPoints = scoring.drawerPoints({
          correctGuessers: correct.length,
          totalGuessers: guessers.length,
          difficulty,
        });
        if (drawerPoints > 0) {
          tx.update(playerRef(roomId, drawer.userId), {
            score: FieldValue.increment(drawerPoints),
            roundScore: FieldValue.increment(drawerPoints),
          });
        }
        awards.push({
          userId: drawer.userId,
          displayName: drawer.displayName,
          points: drawerPoints,
          guessOrder: 0,
          role: 'drawer',
        });
      }
    }

    const now = Timestamp.now();
    const result: RoundResultDoc = {
      roundNumber: room.game.currentRound,
      turnIndex,
      drawerId: drawerId ?? '',
      drawerName: drawer?.displayName ?? 'Unknown',
      word: word ?? '',
      difficulty,
      startedAt: room.game.roundStartedAt ?? now,
      endedAt: now,
      endReason: word ? reason : 'skipped',
      awards,
    };
    tx.set(roundRef(roomId, turnIndex), result);

    tx.update(roomRef(roomId), {
      status: 'round_result',
      'game.roundStatus': 'round_result',
      'game.revealedWord': word,
      'game.maskedWord': word ? maskWord(word, allIndices(word)) : '',
      'game.roundEndsAt': Timestamp.fromMillis(
        Date.now() + TIMING.roundResultMs
      ),
      updatedAt: FieldValue.serverTimestamp(),
    });

    systemMessage(
      tx,
      roomId,
      word ? `The word was "${word}".` : 'No word was chosen.'
    );
    return true;
  });

  if (!ended) return;

  logger.info('turn.ended', { roomId, turnIndex, reason });
  await scheduleTick(
    { roomId, turnIndex, kind: 'next' },
    Date.now() + TIMING.roundResultMs
  );
}

/** Every index of `word`, for the full reveal. */
function allIndices(word: string): number[] {
  return Array.from({ length: word.length }, (_, i) => i);
}

// ---------------------------------------------------------------------------
// Ending a game (section 39)
// ---------------------------------------------------------------------------

/** Closes the match and publishes the final standings. */
export async function finishGame(roomId: string): Promise<void> {
  const winner = await db().runTransaction(async (tx) => {
    const room = await readRoom(tx, roomId);
    if (room.status === 'finished' || room.status === 'closed') return null;

    const players = await readPlayers(tx, roomId);
    const ranked = [...players].sort((a, b) => b.score - a.score);
    const top = ranked[0];

    tx.update(roomRef(roomId), {
      status: 'finished',
      'game.roundStatus': 'final_result',
      'game.currentDrawerId': null,
      'game.roundEndsAt': null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (top) {
      systemMessage(
        tx,
        roomId,
        `${top.displayName} wins with ${top.score} points!`
      );
    }
    return { players: ranked, winnerId: top?.userId ?? null };
  });

  if (!winner) return;

  // Lifetime aggregates are updated outside the transaction: they touch
  // documents in another collection and must never be able to fail the game's
  // own state transition.
  await updateLifetimeStats(winner.players, winner.winnerId);
  logger.info('game.finished', { roomId, winnerId: winner.winnerId });
}

/** Folds a finished game into each player's profile and the leaderboard. */
async function updateLifetimeStats(
  players: PlayerDoc[],
  winnerId: string | null
): Promise<void> {
  const batch = db().batch();
  const now = Timestamp.now();

  for (const player of players) {
    const won = player.userId === winnerId;
    batch.set(
      db().collection('users').doc(player.userId),
      {
        gamesPlayed: FieldValue.increment(1),
        gamesWon: FieldValue.increment(won ? 1 : 0),
        totalScore: FieldValue.increment(player.score),
        updatedAt: now,
      },
      { merge: true }
    );
    batch.set(
      db().collection('leaderboard').doc(player.userId),
      {
        userId: player.userId,
        displayName: player.displayName,
        avatarId: player.avatarId,
        avatarColorIndex: player.avatarColorIndex,
        totalScore: FieldValue.increment(player.score),
        gamesPlayed: FieldValue.increment(1),
        gamesWon: FieldValue.increment(won ? 1 : 0),
        updatedAt: now,
      },
      { merge: true }
    );
  }

  try {
    await batch.commit();
  } catch (error) {
    logger.error('stats.updateFailed', error, { winnerId });
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/** Every player in a room, oldest membership first. */
export async function readPlayers(
  tx: Transaction,
  roomId: string
): Promise<PlayerDoc[]> {
  const snapshot = await tx.get(
    roomRef(roomId).collection('players').orderBy('joinedAt')
  );
  return snapshot.docs.map((d) => d.data() as PlayerDoc);
}

/**
 * Words this room has already used, so a game does not repeat itself.
 *
 * Read outside a transaction; a stale entry here only risks an occasional
 * repeat, which is not worth the contention of reading it transactionally.
 */
async function recentWords(roomId: string): Promise<string[]> {
  const snapshot = await roomRef(roomId)
    .collection('rounds')
    .orderBy('turnIndex', 'desc')
    .limit(40)
    .get();
  return snapshot.docs
    .map((d) => (d.data() as RoundResultDoc).word)
    .filter((w): w is string => typeof w === 'string' && w.length > 0);
}
