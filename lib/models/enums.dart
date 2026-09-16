import 'dart:ui' show Locale;

import 'package:scribble_guess/models/json_utils.dart';

/// Phase of the authoritative game loop owned by the server.
///
/// The Dart identifiers stay idiomatic camelCase while [wire] carries the
/// snake_case value the backend actually writes to Firestore
/// (`game.roundStatus`). Keeping the two apart means the protocol can follow
/// the server's vocabulary without every `switch` in the UI having to.
enum GamePhase {
  /// Players are gathering in the lobby.
  lobby('waiting'),

  /// A short countdown before the first turn.
  starting('starting'),

  /// The drawer is picking a word.
  wordSelection('word_selection'),

  /// The drawer is drawing and everyone else is guessing.
  drawing('drawing'),

  /// The turn ended and scores are shown.
  roundEnd('round_result'),

  /// The whole game ended and final standings are shown.
  gameEnd('final_result'),

  /// A started game is on hold because the room dropped below the minimum
  /// number of players.
  ///
  /// Not the same as [lobby]: the scores, the round number and the turn order
  /// are all still live and the match resumes from here as soon as enough
  /// players are back. The server owns the transition in both directions.
  paused('paused');

  const GamePhase(this.wire);

  /// The value used on the wire and in Firestore.
  final String wire;

  /// Parses [v] by wire value, falling back to [GamePhase.lobby].
  ///
  /// The Dart `name` is accepted too, so a payload written by an older client
  /// still parses rather than silently collapsing to the lobby.
  static GamePhase fromName(String? v) =>
      asWireEnum(GamePhase.values, v, (GamePhase e) => e.wire) ??
      asEnum(GamePhase.values, v) ??
      GamePhase.lobby;

  /// Short human readable label.
  String get label => switch (this) {
        GamePhase.lobby => 'Lobby',
        GamePhase.starting => 'Starting',
        GamePhase.wordSelection => 'Choosing a word',
        GamePhase.drawing => 'Drawing',
        GamePhase.roundEnd => 'Round over',
        GamePhase.gameEnd => 'Game over',
        GamePhase.paused => 'Paused',
      };
}

/// Lifecycle of a room.
///
/// As with [GamePhase], [wire] is the value Firestore holds in `rooms/{id}`;
/// the Dart identifiers stay camelCase.
enum RoomStatus {
  /// Waiting in the lobby for players.
  waiting('waiting'),

  /// The countdown between "start" and the first turn.
  starting('starting'),

  /// A game is currently running.
  inGame('playing'),

  /// A turn ended and the room is showing the round result.
  roundResult('round_result'),

  /// The game finished and the room shows final standings.
  finished('finished'),

  /// The room is over for good and cannot be rejoined.
  closed('closed');

  const RoomStatus(this.wire);

  /// The value used on the wire and in Firestore.
  final String wire;

  /// Parses [v] by wire value, falling back to [RoomStatus.waiting].
  static RoomStatus fromName(String? v) =>
      asWireEnum(RoomStatus.values, v, (RoomStatus e) => e.wire) ??
      asEnum(RoomStatus.values, v) ??
      RoomStatus.waiting;

  /// Whether a game is under way in this room.
  bool get isPlaying =>
      this == RoomStatus.starting ||
      this == RoomStatus.inGame ||
      this == RoomStatus.roundResult;

  /// Whether the room can still be joined.
  bool get isJoinable => this != RoomStatus.closed && this != RoomStatus.finished;

  /// Short human readable label.
  String get label => switch (this) {
        RoomStatus.waiting => 'Waiting',
        RoomStatus.starting => 'Starting',
        RoomStatus.inGame => 'In game',
        RoomStatus.roundResult => 'Round over',
        RoomStatus.finished => 'Finished',
        RoomStatus.closed => 'Closed',
      };
}

/// Realtime connection state of a single player as seen by the server.
enum PlayerConnection {
  /// The socket is live.
  connected,

  /// The socket dropped but the seat is held open.
  reconnecting,

  /// The player is gone.
  disconnected;

  /// Parses [v], falling back to [PlayerConnection.connected].
  static PlayerConnection fromName(String? v) =>
      asEnum(PlayerConnection.values, v) ?? PlayerConnection.connected;

  /// Short human readable label.
  String get label => switch (this) {
        PlayerConnection.connected => 'Online',
        PlayerConnection.reconnecting => 'Reconnecting',
        PlayerConnection.disconnected => 'Offline',
      };
}

/// Tool used to lay down a stroke on the canvas.
/// What the drawer is drawing with.
///
/// ## Every tool is still a stroke
///
/// A rectangle is two points and a tool name; a fill is a colour and a tool
/// name. Neither is a special message — all of them travel the same
/// `begin/append/end` path, land in the same append-only board, and are undone
/// by the same undo. That is what keeps one ordering rule and one redo stack
/// for the whole feature.
///
/// The wire names are the backend's `DRAW_TOOL` values and must be changed in
/// lockstep with them.
enum DrawTool {
  /// The default fine nib. Solid, round cap.
  pen,

  /// Thinner and slightly translucent, so overlaps read as shading.
  pencil,

  /// Wide, translucent and square-capped: strokes build up where they cross.
  marker,

  /// Solid, and its width follows pointer pressure where a device reports it.
  brush,

  /// Paints in the page colour.
  ///
  /// Never a real cut-out: the board is an append-only log, so painting over
  /// is what keeps every client's replay of that log identical.
  eraser,

  /// Floods the whole canvas with one colour.
  fill,

  /// A straight segment between two points.
  line,

  /// An axis-aligned rectangle between two corners.
  rectangle,

  /// An ellipse inscribed in the box between two corners.
  circle;

  /// Parses [v], falling back to [DrawTool.pen].
  static DrawTool fromName(String? v) =>
      asEnum(DrawTool.values, v) ?? DrawTool.pen;

  /// Short human readable label.
  String get label => switch (this) {
        DrawTool.pen => 'Pen',
        DrawTool.pencil => 'Pencil',
        DrawTool.marker => 'Marker',
        DrawTool.brush => 'Brush',
        DrawTool.eraser => 'Eraser',
        DrawTool.fill => 'Fill',
        DrawTool.line => 'Line',
        DrawTool.rectangle => 'Rectangle',
        DrawTool.circle => 'Circle',
      };

  /// Whether this tool is defined by two points rather than by a path.
  ///
  /// A shape is previewed locally while the drag is in flight and sent **once**
  /// on release: streaming it would be a packet per frame for a geometry that
  /// only matters when it settles. The server enforces the two-point cap.
  bool get isShape =>
      this == DrawTool.line ||
      this == DrawTool.rectangle ||
      this == DrawTool.circle;

  /// Whether this tool commits the instant it is touched, with no drag.
  bool get isInstant => this == DrawTool.fill;

  /// Whether this tool streams points while the finger is down.
  bool get isFreehand => !isShape && !isInstant;

  /// Whether this tool lays down ink the colour palette applies to.
  ///
  /// False for the eraser, which always paints in the page colour whatever
  /// swatch is selected.
  bool get usesColor => this != DrawTool.eraser;

  /// Whether this tool's width matters.
  ///
  /// False for the fill, which covers the canvas regardless.
  bool get usesWidth => this != DrawTool.fill;

  /// Whether points from this tool should carry pointer pressure.
  ///
  /// Only the brush varies its width with pressure, and points are the
  /// highest-frequency payload in the game — so only the brush pays the extra
  /// number per point. See `PointTuple` on the server for the same reasoning.
  bool get usesPressure => this == DrawTool.brush;
}

/// Category a word belongs to in the word bank.
enum WordCategory {
  /// Living creatures.
  animals,

  /// Things you eat and drink.
  food,

  /// Everyday objects.
  objects,

  /// Locations and landmarks.
  places,

  /// Films and shows.
  movies,

  /// Sports and games.
  sports,

  /// Professions.
  jobs,

  /// Gadgets and computing.
  technology,

  /// The natural world.
  nature,

  /// Instruments and musical things.
  music,

  /// Things that carry you around.
  vehicles,

  /// Anything from every category.
  random;

  /// Parses [v], falling back to [WordCategory.random].
  static WordCategory fromName(String? v) =>
      asEnum(WordCategory.values, v) ?? WordCategory.random;

  /// Short human readable label.
  String get label => switch (this) {
        WordCategory.animals => 'Animals',
        WordCategory.food => 'Food',
        WordCategory.objects => 'Objects',
        WordCategory.places => 'Places',
        WordCategory.movies => 'Movies',
        WordCategory.sports => 'Sports',
        WordCategory.jobs => 'Jobs',
        WordCategory.technology => 'Technology',
        WordCategory.nature => 'Nature',
        WordCategory.music => 'Music',
        WordCategory.vehicles => 'Vehicles',
        WordCategory.random => 'Random',
      };
}

/// How hard a word is to draw and to guess.
enum WordDifficulty {
  /// Simple, short, very common words.
  easy,

  /// Everyday words of average length.
  medium,

  /// Long, abstract or unusual words.
  hard;

  /// Parses [v], falling back to [WordDifficulty.medium].
  static WordDifficulty fromName(String? v) =>
      asEnum(WordDifficulty.values, v) ?? WordDifficulty.medium;

  /// Short human readable label.
  String get label => switch (this) {
        WordDifficulty.easy => 'Easy',
        WordDifficulty.medium => 'Medium',
        WordDifficulty.hard => 'Hard',
      };
}

/// How much the guessers are told about the word they are chasing.
///
/// All three modes still let the drawer choose from a shortlist; what differs
/// is the shape of the clue everyone else sees. Custom word lists are *not* a
/// mode — a room with `customWords` draws from them whichever mode is set —
/// because the two choices are genuinely independent.
enum WordMode {
  /// Blanks reveal the word's length and its spaces: `_ _ _   _ _ _ _ _`.
  normal,

  /// The length is hidden too, so the mask gives nothing away until the first
  /// hint lands. Considerably harder, and the reason hints exist.
  hidden,

  /// Compound and two-part words are favoured when the bank offers them.
  combination;

  /// Parses [v], falling back to [WordMode.normal].
  static WordMode fromName(String? v) =>
      asEnum(WordMode.values, v) ?? WordMode.normal;

  /// Short human readable label.
  String get label => switch (this) {
        WordMode.normal => 'Normal',
        WordMode.hidden => 'Hidden',
        WordMode.combination => 'Combination',
      };

  /// One-line explanation, shown under the picker.
  String get description => switch (this) {
        WordMode.normal => 'Blanks show how long the word is.',
        WordMode.hidden => 'The length stays secret until the first hint.',
        WordMode.combination => 'Favours two-part and compound words.',
      };
}

/// Language of the word bank and of the app UI.
enum AppLanguage {
  /// English.
  en,

  /// Malayalam.
  ml,

  /// Hindi.
  hi,

  /// German.
  de,

  /// Japanese.
  ja,

  /// Russian.
  ru,

  /// Spanish.
  es,

  /// French.
  fr,

  /// Tamil.
  ta,

  /// Arabic. The one right-to-left language in the set.
  ar;

  /// Parses [v], falling back to [AppLanguage.en].
  static AppLanguage fromName(String? v) =>
      asEnum(AppLanguage.values, v) ?? AppLanguage.en;

  /// Language name written in that language.
  ///
  /// Endonyms, not English names: a player looking for their own language
  /// scans for the word they actually call it.
  String get label => switch (this) {
        AppLanguage.en => 'English',
        AppLanguage.ml => 'മലയാളം',
        AppLanguage.hi => 'हिन्दी',
        AppLanguage.de => 'Deutsch',
        AppLanguage.ja => '日本語',
        AppLanguage.ru => 'Русский',
        AppLanguage.es => 'Español',
        AppLanguage.fr => 'Français',
        AppLanguage.ta => 'தமிழ்',
        AppLanguage.ar => 'العربية',
      };

  /// Whether this language's word bank is written in a non-Latin script.
  ///
  /// Guess input for these relies on NFKC normalisation server-side rather
  /// than the Latin-1 accent folding, so it is worth being explicit about it.
  bool get isNonLatinScript =>
      this == AppLanguage.ml ||
      this == AppLanguage.hi ||
      this == AppLanguage.ja ||
      this == AppLanguage.ru ||
      this == AppLanguage.ta ||
      this == AppLanguage.ar;

  /// Whether this language is written right to left.
  ///
  /// Arabic is the only one in this set, and it matters far beyond text
  /// alignment: the whole layout mirrors, so a row that reads avatar-then-name
  /// in English must read name-then-avatar here. Flutter does that for any
  /// subtree under the right `Directionality`, which is why this is a property
  /// of the language rather than a decision each widget makes.
  bool get isRtl => this == AppLanguage.ar;

  /// The locale this language maps to.
  ///
  /// One place knows the mapping. A widget building its own from [name] would
  /// work right up until the first language whose BCP-47 code differs from its
  /// enum identifier.
  Locale get locale => Locale(name);
}

/// Kind of row shown in the chat panel.
enum ChatMessageType {
  /// Plain chat from a player who is not guessing.
  chat,

  /// A guess that was wrong.
  guess,

  /// A guess that matched the word.
  correctGuess,

  /// A guess that was one letter away.
  closeGuess,

  /// A server announcement.
  system,

  /// A player joined the room.
  playerJoined,

  /// A player left the room.
  playerLeft,

  /// A revealed-letter hint.
  hint;

  /// Parses [v], falling back to [ChatMessageType.chat].
  static ChatMessageType fromName(String? v) =>
      asEnum(ChatMessageType.values, v) ?? ChatMessageType.chat;

  /// Short human readable label.
  String get label => switch (this) {
        ChatMessageType.chat => 'Chat',
        ChatMessageType.guess => 'Guess',
        ChatMessageType.correctGuess => 'Correct guess',
        ChatMessageType.closeGuess => 'Close guess',
        ChatMessageType.system => 'System',
        ChatMessageType.playerJoined => 'Player joined',
        ChatMessageType.playerLeft => 'Player left',
        ChatMessageType.hint => 'Hint',
      };
}

/// State of the transport between the app and the game server.
enum ConnectionStatus {
  /// Nothing has been attempted yet.
  idle,

  /// First connection attempt is in flight.
  connecting,

  /// The socket is live.
  connected,

  /// The socket dropped and is being retried.
  reconnecting,

  /// The socket is down and no retry is scheduled.
  disconnected,

  /// Connecting failed for good.
  failed;

  /// Parses [v], falling back to [ConnectionStatus.idle].
  static ConnectionStatus fromName(String? v) =>
      asEnum(ConnectionStatus.values, v) ?? ConnectionStatus.idle;

  /// Short human readable label.
  String get label => switch (this) {
        ConnectionStatus.idle => 'Idle',
        ConnectionStatus.connecting => 'Connecting',
        ConnectionStatus.connected => 'Connected',
        ConnectionStatus.reconnecting => 'Reconnecting',
        ConnectionStatus.disconnected => 'Offline',
        ConnectionStatus.failed => 'Connection failed',
      };
}

/// Theme preference stored in the app settings.
enum SketchThemeMode {
  /// Always the paper-light palette.
  light,

  /// Always the ink-dark palette.
  dark,

  /// Follow the device setting.
  system;

  /// Parses [v], falling back to [SketchThemeMode.system].
  static SketchThemeMode fromName(String? v) =>
      asEnum(SketchThemeMode.values, v) ?? SketchThemeMode.system;

  /// Short human readable label.
  String get label => switch (this) {
        SketchThemeMode.light => 'Light',
        SketchThemeMode.dark => 'Dark',
        SketchThemeMode.system => 'System',
      };
}

/// Which set of repositories backs the running game.
enum BackendMode {
  /// Socket.IO backed multiplayer.
  online,

  /// On-device practice mode with bots.
  practice;

  /// Parses [v], falling back to [BackendMode.online].
  static BackendMode fromName(String? v) =>
      asEnum(BackendMode.values, v) ?? BackendMode.online;

  /// Short human readable label.
  String get label => switch (this) {
        BackendMode.online => 'Online',
        BackendMode.practice => 'Practice',
      };
}

/// Which population a leaderboard page is drawn from.
///
/// The three tabs of the leaderboard screen, and the `scope` parameter of
/// `GET /api/leaderboard/me/rank`. Mirrors `LEADERBOARD_SCOPE` in the
/// backend's `social.constants.ts`.
enum LeaderboardScope {
  /// Everybody who has finished at least one game.
  world('world'),

  /// The local player and their accepted friends.
  friends('friends'),

  /// Players who set the same city as the local player.
  locality('locality');

  const LeaderboardScope(this.wire);

  /// The value used on the wire.
  final String wire;

  /// Parses [v] by wire value, falling back to [LeaderboardScope.world].
  static LeaderboardScope fromName(String? v) =>
      asWireEnum(LeaderboardScope.values, v, (LeaderboardScope e) => e.wire) ??
      asEnum(LeaderboardScope.values, v) ??
      LeaderboardScope.world;

  /// Short human readable label, used as the tab title.
  String get label => switch (this) {
        LeaderboardScope.world => 'World',
        LeaderboardScope.friends => 'Friends',
        LeaderboardScope.locality => 'Locality',
      };
}

/// How the local player stands relative to another player.
///
/// The single value the profile screen's action buttons are driven from. It is
/// computed by the server and never inferred here: deciding for ourselves that
/// we are friends with somebody would be deciding what we are allowed to do to
/// them, and a stale client would offer actions the server refuses.
///
/// Note that there is no `blockedBy`. A player who has been blocked sees a
/// profile identical to a stranger's — the server reports [none] — and their
/// Add Friend tap is refused with a message that does not say why.
enum SocialRelation {
  /// The local player looking at their own profile.
  self('self'),

  /// No request, no friendship and no block.
  none('none'),

  /// A request from the local player is waiting on the other player.
  requestSent('request_sent'),

  /// A request from the other player is waiting on the local player.
  requestReceived('request_received'),

  /// Accepted, both ways.
  friends('friends'),

  /// The local player has blocked the other player.
  blocked('blocked');

  const SocialRelation(this.wire);

  /// The value used on the wire.
  final String wire;

  /// Parses [v] by wire value, falling back to [SocialRelation.none].
  ///
  /// Falling back to [none] rather than throwing matters: a server that grows
  /// a relation this build has not heard of should leave the profile showing
  /// "Add friend", which the server will refuse if it is wrong, rather than
  /// crashing the screen.
  static SocialRelation fromName(String? v) =>
      asWireEnum(SocialRelation.values, v, (SocialRelation e) => e.wire) ??
      asEnum(SocialRelation.values, v) ??
      SocialRelation.none;

  /// Whether the two players are connected in some way.
  bool get isFriend => this == SocialRelation.friends;

  /// Whether a request is open in either direction.
  bool get isPending =>
      this == SocialRelation.requestSent || this == SocialRelation.requestReceived;
}

/// The lifecycle of a friend request.
enum FriendRequestStatus {
  /// Sent and waiting on the receiver. The only status that blocks a resend.
  pending('pending'),

  /// The receiver said yes; a friendship exists.
  accepted('accepted'),

  /// The receiver said no.
  rejected('rejected'),

  /// The sender took it back, or a block resolved it.
  cancelled('cancelled');

  const FriendRequestStatus(this.wire);

  /// The value used on the wire.
  final String wire;

  /// Parses [v] by wire value, falling back to [FriendRequestStatus.pending].
  static FriendRequestStatus fromName(String? v) =>
      asWireEnum(
        FriendRequestStatus.values,
        v,
        (FriendRequestStatus e) => e.wire,
      ) ??
      asEnum(FriendRequestStatus.values, v) ??
      FriendRequestStatus.pending;
}
