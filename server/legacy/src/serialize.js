/**
 * The only place that turns server state into wire JSON.
 *
 * Every function here produces exactly the shape the matching Dart model in
 * lib/models/ parses - same key names, same enum `.name` strings, same compact
 * stroke keys (id/a/p/c/w/t/ts).
 *
 * SECURITY: `gameStateJson` is the single choke point for the secret word. It
 * takes the recipient's player id and decides for itself whether `word` may be
 * included, so no caller can leak the word by forgetting a flag.
 */

import { CHAT_TYPE, CONNECTION, DRAW_TOOL, ERROR_CODE, PHASE, ROOM_STATUS, WORD_MODE } from './protocol.js';
import { DEFAULT_SETTINGS } from './config.js';

/** Coerces to a plain string. */
function str(value, fallback = '') {
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return fallback;
}

/** Coerces to a finite integer. */
function int(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : fallback;
}

/** Coerces to a finite double. */
function dbl(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

/** Coerces to a boolean. */
function bool(value, fallback = false) {
  return typeof value === 'boolean' ? value : fallback;
}

/** Serializes a player. Mirrors `Player.toJson`. */
export function playerJson(player) {
  return {
    id: str(player?.id),
    name: str(player?.name),
    avatarId: int(player?.avatarId),
    avatarColorIndex: int(player?.avatarColorIndex),
    score: int(player?.score),
    roundScore: int(player?.roundScore),
    isHost: bool(player?.isHost),
    isReady: bool(player?.isReady),
    isDrawing: bool(player?.isDrawing),
    hasGuessed: bool(player?.hasGuessed),
    guessOrder: player?.guessOrder === null || player?.guessOrder === undefined ? null : int(player.guessOrder),
    isMuted: bool(player?.isMuted),
    connection: CONNECTION[player?.connection] ?? CONNECTION.connected,
  };
}

/** Serializes room settings. Mirrors `RoomSettings.toJson`. */
export function settingsJson(settings) {
  const source = settings ?? DEFAULT_SETTINGS;
  return {
    maxPlayers: int(source.maxPlayers, DEFAULT_SETTINGS.maxPlayers),
    rounds: int(source.rounds, DEFAULT_SETTINGS.rounds),
    drawTimeSeconds: int(source.drawTimeSeconds, DEFAULT_SETTINGS.drawTimeSeconds),
    wordChoiceCount: int(source.wordChoiceCount, DEFAULT_SETTINGS.wordChoiceCount),
    hintCount: int(source.hintCount, DEFAULT_SETTINGS.hintCount),
    wordSelectSeconds: int(source.wordSelectSeconds, DEFAULT_SETTINGS.wordSelectSeconds),
    wordMode: WORD_MODE[source.wordMode] ?? WORD_MODE.choose,
    language: str(source.language, 'en'),
    categories: [...(source.categories ?? ['random'])].map((category) => str(category)),
    customWords: [...(source.customWords ?? [])].map((word) => str(word)),
    allowVoteKick: bool(source.allowVoteKick, DEFAULT_SETTINGS.allowVoteKick),
    isPrivate: bool(source.isPrivate, DEFAULT_SETTINGS.isPrivate),
  };
}

/** Serializes a room and everyone seated in it. Mirrors `Room.toJson`. */
export function roomJson(room) {
  return {
    code: str(room?.code),
    hostId: str(room?.hostId),
    players: room?.orderedPlayers ? room.orderedPlayers().map(playerJson) : [],
    settings: settingsJson(room?.settings),
    status: ROOM_STATUS[room?.status] ?? ROOM_STATUS.waiting,
    createdAtMs: int(room?.createdAtMs),
    bannedIds: [...(room?.bannedIds ?? [])].map((id) => str(id)),
  };
}

/** Serializes one word-bank entry. Mirrors `WordItem.toJson`. */
export function wordItemJson(item) {
  return {
    text: str(item?.text),
    category: str(item?.category, 'random'),
    difficulty: str(item?.difficulty, 'medium'),
  };
}

/**
 * Whether the secret word may be shown to `recipientId`.
 *
 * True only for the current drawer, or once the turn is over - `roundEnd` and
 * `gameEnd` reveal the word to everyone. This is the whole word-secrecy rule,
 * expressed once.
 */
export function mayseeWord(state, recipientId) {
  if (!state) return false;
  if (state.phase === PHASE.roundEnd || state.phase === PHASE.gameEnd) return true;
  return Boolean(recipientId) && recipientId === state.drawerId;
}

/**
 * Serializes the game state FOR ONE RECIPIENT. Mirrors `GameState.toJson`.
 *
 * `word` is present only when `mayseeWord` allows it, and `wordChoices` are
 * drawer-only because the offer contains the word that was picked. Everybody
 * else gets `maskedWord` and `wordLength` and nothing more.
 *
 * @param {object} state internal engine state
 * @param {string|null} recipientId the player this payload is being built for
 */
export function gameStateJson(state, recipientId) {
  const reveal = mayseeWord(state, recipientId);
  const isDrawer = Boolean(recipientId) && recipientId === state?.drawerId;
  return {
    roomCode: str(state?.roomCode),
    phase: PHASE[state?.phase] ?? PHASE.lobby,
    currentRound: int(state?.currentRound),
    totalRounds: int(state?.totalRounds),
    turnIndex: int(state?.turnIndex),
    drawerId: state?.drawerId ?? null,
    word: reveal ? (state?.word ?? null) : null,
    maskedWord: str(state?.maskedWord),
    wordLength: int(state?.wordLength),
    hintIndices: [...(state?.hintIndices ?? [])].map((index) => int(index)),
    turnStartMs: int(state?.turnStartMs),
    turnEndMs: int(state?.turnEndMs),
    correctGuesserIds: [...(state?.correctGuesserIds ?? [])].map((id) => str(id)),
    roundScores: { ...(state?.roundScores ?? {}) },
    wordChoices: isDrawer ? [...(state?.wordChoices ?? [])].map(wordItemJson) : [],
  };
}

/** Serializes one normalized point to the compact 2-element wire format. */
export function pointJson(point) {
  if (Array.isArray(point)) return [dbl(point[0]), dbl(point[1])];
  return [dbl(point?.x), dbl(point?.y)];
}

/** Serializes a stroke with the compact keys id/a/p/c/w/t/ts. `Stroke.toJson`. */
export function strokeJson(stroke) {
  return {
    id: str(stroke?.id),
    a: str(stroke?.authorId),
    p: (stroke?.points ?? []).map(pointJson),
    c: int(stroke?.colorValue, 0xff1a1a1a),
    w: dbl(stroke?.width, 4),
    t: DRAW_TOOL[stroke?.tool] ?? DRAW_TOOL.pen,
    ts: int(stroke?.timestampMs),
  };
}

/** Serializes a chat row. Mirrors `ChatMessage.toJson`. */
export function chatMessageJson(message) {
  return {
    id: str(message?.id),
    senderId: str(message?.senderId),
    senderName: str(message?.senderName),
    text: str(message?.text),
    type: CHAT_TYPE[message?.type] ?? CHAT_TYPE.chat,
    timestampMs: int(message?.timestampMs),
  };
}

/** Serializes the scoreboard delta of a finished turn. `RoundResult.toJson`. */
export function roundResultJson(result) {
  return {
    round: int(result?.round),
    word: str(result?.word),
    drawerId: str(result?.drawerId),
    scoreDeltas: { ...(result?.scoreDeltas ?? {}) },
    totals: { ...(result?.totals ?? {}) },
    correctOrder: [...(result?.correctOrder ?? [])].map((id) => str(id)),
  };
}

/** Serializes one standings row. Mirrors `PlayerScore.toJson`. */
export function playerScoreJson(score) {
  return {
    playerId: str(score?.playerId),
    name: str(score?.name),
    avatarId: int(score?.avatarId),
    avatarColorIndex: int(score?.avatarColorIndex),
    score: int(score?.score),
    rank: int(score?.rank),
  };
}

/** Serializes the final standings of a game. Mirrors `GameResult.toJson`. */
export function gameResultJson(result) {
  return {
    roomCode: str(result?.roomCode),
    standings: (result?.standings ?? []).map(playerScoreJson),
    totalRounds: int(result?.totalRounds),
  };
}

/**
 * Serializes a failure. Mirrors `Failure.toJson` /
 * `Failure.fromJson({code, message, details})`.
 */
export function failureJson(code, message, details) {
  const errorCode = ERROR_CODE[code] ?? ERROR_CODE.unknown;
  const payload = { code: errorCode, message: str(message, errorCode) };
  if (details !== undefined && details !== null) payload.details = details;
  return payload;
}

/** A rejected ack: `{ok: false, error: Failure}`. */
export function errorAck(code, message, details) {
  return { ok: false, error: failureJson(code, message, details) };
}

/** An accepted ack, optionally carrying extra fields. */
export function okAck(extra = {}) {
  return { ok: true, ...extra };
}

/**
 * Builds the standings of a finished game: sorted by score descending, ranks
 * 1..n where ties share a rank.
 */
export function standingsFrom(players) {
  const sorted = [...players].sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    return String(a.name).localeCompare(String(b.name));
  });
  const standings = [];
  let rank = 0;
  let previousScore = null;
  sorted.forEach((player, index) => {
    if (previousScore === null || player.score !== previousScore) {
      rank = index + 1;
      previousScore = player.score;
    }
    standings.push({
      playerId: player.id,
      name: player.name,
      avatarId: player.avatarId,
      avatarColorIndex: player.avatarColorIndex,
      score: player.score,
      rank,
    });
  });
  return standings;
}
