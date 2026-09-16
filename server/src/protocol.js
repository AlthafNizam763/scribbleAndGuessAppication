/**
 * Every Socket.IO event string of the protocol, exactly as defined in
 * docs/CONTRACT.md section 8 and mirrored by
 * lib/core/constants/socket_events.dart on the Flutter side.
 *
 * Never inline an event name anywhere else in the server.
 */

// ---------------------------------------------------------------------------
// Client -> server
// ---------------------------------------------------------------------------

/** Handshake carrying the local profile. Acks with the server clock. */
export const CLIENT_HELLO = 'c:hello';
/** Clock-offset probe. Acks with the send and server timestamps. */
export const CLIENT_TIME_PING = 'c:time:ping';
/** Creates a room from the given settings and profile. */
export const CLIENT_ROOM_CREATE = 'c:room:create';
/** Joins an existing room by code. */
export const CLIENT_ROOM_JOIN = 'c:room:join';
/** Leaves the current room. */
export const CLIENT_ROOM_LEAVE = 'c:room:leave';
/** Sets the ready flag of the calling player. */
export const CLIENT_ROOM_READY = 'c:room:ready';
/** Replaces the room settings. Host only. */
export const CLIENT_ROOM_SETTINGS = 'c:room:settings';
/** Removes a player from the room. Host only. */
export const CLIENT_ROOM_KICK = 'c:room:kick';
/** Removes a player and blocks them from rejoining. Host only. */
export const CLIENT_ROOM_BAN = 'c:room:ban';
/** Mutes or unmutes a player in chat. Host only. */
export const CLIENT_ROOM_MUTE = 'c:room:mute';
/** Hands the host role to another player. Host only. */
export const CLIENT_ROOM_TRANSFER_HOST = 'c:room:transferHost';
/** Casts a vote to kick a player. */
export const CLIENT_ROOM_VOTE_KICK = 'c:room:voteKick';
/** Reports a player with a free-form reason. */
export const CLIENT_ROOM_REPORT = 'c:room:report';
/** Starts the match. Host only. */
export const CLIENT_GAME_START = 'c:game:start';
/** Picks one of the offered words by index. Drawer only. */
export const CLIENT_GAME_SELECT_WORD = 'c:game:selectWord';
/** Restarts the match with the same players. Host only. */
export const CLIENT_GAME_PLAY_AGAIN = 'c:game:playAgain';
/** Announces the first points of a new stroke. No ack. */
export const CLIENT_DRAW_BEGIN = 'c:draw:begin';
/** Appends a batch of points to a live stroke. No ack. */
export const CLIENT_DRAW_APPEND = 'c:draw:append';
/** Ends a live stroke. No ack. */
export const CLIENT_DRAW_END = 'c:draw:end';
/** Undoes the last stroke of the drawer. No ack. */
export const CLIENT_DRAW_UNDO = 'c:draw:undo';
/** Redoes the last undone stroke of the drawer. No ack. */
export const CLIENT_DRAW_REDO = 'c:draw:redo';
/** Clears the board. No ack. */
export const CLIENT_DRAW_CLEAR = 'c:draw:clear';
/** Sends a chat message, which doubles as a guess while drawing. */
export const CLIENT_CHAT_SEND = 'c:chat:send';

// ---------------------------------------------------------------------------
// Server -> client
// ---------------------------------------------------------------------------

/** Full room snapshot after any membership or settings change. */
export const SERVER_ROOM_STATE = 's:room:state';
/** The room was closed, with a reason. */
export const SERVER_ROOM_CLOSED = 's:room:closed';
/** The recipient was kicked or banned, with a reason. */
export const SERVER_YOU_KICKED = 's:you:kicked';
/** Full game snapshot. The word is omitted for non-drawers. */
export const SERVER_GAME_STATE = 's:game:state';
/** The words the drawer may choose from. Drawer only. */
export const SERVER_GAME_WORD_CHOICES = 's:game:wordChoices';
/** A new turn started. */
export const SERVER_GAME_ROUND_START = 's:game:roundStart';
/** Extra letters were revealed in the masked word. */
export const SERVER_GAME_HINT = 's:game:hint';
/** The turn ended, carrying the round result and the new game state. */
export const SERVER_GAME_ROUND_END = 's:game:roundEnd';
/** The match ended, carrying the final standings. */
export const SERVER_GAME_END = 's:game:end';
/** A remote stroke started. */
export const SERVER_DRAW_BEGIN = 's:draw:begin';
/** Points were appended to a remote stroke. */
export const SERVER_DRAW_APPEND = 's:draw:append';
/** A remote stroke ended. */
export const SERVER_DRAW_END = 's:draw:end';
/** A remote stroke was undone. */
export const SERVER_DRAW_UNDO = 's:draw:undo';
/** A previously undone remote stroke was restored. */
export const SERVER_DRAW_REDO = 's:draw:redo';
/** The board was cleared. */
export const SERVER_DRAW_CLEAR = 's:draw:clear';
/** The full stroke list, sent to late joiners and after a reconnect. */
export const SERVER_DRAW_SNAPSHOT = 's:draw:snapshot';
/** A chat, guess or system message. */
export const SERVER_CHAT_MESSAGE = 's:chat:message';
/** Periodic broadcast of the authoritative server clock. */
export const SERVER_TIME_SYNC = 's:time:sync';
/** An out-of-band failure that is not tied to a single ack. */
export const SERVER_ERROR = 's:error';

// ---------------------------------------------------------------------------
// Enum value strings (Dart enum `.name` values - never invent alternatives)
// ---------------------------------------------------------------------------

/** GamePhase. */
export const PHASE = Object.freeze({
  lobby: 'lobby',
  starting: 'starting',
  wordSelection: 'wordSelection',
  drawing: 'drawing',
  roundEnd: 'roundEnd',
  gameEnd: 'gameEnd',
});

/** RoomStatus. */
export const ROOM_STATUS = Object.freeze({
  waiting: 'waiting',
  inGame: 'inGame',
  finished: 'finished',
});

/** PlayerConnection. */
export const CONNECTION = Object.freeze({
  connected: 'connected',
  reconnecting: 'reconnecting',
  disconnected: 'disconnected',
});

/** DrawTool. */
export const DRAW_TOOL = Object.freeze({ pen: 'pen', eraser: 'eraser' });

/** WordCategory, in canonical declaration order. */
export const WORD_CATEGORIES = Object.freeze([
  'animals',
  'food',
  'objects',
  'places',
  'movies',
  'sports',
  'jobs',
  'technology',
  'nature',
  'random',
]);

/** WordDifficulty, in canonical declaration order. */
export const WORD_DIFFICULTIES = Object.freeze(['easy', 'medium', 'hard']);

/** WordMode. */
export const WORD_MODE = Object.freeze({ choose: 'choose', random: 'random', custom: 'custom' });

/** AppLanguage, in canonical declaration order. */
export const LANGUAGES = Object.freeze(['en', 'es', 'fr', 'de']);

/** ChatMessageType. */
export const CHAT_TYPE = Object.freeze({
  chat: 'chat',
  guess: 'guess',
  correctGuess: 'correctGuess',
  closeGuess: 'closeGuess',
  system: 'system',
  playerJoined: 'playerJoined',
  playerLeft: 'playerLeft',
  hint: 'hint',
});

/** AppErrorCode from lib/core/errors/failures.dart. */
export const ERROR_CODE = Object.freeze({
  unknown: 'unknown',
  network: 'network',
  timeout: 'timeout',
  serverError: 'serverError',
  connectionLost: 'connectionLost',
  roomNotFound: 'roomNotFound',
  roomFull: 'roomFull',
  gameInProgress: 'gameInProgress',
  nameTaken: 'nameTaken',
  invalidCode: 'invalidCode',
  banned: 'banned',
  kicked: 'kicked',
  notHost: 'notHost',
  notDrawer: 'notDrawer',
  invalidAction: 'invalidAction',
  validation: 'validation',
  storage: 'storage',
});

/** GuessVerdict from lib/domain/rules/guess_matcher.dart. */
export const VERDICT = Object.freeze({ correct: 'correct', close: 'close', wrong: 'wrong' });

/** Every server-originated event, in protocol order. */
export const SERVER_EVENTS = Object.freeze([
  SERVER_ROOM_STATE,
  SERVER_ROOM_CLOSED,
  SERVER_YOU_KICKED,
  SERVER_GAME_STATE,
  SERVER_GAME_WORD_CHOICES,
  SERVER_GAME_ROUND_START,
  SERVER_GAME_HINT,
  SERVER_GAME_ROUND_END,
  SERVER_GAME_END,
  SERVER_DRAW_BEGIN,
  SERVER_DRAW_APPEND,
  SERVER_DRAW_END,
  SERVER_DRAW_UNDO,
  SERVER_DRAW_REDO,
  SERVER_DRAW_CLEAR,
  SERVER_DRAW_SNAPSHOT,
  SERVER_CHAT_MESSAGE,
  SERVER_TIME_SYNC,
  SERVER_ERROR,
]);

/** Every client-originated event, in protocol order. */
export const CLIENT_EVENTS = Object.freeze([
  CLIENT_HELLO,
  CLIENT_TIME_PING,
  CLIENT_ROOM_CREATE,
  CLIENT_ROOM_JOIN,
  CLIENT_ROOM_LEAVE,
  CLIENT_ROOM_READY,
  CLIENT_ROOM_SETTINGS,
  CLIENT_ROOM_KICK,
  CLIENT_ROOM_BAN,
  CLIENT_ROOM_MUTE,
  CLIENT_ROOM_TRANSFER_HOST,
  CLIENT_ROOM_VOTE_KICK,
  CLIENT_ROOM_REPORT,
  CLIENT_GAME_START,
  CLIENT_GAME_SELECT_WORD,
  CLIENT_GAME_PLAY_AGAIN,
  CLIENT_DRAW_BEGIN,
  CLIENT_DRAW_APPEND,
  CLIENT_DRAW_END,
  CLIENT_DRAW_UNDO,
  CLIENT_DRAW_REDO,
  CLIENT_DRAW_CLEAR,
  CLIENT_CHAT_SEND,
]);
