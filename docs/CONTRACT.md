# Scribble & Guess — Engineering Contract (SOURCE OF TRUTH)

Every agent working on this repo MUST read this file first and follow it exactly.
Names, signatures and event strings defined here are binding. Do not invent alternatives.

---

## 0a. Backend (amendment — read this before section 11)

The authoritative backend is now **`../scribbleAndGuessWeb`** — a Next.js +
Node + TypeScript + MongoDB + Socket.IO server. Its `README.md` documents every
endpoint and event.

**Firebase is no longer authoritative for the game.** The app previously split
its backend in two — Firestore owned rooms, rounds and scoring while a separate
relay carried only strokes — and this document still describes that split in
places. It no longer holds:

- The socket protocol in **section 8 is unchanged and still binding.** The
  backend implements it exactly, which is why the `Socket*Repository` classes
  were kept and the `Firebase*Repository` ones were unwired.
- The same socket now carries **everything**: rooms, rounds, the word, the
  timer, scoring, chat and moderation, as well as drawing. There is one
  authority, so two sources of truth can no longer disagree about whose turn
  it is.
- Auth is a **backend-issued JWT**, not a Firebase ID token. It travels in the
  Socket.IO handshake (`auth: {token}`), not in `c:hello`; a socket without a
  valid token is refused before any handler runs. `AuthService` keeps its old
  method names (`ensureSignedIn`, `currentUserId`, `authStateChanges`) so the
  splash screen and providers did not have to change.
- The player id is the backend user's `_id`, not a Firebase uid. The rule is
  unchanged: **the server assigns it, the client never mints one.**
- `lib/repositories/impl/firebase_*.dart` and the Firebase services are left in
  the tree but are no longer wired into `core_providers.dart`.

Two additions to section 0's dependency rule: `http` was promoted from a
transitive dependency to a direct one so `lib/data/api/` can use it — no new
package enters the build — and nothing else was added.

New folders, following section 1's spirit:

```
lib/data/api/    api_client.dart, auth_api.dart     REST transport
```

Run both sides with:

```bash
cd scribbleAndGuessWeb && npm run seed && npm run dev
cd scribbleAndGuessAppication && flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

---

## 0. Environment (verified, do not change)

- Flutter 3.41.7 / Dart 3.11.5 (`sdk: ^3.11.5`)
- Package name: `scribble_guess`. Imports use `package:scribble_guess/...` (never relative `../..` across top-level folders).
- Dependencies (pinned in pubspec.yaml — DO NOT add new dependencies):
  - `flutter_riverpod: ^2.6.1`
  - `go_router: ^17.5.0`
  - `shared_preferences: ^2.5.5`
  - `socket_io_client: ^3.1.6`
  - `uuid: ^4.6.0`, `equatable: ^2.1.0`, `collection: ^1.19.1`
- Lints: `flutter_lints` + `strict-casts: true` + rules in analysis_options.yaml.
  In particular: `prefer_single_quotes`, `prefer_const_constructors`, `always_declare_return_types`,
  `avoid_print` (use `AppLogger`), `unawaited_futures` (use `unawaited(...)` from `dart:async`),
  `directives_ordering` (dart: imports, then package:, then relative — alphabetical inside each group).
- Bundled fonts: family `PatrickHand` (w400) and `Nunito` (w400/600/700/800).
- NO code generation. No build_runner, no freezed, no json_serializable. Hand-write `fromJson`/`toJson`/`copyWith`.

## 1. Folder layout (binding)

```
lib/
  core/
    constants/    app_constants.dart, socket_events.dart, game_defaults.dart, app_strings.dart
    theme/        app_colors.dart, app_typography.dart, app_spacing.dart, sketch_decoration.dart, app_theme.dart, app_motion.dart
    utils/        result.dart, app_logger.dart, responsive.dart, geometry.dart, time_utils.dart,
                  validators.dart, debouncer.dart, id_generator.dart, extensions.dart
    errors/       failures.dart
  models/         one file per model, snake_case file names
  domain/
    repositories/ abstract interfaces ONLY (no implementation, no Flutter imports)
    rules/        pure game logic: scoring, word selection, hints, guess matching, timer math
  data/
    repositories/ concrete implementations (socket-backed + local/offline)
    sources/      socket data source, preferences data source
    words/        word bank data
  services/       socket_service.dart, storage_service.dart, auth_service.dart, room_service.dart,
                  game_service.dart, drawing_service.dart, sound_service.dart, connectivity_service.dart
  providers/      riverpod providers, one file per feature area
  screens/        <feature>/<feature>_screen.dart (+ local widgets under <feature>/widgets/)
  widgets/        shared reusable widgets (the "sketch UI kit")
  routes/         app_router.dart, app_routes.dart
  main.dart
test/
  unit/  widget/
server/           Node.js + Socket.IO authoritative game server
docs/
```

## 2. Coding conventions (binding)

- Immutable models: `final` fields, `const` constructors where possible, `extends Equatable`, `props` override.
- Every model implements: `const X({...})`, `factory X.fromJson(Map<String, dynamic> json)`, `Map<String, dynamic> toJson()`, `X copyWith({...})`.
- JSON is defensive: never let a malformed payload throw. Use helpers from `lib/models/json_utils.dart`
  (`asString`, `asInt`, `asDouble`, `asBool`, `asStringList`, `asList`, `asMap`, `asIntMap`).
- Enums are serialized by their `name` string and parsed with a generated-by-hand
  `static X fromName(String? v) => ... ?? fallback` helper. NEVER use `values.byName` unguarded — it throws.
- No business logic inside widgets. No `setState` for shared state — Riverpod only.
- Build methods stay small: extract private `Widget _buildX()` methods or separate widget classes.
- Every user-facing string comes from `AppStrings`. Every colour from the theme. Every spacing value from `AppSpacing`.
- `avoid_print`: use `AppLogger.d/i/w/e`.
- Dispose every controller, subscription, timer, animation controller and focus node.

## 3. Riverpod 2.6.1 API rules (binding — do NOT use Riverpod 3 syntax)

- Use `Notifier` / `AsyncNotifier` + `NotifierProvider` / `AsyncNotifierProvider`. Do NOT use `StateNotifier`.
- Declaration form:
  ```dart
  final roomControllerProvider =
      NotifierProvider<RoomController, RoomUiState>(RoomController.new);

  class RoomController extends Notifier<RoomUiState> {
    @override
    RoomUiState build() => const RoomUiState.initial();
  }
  ```
- `AsyncNotifierProvider<C, T>(C.new)` with `class C extends AsyncNotifier<T> { @override Future<T> build() async {...} }`.
- Simple values: `Provider`, `FutureProvider`, `StreamProvider`. Use `StateProvider` only for trivial local UI toggles.
- Providers are KEEP-ALIVE by default in 2.x. Use `.autoDispose` explicitly when disposal is wanted.
- Inside a `Notifier`, dependencies are read with `ref.read(...)` / `ref.watch(...)`.
  Register teardown with `ref.onDispose(...)`.
- Widgets: `ConsumerWidget` / `ConsumerStatefulWidget` + `ConsumerState`. `ProviderScope` wraps the app in `main.dart`.
- Use `ref.listen` for side effects (navigation, snackbars) — never trigger navigation inside a `build` body.

## 4. Design system (binding — hand-drawn sketchbook)

FORBIDDEN: glassmorphism, blur, neon, heavy gradients, 3D transforms, elevation > 2, long/complex animations,
"premium dashboard" chrome, `BackdropFilter`, multi-stop gradients as backgrounds.

REQUIRED look:
- Background: warm paper off-white. Ink-black outlines. Playful accents used sparingly.
- Every container/button/card is drawn with a **hand-drawn wobbly border** via `SketchBorderPainter`
  (a `CustomPainter` that perturbs a rounded-rect path with deterministic pseudo-random jitter seeded by an
  int `seed`, so it does NOT re-randomise every frame).
- Offsets/shadows: at most one flat "sticker" offset shadow (solid ink colour, no blur, 2-3px), never soft blurs.
- Corner radius: 10-16.
- Animations: <= 250ms, `Curves.easeOut`, simple fades/slides/scales. All animation durations MUST be routed
  through `AppMotion.duration(context, base)`, which returns `Duration.zero` when reduced-motion is on.

### `AppColors` (exact names — theme agent creates, everyone else consumes)

```
paper, paperDim, paperShade        // backgrounds
ink, inkSoft, inkFaint             // text/outlines
accentRed, accentBlue, accentYellow, accentGreen, accentPurple, accentOrange, accentPink, accentTeal
success, warning, danger, info
canvasWhite
avatarPalette  -> List<Color>   (8 entries, indexed by Player.avatarColorIndex)
drawingPalette -> List<Color>   (24 entries, the drawing colour picker)
```

Light and dark palettes are both exposed through `SketchColors extends ThemeExtension<SketchColors>`,
so widgets read `context.sketch.paper`, `context.sketch.ink`, etc. via an extension on `BuildContext`.

### Typography (`AppTypography`)

- Display/headings/buttons/room-code: family `PatrickHand`.
- Body/labels/chat/inputs: family `Nunito`.
- Exposes `static TextTheme textTheme(Color onSurface)`.

### `AppSpacing`

`xs=4, sm=8, md=12, lg=16, xl=24, xxl=32`, plus `radiusSm=10, radiusMd=14, radiusLg=20`, `border=2.0`.

## 5. Shared widget kit (`lib/widgets/`) — exact file + class names

| file | class | notes |
|---|---|---|
| `sketch_border_painter.dart` | `SketchBorderPainter` | deterministic wobbly rounded-rect painter; correct `shouldRepaint` |
| `sketch_container.dart` | `SketchContainer` | box with hand-drawn border + optional flat offset shadow |
| `sketch_button.dart` | `SketchButton` | `SketchButtonVariant { primary, secondary, danger, ghost }`, `SketchButtonSize { small, medium, large }`, `onPressed`, `icon`, `label`, `isLoading`, `expanded`. Min tap target 48. |
| `sketch_icon_button.dart` | `SketchIconButton` | square icon button, tooltip + semantics label required |
| `sketch_card.dart` | `SketchCard` | padded `SketchContainer` with optional `title` |
| `sketch_text_field.dart` | `SketchTextField` | hand-drawn bordered input |
| `sketch_scaffold.dart` | `SketchScaffold` | paper background + optional `SketchAppBar` + safe area + max-width centering |
| `sketch_app_bar.dart` | `SketchAppBar` | title + leading back doodle + actions |
| `sketch_dialog.dart` | `SketchDialog`, `showSketchDialog<T>()`, `showSketchConfirmDialog()` | sketch-styled dialogs |
| `sketch_bottom_sheet.dart` | `showSketchBottomSheet<T>()` | |
| `sketch_chip.dart` | `SketchChip` | selectable pill |
| `sketch_slider.dart` | `SketchSlider` | labelled slider |
| `sketch_toggle.dart` | `SketchToggle` | labelled switch row |
| `sketch_stepper.dart` | `SketchNumberStepper` | minus/plus integer stepper |
| `sketch_progress_bar.dart` | `SketchProgressBar` | timer bar |
| `sketch_divider.dart` | `SketchDivider` | wobbly line |
| `sketch_badge.dart` | `SketchBadge` | small count/status badge |
| `sketch_empty_state.dart` | `SketchEmptyState` | doodle + message + optional action |
| `sketch_loader.dart` | `SketchLoader` | pencil-scribble loading indicator |
| `sketch_snackbar.dart` | `SketchSnack` | `SketchSnack.show(context, message, type)` |
| `doodle_icons.dart` | `DoodleIcons` / `DoodleIcon` / `DoodleGlyph` | `CustomPainter` doodle glyphs: pencil, eraser, palette, undo, redo, trash, crown, clock, trophy, chat, users, gear, home, question, wifiOff, star, check, cross, play, plus, minus, share, kick, ban, mute, report, back |
| `player_avatar.dart` | `PlayerAvatar` | procedural character avatar from `(avatarId 0..17, colorIndex 0..7)`. NO image assets. |
| `avatar_art.dart` | `AvatarKind` / `AvatarFace` / `AvatarCatalog` | the 18 characters — 6 people, 6 animals, 6 anime — and the fixed pigments they are drawn in |
| `avatar_painter.dart` | `AvatarArtPainter` | `CustomPainter` that draws one `AvatarFace` in a 100x100 design box |
| `player_tile.dart` | `PlayerTile` | avatar, name, animated score, host crown, drawing pencil, correct tick, ready state, connection dot, moderation overflow menu |
| `score_board.dart` | `ScoreBoard` | ranked list of `PlayerTile` with rank numerals |
| `drawing_canvas.dart` | `DrawingCanvas` | see section 9 |
| `color_picker.dart` | `SketchColorPicker` | grid over `AppColors.drawingPalette` |
| `brush_selector.dart` | `BrushSelector` | brush size dots + tool toggle |
| `chat_panel.dart` | `ChatPanel` | message list + input |
| `chat_bubble.dart` | `ChatBubble` | one message row, styled per `ChatMessageType` |
| `countdown_timer.dart` | `CountdownTimerView` | server-clock driven timer, ticks locally at 200ms |
| `word_display.dart` | `WordDisplay` | masked/revealed word with letter blanks |
| `confetti_overlay.dart` | `ConfettiOverlay` | lightweight `CustomPainter` confetti, ~60 particles, 2.5s, auto-stops |
| `animated_score_text.dart` | `AnimatedScoreText` | tweens between int values |
| `connection_banner.dart` | `ConnectionBanner` | connecting / reconnecting / offline banner |
| `responsive_layout.dart` | `ResponsiveLayout` | `compact`/`medium`/`expanded` builders |

## 6. Models (`lib/models/`) — exact class + field names

All extend `Equatable`. All have `fromJson` / `toJson` / `copyWith`.

**enums.dart** (all enums live here, each with a `fromName` static and a `label` getter where useful)

```dart
enum GamePhase { lobby, starting, wordSelection, drawing, roundEnd, gameEnd }
enum RoomStatus { waiting, inGame, finished }
enum PlayerConnection { connected, reconnecting, disconnected }
enum DrawTool { pen, eraser }
enum WordCategory { animals, food, objects, places, movies, sports, jobs, technology, nature, random }
enum WordDifficulty { easy, medium, hard }
enum WordMode { choose, random, custom }
enum AppLanguage { en, es, fr, de }
enum ChatMessageType { chat, guess, correctGuess, closeGuess, system, playerJoined, playerLeft, hint }
enum ConnectionStatus { idle, connecting, connected, reconnecting, disconnected, failed }
enum SketchThemeMode { light, dark, system }
enum BackendMode { online, practice }
```

- **json_utils.dart** — top-level defensive helpers (see section 2).
- **player_profile.dart** — `PlayerProfile { String id; String name; int avatarId; int avatarColorIndex; }`
- **player.dart** — `Player { String id; String name; int avatarId; int avatarColorIndex; int score; int roundScore; bool isHost; bool isReady; bool isDrawing; bool hasGuessed; int? guessOrder; bool isMuted; PlayerConnection connection; }` plus `bool get isConnected`.
- **room_settings.dart** — `RoomSettings { int maxPlayers; int rounds; int drawTimeSeconds; int wordChoiceCount; int hintCount; int wordSelectSeconds; WordMode wordMode; AppLanguage language; Set<WordCategory> categories; List<String> customWords; bool allowVoteKick; bool isPrivate; }` plus `static const RoomSettings defaults` and `List<String> validate()` returning human-readable problems (empty list == valid).
- **room.dart** — `Room { String code; String hostId; List<Player> players; RoomSettings settings; RoomStatus status; int createdAtMs; List<String> bannedIds; }` plus `Player? playerById(String id)`, `bool get isFull`, `bool isHost(String id)`, `int get readyCount`.
- **stroke_point.dart** — `StrokePoint { double x; double y; }` NORMALIZED to 0..1. Compact JSON as a 2-element list via `List<double> toJsonList()` / `StrokePoint.fromJsonList(dynamic)`.
- **stroke.dart** — `Stroke { String id; String authorId; List<StrokePoint> points; int colorValue; double width; DrawTool tool; int timestampMs; }`, plus `Stroke copyWithPoints(List<StrokePoint>)`. Compact JSON keys: `id`, `a` (authorId), `p` (points), `c` (colorValue), `w` (width), `t` (tool name), `ts` (timestampMs).
- **drawing_board.dart** — `DrawingBoard { List<Stroke> strokes; List<Stroke> redoStack; }` with pure ops `addStroke`, `replaceStroke`, `undo`, `redo`, `clear`, `static const empty`.
- **drawing_event.dart** — sealed class `DrawingEvent` with `StrokeBegan(Stroke)`, `StrokeAppended(String strokeId, List<StrokePoint> points)`, `StrokeEnded(String strokeId)`, `StrokeUndone(String strokeId)`, `StrokeRedone(Stroke stroke)`, `BoardCleared()`, `BoardSnapshot(List<Stroke> strokes)`.
- **word_item.dart** — `WordItem { String text; WordCategory category; WordDifficulty difficulty; }`
- **game_state.dart** — `GameState { String roomCode; GamePhase phase; int currentRound; int totalRounds; int turnIndex; String? drawerId; String? word; String maskedWord; int wordLength; List<int> hintIndices; int turnStartMs; int turnEndMs; List<String> correctGuesserIds; Map<String,int> roundScores; List<WordItem> wordChoices; }` plus `bool isDrawer(String playerId)` and `static const GameState initial`. `word` is non-null ONLY for the drawer or after round end.
- **round_result.dart** — `RoundResult { int round; String word; String drawerId; Map<String,int> scoreDeltas; Map<String,int> totals; List<String> correctOrder; }`
- **player_score.dart** — `PlayerScore { String playerId; String name; int avatarId; int avatarColorIndex; int score; int rank; }`
- **game_result.dart** — `GameResult { String roomCode; List<PlayerScore> standings; int totalRounds; }`
- **chat_message.dart** — `ChatMessage { String id; String senderId; String senderName; String text; ChatMessageType type; int timestampMs; }`
- **app_settings.dart** — `AppSettings { bool soundEnabled; bool hapticsEnabled; bool reducedMotion; SketchThemeMode themeMode; String serverUrl; }` plus `static const defaults`.
- **leaderboard_entry.dart** — `LeaderboardEntry { String playerId; String name; int avatarId; int avatarColorIndex; int totalScore; int gamesPlayed; int wins; int bestRoundScore; int updatedAtMs; }`

## 7. Errors + Result

`lib/core/errors/failures.dart`:

```dart
enum AppErrorCode {
  unknown, network, timeout, serverError, connectionLost,
  roomNotFound, roomFull, gameInProgress, nameTaken, invalidCode,
  banned, kicked, notHost, notDrawer, invalidAction, validation, storage,
}

class Failure extends Equatable {
  const Failure(this.code, this.message, {this.details});
  final AppErrorCode code;
  final String message;
  final Object? details;
  factory Failure.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
  String get userMessage; // maps code -> AppStrings
}
```

`lib/core/utils/result.dart`:

```dart
sealed class Result<T> { const Result(); }
final class Ok<T> extends Result<T> { const Ok(this.value); final T value; }
final class Err<T> extends Result<T> { const Err(this.failure); final Failure failure; }
// extension: isOk, isErr, valueOrNull, failureOrNull, fold<R>(onOk, onErr), map<R>()
// helper: Future<Result<T>> guard<T>(Future<T> Function() body)
```

## 8. Socket protocol — EXACT STRINGS

Mirrored in `lib/core/constants/socket_events.dart` (as `class SocketEvents { static const ... }`)
and `server/src/protocol.js`.

Client -> Server (all with ack callbacks unless noted)

```
'c:hello'             {profile}                  ack {ok, serverTimeMs, playerId}
'c:time:ping'         {t0}                       ack {t0, t1}
'c:room:create'       {settings, profile}        ack {ok, room} | {ok:false, error}
'c:room:join'         {code, profile}            ack {ok, room} | {ok:false, error}
'c:room:leave'        {}                         ack {ok}
'c:room:ready'        {ready}                    ack {ok}
'c:room:settings'     {settings}                 ack {ok}   (host only)
'c:room:kick'         {playerId}                 ack {ok}   (host only)
'c:room:ban'          {playerId}                 ack {ok}   (host only)
'c:room:mute'         {playerId, muted}          ack {ok}   (host only)
'c:room:transferHost' {playerId}                 ack {ok}   (host only)
'c:room:voteKick'     {playerId}                 ack {ok}
'c:room:report'       {playerId, reason}         ack {ok}
'c:game:start'        {}                         ack {ok}   (host only)
'c:game:selectWord'   {index}                    ack {ok}   (drawer only)
'c:game:playAgain'    {}                         ack {ok}   (host only)
'c:draw:begin'        {stroke}                   no ack
'c:draw:append'       {strokeId, points}         no ack
'c:draw:end'          {strokeId}                 no ack
'c:draw:undo'         {}                         no ack
'c:draw:redo'         {}                         no ack
'c:draw:clear'        {}                         no ack
'c:chat:send'         {text}                     ack {ok}

'c:voice:join'        {}                         ack {ok, enabled, isDrawer, phase, muted, peers, iceServers}
'c:voice:leave'       {}                         ack {ok}
'c:voice:offer'       {targetId, description}    ack {ok}   (guesser -> guesser only)
'c:voice:answer'      {targetId, description}    ack {ok}   (guesser -> guesser only)
'c:voice:ice'         {targetId, candidate}      ack {ok}   (guesser -> guesser only)
'c:voice:mute'        {muted}                    ack {ok, muted}
```

Server -> Client

```
's:room:state'        {room}
's:room:closed'       {reason}
's:you:kicked'        {reason}
's:game:state'        {game}                (word omitted unless recipient is drawer or round ended)
's:game:wordChoices'  {choices:[WordItem]}  (drawer only)
's:game:roundStart'   {game}
's:game:hint'         {hintIndices, maskedWord}
's:game:roundEnd'     {result, game}
's:game:end'          {result}
's:draw:begin'        {stroke}
's:draw:append'       {strokeId, points}
's:draw:end'          {strokeId}
's:draw:undo'         {strokeId}
's:draw:redo'         {stroke}
's:draw:clear'        {}
's:draw:snapshot'     {strokes}
's:chat:message'      {message}
's:time:sync'         {serverTimeMs}
's:error'             {error}

's:voice:state'       {enabled, isDrawer, phase, muted, peers, iceServers}  (to one recipient)
's:voice:peerJoined'  {peer:{userId, muted}}     (voice group only)
's:voice:peerLeft'    {userId, reason}           (voice group only)
's:voice:offer'       {from, description}        (to one peer's socket)
's:voice:answer'      {from, description}        (to one peer's socket)
's:voice:ice'         {from, candidate}          (to one peer's socket)
's:voice:mute'        {userId, muted}            (voice group only)
's:voice:error'       {code, message}            (code is the server's ErrorCode)
```

Rules: the server NEVER sends `word` to non-drawers before round end. The server owns the timer,
scores, correct-answer detection, phase transitions and every permission check.

### Voice chat (guessers only)

Voice is WebRTC. The `c:voice:*` / `s:voice:*` events carry **signalling only** — SDP offers,
SDP answers and ICE candidates. Audio never travels over this socket and is never stored.

The rule, enforced by the server and not by the UI:

- The **current drawer** may not join voice, may not signal, and may not be signalled. Every
  `c:voice:*` from them is refused with `error.details.code == 'DRAWER_VOICE_DISABLED'`, and an
  `s:voice:error` carrying `code: 'DRAWER_VOICE_DISABLED'` is pushed for the fire-and-forget
  verbs. `c:voice:leave` is the one exception and is always allowed, so a client complying with a
  role change is never refused.
- **Guessers** form a full WebRTC mesh with each other. Who sends the offer in a pair is decided
  by comparing player ids — the lexicographically smaller one offers — so no round trip is needed
  to avoid both ends offering at once.
- Voice is open in `word_selection`, `drawing` and `round_result`, and closed in every other
  phase. `s:voice:peerJoined` / `s:voice:peerLeft` go to the voice group, which the drawer is
  never in; `s:voice:state` is addressed to one recipient and is how a player who has just become
  the drawer is told to hang up.
- `iceServers` comes from the server's `WEBRTC_*` environment, so no STUN or TURN credential is
  compiled into the client.

## 9. Drawing canvas contract

- Coordinates are normalized to `[0,1]` relative to the canvas box, which is ALWAYS laid out at
  `AppConstants.canvasAspectRatio = 4 / 3`. `lib/core/utils/geometry.dart` provides
  `StrokePoint normalize(Offset local, Size size)` and `Offset denormalize(StrokePoint p, Size size)`.
- `DrawingCanvas` paints inside a `RepaintBoundary` with TWO `CustomPainter`s:
  a committed-strokes painter (repaints only when the committed list changes) and a live-stroke painter
  driven by a `ValueNotifier<Stroke?>` via `RepaintBoundary` + `CustomPaint`, so the widget tree does
  NOT rebuild while the finger moves.
- Points are simplified with `Geometry.simplify(points, tolerance)` (Ramer-Douglas-Peucker) before sending,
  and rendered with quadratic-bezier smoothing between midpoints.
- Outgoing points are batched at `AppConstants.strokeBatchMs = 60`.
- Eraser draws with `BlendMode.clear` inside a `saveLayer`.
- Non-drawers get `interactive: false` and no gesture recognizers at all.

## 10. Game rules (`lib/domain/rules/`) — pure Dart, no Flutter imports

- `scoring.dart` — `ScoringConfig` (const, tunable) + `ScoringService`:
  - `int guesserPoints({required int msRemaining, required int msTotal, required int guessOrder, required WordDifficulty difficulty})`
  - `int drawerPoints({required int correctGuessers, required int totalGuessers, required WordDifficulty difficulty})`
  - Deterministic and pure.
- `word_selection.dart` — `WordSelector` with an injectable `Random`:
  - `List<WordItem> pickChoices({required List<WordItem> pool, required RoomSettings settings, required Set<String> usedWords, required int count})`
- `hint_engine.dart` — `HintEngine.maskWord(String word, List<int> revealedIndices)`,
  `List<int> nextHintIndices({required String word, required List<int> current, required int totalHints, required int hintNumber, required Random random})`.
  Spaces and hyphens are always revealed and never count as hints.
- `guess_matcher.dart` — `GuessMatcher.evaluate(String guess, String word)` -> `GuessVerdict { correct, close, wrong }`
  (normalize case/accents/whitespace; `close` = Levenshtein distance 1 on a word of >= 4 letters).
- `turn_timer.dart` — `TurnTimer` pure math: `Duration remaining({required int turnEndMs, required int serverNowMs})`,
  `double progress({required int startMs, required int endMs, required int nowMs})` clamped 0..1.
- `room_state_machine.dart` — `RoomStateMachine.canTransition(GamePhase from, GamePhase to)` and `GamePhase next(...)`.

## 11. Repository interfaces (`lib/domain/repositories/`) — no Flutter imports

```dart
abstract interface class RoomRepository {
  Stream<Room> get roomStream;
  Stream<Failure> get errorStream;
  Room? get currentRoom;
  Future<Result<Room>> createRoom(RoomSettings settings, PlayerProfile profile);
  Future<Result<Room>> joinRoom(String code, PlayerProfile profile);
  Future<Result<void>> leaveRoom();
  Future<Result<void>> setReady(bool ready);
  Future<Result<void>> updateSettings(RoomSettings settings);
  Future<Result<void>> kickPlayer(String playerId);
  Future<Result<void>> banPlayer(String playerId);
  Future<Result<void>> mutePlayer(String playerId, bool muted);
  Future<Result<void>> transferHost(String playerId);
  Future<Result<void>> voteKick(String playerId);
  Future<Result<void>> reportPlayer(String playerId, String reason);
  void dispose();
}

abstract interface class GameRepository {
  Stream<GameState> get gameStream;
  Stream<List<WordItem>> get wordChoicesStream;
  Stream<RoundResult> get roundResultStream;
  Stream<GameResult> get gameResultStream;
  Future<Result<void>> startGame();
  Future<Result<void>> selectWord(int index);
  Future<Result<void>> playAgain();
  void dispose();
}

abstract interface class DrawingRepository {
  Stream<DrawingEvent> get events;
  Future<Result<void>> beginStroke(Stroke stroke);
  Future<Result<void>> appendPoints(String strokeId, List<StrokePoint> points);
  Future<Result<void>> endStroke(String strokeId);
  Future<Result<void>> undo();
  Future<Result<void>> redo();
  Future<Result<void>> clear();
  void dispose();
}

abstract interface class ChatRepository {
  Stream<ChatMessage> get messages;
  Future<Result<void>> send(String text);
  void dispose();
}

abstract interface class ProfileRepository {
  Future<PlayerProfile?> load();
  Future<Result<void>> save(PlayerProfile profile);
  Future<Result<void>> clear();
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<Result<void>> save(AppSettings settings);
}

abstract interface class LeaderboardRepository {
  Future<List<LeaderboardEntry>> load();
  Future<Result<void>> record(GameResult result, String selfPlayerId);
  Future<Result<void>> clear();
}
```

Two implementations of the realtime repositories live in `lib/data/repositories/`:
`SocketRoomRepository` / `SocketGameRepository` / `SocketDrawingRepository` / `SocketChatRepository`
(driven by `SocketService`), and `LocalRoomRepository` / `LocalGameRepository` / `LocalDrawingRepository` /
`LocalChatRepository` — an in-memory single-device "Practice" mode with simple bots so the app is fully
playable and testable with no server. Selection happens in `lib/providers/backend_provider.dart`
via `BackendMode { online, practice }`.

## 12. Routes (`lib/routes/`)

`AppRoutes` holds `static const String` path + name pairs:
`splash '/'`, `home '/home'`, `profile '/profile'`, `createRoom '/create'`, `joinRoom '/join'`,
`lobby '/room/:code'`, `game '/room/:code/game'`, `roundResult '/room/:code/round'`,
`finalResult '/room/:code/result'`, `leaderboard '/leaderboard'`, `settings '/settings'`,
`howToPlay '/how-to-play'`, `connectionLost '/error/connection'`, `roomNotFound '/error/room-not-found'`,
`roomFull '/error/room-full'`.

`app_router.dart` builds a `GoRouter` whose `redirect` pushes the user out of `/room/...` routes when
there is no active room, and the lobby/game screens guard back navigation with `PopScope` + a confirm dialog.

## 13. Testing

`test/unit/`: scoring, word selection, hint engine, guess matcher, turn timer, room state machine,
stroke serialization round-trip, geometry normalize/denormalize/simplify, room settings validation,
json_utils defensiveness, local repositories, drawing board ops.
`test/widget/`: sketch button, player tile, drawing canvas (non-interactive render + no gestures while watching),
chat panel, word display masking, lobby screen, game screen scaffold.
Use `ProviderScope(overrides: [...])` with fake repositories. No network in tests.

## 14. Accessibility

- Min tap target 48x48 everywhere (`SketchButton` enforces).
- `Semantics` labels on every icon-only control; `ExcludeSemantics` on decorative painters.
- Contrast: ink on paper >= 7:1. Never colour-only status — always pair with an icon or shape.
- `AppSettings.reducedMotion` (default follows `MediaQuery.disableAnimations`) short-circuits every animation
  through `AppMotion.duration(context, base)`.
- Layouts must survive text scale 1.3 — use `Flexible`/`FittedBox`, avoid fixed-height text rows.

## 15. Responsive breakpoints (`lib/core/utils/responsive.dart`)

`Breakpoints { compact < 600, medium 600..1023, expanded >= 1024 }`.

- Game screen: compact = canvas + collapsible bottom sheets for players/chat;
  medium = canvas with a right rail; expanded = 3 columns (players | canvas | chat).
- Content max width 1100 on expanded, centered.
