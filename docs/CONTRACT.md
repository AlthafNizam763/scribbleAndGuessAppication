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
- Bundled fonts: family `SpaceGrotesk` (w400/500/700) and `PlusJakartaSans` (w400/500/600/700/800).
- NO code generation. No build_runner, no freezed, no json_serializable. Hand-write `fromJson`/`toJson`/`copyWith`.

## 1. Folder layout (binding)

```
lib/
  core/
    constants/    app_constants.dart, socket_events.dart, game_defaults.dart, app_strings.dart
    theme/        app_colors.dart, app_palette.dart, app_typography.dart, app_spacing.dart, app_elevation.dart, app_theme.dart, app_motion.dart
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
  widgets/        shared reusable widgets (the app UI kit)
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

## 4. Design system (binding — modern premium Gen-Z gaming)

FORBIDDEN: glassmorphism, `BackdropFilter`, blur, neon overload, multi-stop gradients as backgrounds,
3D transforms, big soft drop shadows, long or complex animations, a screen inventing its own colour.

REQUIRED look:
- One primary — **electric violet** — carries every action. A coral secondary and an aqua tertiary carry
  everything social and everything earned. Nothing else fills a surface except a game's own category colour.
- Depth is a **surface step plus a hairline**, never a shadow stack. A card is one notch above the page;
  `AppElevation.lifted` exists for cards that float and `AppElevation.glow` for the one primary button per
  screen, and that is the entire depth vocabulary.
- Corner radius: 8 / 12 / 16 / 20 / 28, plus a pill. Small shapes get proportionally rounder corners.
- Interactive surfaces answer a touch by **shrinking** to `AppMotion.pressScale` (0.96). Material's ink
  ripple is off app-wide (`NoSplash.splashFactory`): a ripple lands a frame late and reads as a second
  reaction to one tap. Use `PressableScale` for anything tappable that draws its own surface.
- Animations: <= 280ms, `Curves.easeOutCubic`, simple fades/slides/scales. Every duration MUST be routed
  through `AppMotion.duration(context, base)`, which returns `Duration.zero` under reduced motion.

### `AppColors` (raw tokens — brightness-specific, consumed by `AppPalette`)

```
violet, violetDeep, violetBright, violetWash, violetShade     // primary
coral, coralBright, coralWash, coralShade                     // secondary
aqua, aquaBright, aquaWash, aquaShade                         // tertiary
bg, surface, surfaceSunken, surfaceActive, border, borderStrong
text, textMuted, textFaint, canvas
darkBg, darkSurface, darkSurfaceSunken, darkSurfaceActive, darkBorder, darkBorderStrong
darkText, darkTextMuted, darkTextFaint, darkCanvas
success, warning, danger, info                                (+ dark* variants)
accentRed, accentBlue, accentYellow, accentGreen,
accentPurple, accentOrange, accentPink, accentTeal            (+ darkAccent* variants)
brandViolet, brandOrange, brandAqua, brandPlate, brandPink, brandInk  // the mark; brightness independent
avatarPalette  -> List<Color>   (8 entries, indexed by Player.avatarColorIndex — ORDER IS ON THE WIRE)
drawingPalette -> List<Color>   (24 entries, the drawing colour picker — ORDER IS ON THE WIRE)
```

Light and dark are both exposed through `AppPalette extends ThemeExtension<AppPalette>`, so widgets read
`context.palette.surface`, `context.palette.text`, etc. via an extension on `BuildContext`. A screen NEVER
writes a `Color(0x...)` literal. Three helpers cover colour that only exists at runtime — a game tint the
server sent: `wash(c)`, `washBorder(c)` and `onFill(c)`, the last computing readable ink by luminance.

### Typography (`AppTypography`)

- Display / headline / titleLarge / every number: family `SpaceGrotesk`, bundled **w400 / w500 / w700 only**.
- Body / labels / chat / inputs / button text: family `PlusJakartaSans`, bundled w400 / w500 / w600 / w700 / w800.
- Never ask a family for a weight it does not ship. The engine does not fail, it synthesises, and a faked
  bold is exactly the look this system replaced. `AppTypography.{regular,medium,semibold,bold,black}` name
  the safe values, and `test/widget/design_system_test.dart` holds the line.
- Exposes `static TextTheme textTheme(Color onSurface)` and `static TextStyle numeric(...)`, the latter
  tabular-figured so a counting timer does not jitter its own width.

### `AppSpacing`

`xs=4, sm=8, md=12, lg=16, xl=24, xxl=32, xxxl=48`; radii `radiusXs=8, radiusSm=12, radiusMd=16,
radiusLg=20, radiusXl=28, radiusPill=999`; strokes `hairline=1.0, border=1.5, borderThick=2.0`;
sizing `minTapTarget=48, controlHeight=52, controlHeightSm=40, maxContentWidth=1100`.

### `AppElevation` and `AppMotion`

`AppElevation.{none, lifted(shadow), raised(shadow), glow(tint)}`.
`AppMotion.{instant=110ms, normal=200ms, slow=280ms, ambient=1200ms}`, curves `standard / entrance / exit`,
and `pressScale = 0.96` with `pressScaleOf(context)` for the reduced-motion case.

## 5. Shared widget kit — exact file + class names

The kit lives in `lib/core/widgets/` (the design-system primitives, which import nothing from `providers/`)
and `lib/widgets/` (the game-aware pieces). Both are re-exported from `lib/widgets/widgets.dart`; import
that barrel.

| file | class | notes |
|---|---|---|
| `core/widgets/app_button.dart` | `AppButton` | `AppButtonVariant { primary, secondary, outline, ghost, danger }`, `AppButtonSize { regular, compact }`, `onPressed`, `icon`, `label`, `busy`, `expand`, `tone`. Shrinks on press; only `primary` glows. Min tap target 48. |
| `core/widgets/app_button.dart` | `AppIconButton` | square icon button, tooltip + semantics label required, `selected` / `filled` / `tone` |
| `core/widgets/app_button.dart` | `PressableScale` | wraps anything tappable that draws its own surface, so the whole app presses alike |
| `core/widgets/app_card.dart` | `AppCard` | the one container shape: surface + hairline. `selected` washes it in `tone`; `elevated` casts the one allowed shadow |
| `core/widgets/app_card.dart` | `AppSection` | eyebrow title over a card of rows |
| `core/widgets/app_card.dart` | `AppSectionHeading` | bold title + muted subtitle + optional trailing |
| `core/widgets/app_card.dart` | `AppBadge`, `AppStatTile` | tinted pill; labelled number |
| `core/widgets/app_controls.dart` | `AppStepperTile`, `AppToggleTile` | numeric stepper row; labelled switch row |
| `core/widgets/app_controls.dart` | `AppChip`, `AppChipGroup<T>` | selectable pill and its wrap |
| `core/widgets/app_controls.dart` | `AppProgressBar`, `AppSegmentedTabs` | pill progress bar; the segmented tab strip that replaces Material's underline |
| `core/widgets/app_scaffold.dart` | `AppScaffold` | page background, left-aligned display title + optional subtitle, banner, pinned bottom bar, max-width centering |
| `core/widgets/app_scaffold.dart` | `AppEmptyState`, `AppLoadingState`, `AppErrorState`, `AppSkeleton` | the four non-content states. A list that is about to arrive uses `AppSkeleton`, never a bare spinner. |
| `core/widgets/app_dialogs.dart` | `confirm()`, `notify()`, `showAppSheet<T>()` | the only dialog, toast and sheet entry points |
| `core/widgets/tap_feedback.dart` | `TapFeedback` | the hole the kit declares and `ScribbleGuessApp` fills with `SoundService` |
| `core/widgets/brand_logo.dart` | `BrandMark`, `BrandWordmark`, `BrandLogo` | the cat, the name, and the two locked up |
| `widgets/player_avatar.dart` | `PlayerAvatar` | procedural character avatar from `(avatarId, colorIndex)`. NO image assets. |
| `widgets/avatar_art.dart` | `AvatarKind` / `AvatarFace` / `AvatarCatalog` | the characters and the fixed pigments they are drawn in |
| `widgets/avatar_painter.dart` | `AvatarArtPainter` | `CustomPainter` that draws one `AvatarFace` in a 100x100 design box |
| `widgets/player_row.dart` | `PlayerRow` | avatar, name, state badges, score chip |
| `widgets/game_hud.dart` | `WordMaskDisplay`, `TurnTimerBar`, `HudBadge` | the word slots, the draining bar, the tinted pill |
| `widgets/social_widgets.dart` | `PlayerTile`, `RankBadge`, `RankChange`, `StatCell`, `StatsStrip`, `CountBadge` | the leaderboard / friends / profile vocabulary |
| `widgets/drawing_canvas.dart` | `DrawingCanvas` | see section 9 |
| `widgets/chat_panel.dart` | `ChatList`, `ChatComposer` | transcript + guess box |
| `widgets/connection_banner.dart` | `ConnectionBanner` | connecting / reconnecting / failed strip |


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
enum AppThemeMode { light, dark, system }
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
- **app_settings.dart** — `AppSettings { bool soundEnabled; bool hapticsEnabled; bool reducedMotion; AppThemeMode themeMode; String serverUrl; }` plus `static const defaults`.
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

## 8a. Platform games — Kazhutha, Bluff Bar, Space Mystery, Ludo

Section 8 is the **Scribble & Guess** protocol and is unchanged. The other four
games run on the platform room/match layer instead, which has its own event
namespace (`game:*`) and its own room channel. The two never mix: a Scribble
room is a `Room`, a platform room is a `GameRoom`, and `SCRIBBLE_GUESS` is
refused by every endpoint below on purpose.

Server source: `scribbleAndGuessWeb/src/socket/game_platform.socket.ts`.

### Rooms and matches (all four games)

```
'game:room_created'   {gameId, isPrivate?, maxPlayers?}   ack {room}
'game:player_joined'  {gameId, roomId|roomCode}           ack {room}
'game:player_left'    {gameId, roomId?}                   ack {room}
'game:player_ready'   {gameId, roomId?, ready}            ack {room, started}
'game:action'         {gameId, matchId, type, ...}        ack {state}
'game:chat_message'   {gameId, roomId?, message}          ack {message}
```

Server -> client:

```
'game:room_updated'   {room, event}
'game:match_started'  {matchId, roomId, gameId, status, state, result}
'game:match_state'    {matchId, roomId, gameId, status, state, result}
'game:match_completed'{matchId, roomId, gameId, status, state, result}
'game:chat_message'   {message}
```

`state` is **that viewer's projection**, not the match. Two players in one match
receive different `state` objects from the same broadcast, and nothing a player
is not entitled to is in theirs. This is the whole anti-cheat design: a client
cannot reveal a hand, a role or a position it was never sent.

Voice signalling reuses the same six events as section 8 under the `game:`
prefix (`game:voice_joined`, `game:voice_left`, `game:voice_offer`,
`game:voice_answer`, `game:voice_ice_candidate`, `game:player_muted`). Only SDP
and ICE travel; audio is peer-to-peer exactly as before.

### Kazhutha

One action. Aliased as `kazhutha:draw_card`, or send `type: 'draw_card'`
through `game:action`.

```
'kazhutha:draw_card'  {gameId, matchId, targetPlayerId, cardIndex?}
```

- Cards are real: `<rank><suit>`, two characters, ten is `T` — `AS`, `TD`, `QS`.
  The deck is 49 cards (52 less three queens) and `QS` is the donkey.
- `cardIndex` is a position in the target's fan. The server **reshuffles that
  hand immediately before the pick**, so the position is tactile but carries no
  information and cannot be used to collude over voice chat. Omitting it picks
  at random.
- Projection: `{currentPlayerId, donkeyCard, players[{playerId, cardCount, out,
  finishPosition}], discards[], finishOrder, lastAction, kazhuthaId}` plus your
  own `hand`. Other players' hands are **never** present — only counts.
- `discards` is public, because a laid pair goes face up on a real table. It is
  the only thing in the game a sharp player can count.
- `kazhuthaId` is null until the match completes, then names the donkey.

### Bluff Bar

```
'bluff:declare'    {gameId, matchId, cardIds[1..3], reaction?}
'bluff:challenge'  {gameId, matchId, reaction?}
'bluff:react'      {gameId, matchId, reaction}
```

- Each card is `{id, card}`: an instance id and a face. Ids exist because the
  shoe is multi-deck and the same face can appear twice.
- `declare` claims all the named cards are `tableRank`. Jokers count as it.
- `challenge` is legal only for the player on turn, only against the previous
  claim, and never against your own.
- `reaction` is one of `stare|smirk|sweat|laugh|drink|shrug` and never affects
  a rule.
- Projection: `{tableRank, roundNumber, deckComposition, players[{cardCount,
  alive, glassesRemaining, shotsTaken, outOfRound}], pileCount, claims[],
  lastClaim, lastChallenge, lastShot, lastReaction, eliminated}` plus `hand`.
- `deckComposition` is public and is the game: once the claims exceed what the
  shoe holds, somebody is lying and the arithmetic proves it.
- `lastClaim` carries a **count only**. The faces appear in
  `lastChallenge.revealed`, and paying for that is what a call *is*.
- `glassesRemaining` starts at 6 and never rises. A lost call is eliminated
  with probability `1/glassesRemaining`, then a glass is removed — so the sixth
  is a certainty and a match always terminates.

### Space Mystery — real-time

**This game does not use `game:action`'s persisted path.** It runs a 20 Hz
server-side simulation and broadcasts at 10 Hz. Positions are never written to
the database.

```
'space:move'       {gameId, matchId, dx, dy}        no meaningful ack
'space:task'       {gameId, matchId, stationId}
'space:eliminate'  {gameId, matchId, targetId}
'space:report'     {gameId, matchId}
'space:meeting'    {gameId, matchId}
'space:vote'       {gameId, matchId, targetId}      empty targetId = skip
'space:sabotage'   {gameId, matchId, kind}          breach | lights | comms
'space:vent'       {gameId, matchId, ventId?}       omit ventId to climb out
```

Server -> client, ten times a second, **one payload per viewer**:

```
'space:state'  {phase, serverMs, you, players[], seats[], bodies[],
                taskProgress, taskDone, taskTotal, sabotage, meeting,
                events[], result}
```

Binding rules the client must not attempt to work around:

- **`dx`/`dy` is a direction, never a position.** It is clamped to a unit
  vector on arrival and integrated against the floor plan server-side. A
  thousand move messages in a second move a player exactly as far as twenty.
- **`players[]` contains only who you can see** — inside your vision radius and
  with an unobstructed line of sight, or everybody if you are a ghost or in a
  meeting. A player you cannot see is not in the payload at all.
- **`role` is null** on every other player, except your fellow traitors if you
  are one, and everybody once the match has completed.
- **`you.tasks` is yours alone.** Crew progress is the single number
  `taskProgress`, so the bar moves without revealing whose bar it is.
- `sabotage` never names who triggered it.
- `meeting.voted` lists who has voted; what they voted is withheld until the
  count.
- The map arrives once, in the match's `publicState.map` — rooms, corridors,
  stations, vents, breach stations, the meeting table and the player radius.
  It is for drawing. Deleting a wall from the client's copy does not remove it
  from the server's.
- `events[]` is for the tick it happened on and is not replayed. A client that
  missed one was not connected.

### Rematch

```
'game:rematch_request'  {gameId, roomId}           ack {rematch}
'game:rematch_respond'  {gameId, roomId, accept}   ack {rematch}
```

The offer rides on the room, so it arrives in `game:room_updated` as
`room.rematch = {open, requestedBy, deadlineAtMs, accepted[], declined[],
outcome}`. `outcome` is `open | started | failed | cancelled`.

Binding behaviour, all of it server-side:

- An offer stands for **30 seconds**. When it lapses it *settles* rather than
  failing — three of five saying yes is a rematch.
- Requesting while an offer is open **counts as accepting it**. That is the
  duplicate protection: two players tapping at once is normal, not an error.
- **Declining also leaves the room.** A player who said no and stayed seated
  would be carried into the next deal by everybody else's acceptances.
- Bots are seated as accepted on creation. They never decline.
- If the survivors are below `minPlayers` and the game has bots, the shortfall
  is topped up to the minimum — never to the old occupancy.
- If it still cannot fill, `outcome` becomes `failed` and the client shows
  "Not enough players for rematch" with a way out.

### Platform voice

Same six verbs as section 8, under `game:`. **Exact names**, which differ from
the Scribble set and from each other:

```
'game:voice_joined'        {gameId, roomId}                 ack {enabled, voiceRoomId,
                                                                 peers, iceServers,
                                                                 muted, reason}
'game:voice_left'          {gameId, roomId}                 ack {}
'game:player_muted'        {gameId, roomId, muted}          ack {muted}
'game:voice_offer'         {gameId, roomId, targetId, description}   no ack
'game:voice_answer'        {gameId, roomId, targetId, description}   no ack
'game:voice_ice_candidate' {gameId, roomId, targetId, candidate}     no ack
```

Server -> client: the same names carrying `fromUserId`, plus
`game:voice_state` (the server withdrawing voice) and `game:voice_error`
(a refused signalling frame, out of band).

- Signalling is relayed on `platform-voice:<roomId>`, **not** the room
  channel, and offers are addressed to one peer rather than broadcast.
- Audio never crosses the socket and is never stored. ICE servers come from
  the server so no TURN credential is compiled into the app.
- **Who may talk is decided server-side, on every frame:**
  - Kazhutha and Ludo — anybody seated. Going out at Kazhutha is winning, not
    elimination, and those players are still at the table.
  - Bluff Bar — not once you have run out of glasses.
  - Space Mystery — **living players, during a meeting only.** The dead are
    refused outright, which is what stops a ghost naming their killer.
- Refusals are `NOT_IN_GAME` (membership, never changes while seated) or
  `VOICE_NOT_AVAILABLE` (timing — a client shows this as a microphone that is
  off for now, not as an error).
- Membership is re-derived whenever it can have changed: a meeting opening or
  closing, somebody dying, a match ending. Anybody who no longer qualifies is
  sent `game:voice_state {enabled: false}` and dropped from the channel.

The client speaks both dialects through one `VoiceChatService`, selected by
`VoiceDialect` — see `lib/services/voice/voice_dialect.dart`. Do not add a
third protocol.

### Bots (all four)

Seated through the REST platform API (`addStupids` / `clearStupids`, owner
only, waiting rooms only), at `EASY`, `NORMAL` or `HARD`. Difficulty changes
what a bot *notices*, not what it is allowed to see: every bot is handed the
same per-viewer projection a person in that seat would be sent, and its move
goes back through the same validator. There is no bot-only code path into any
rules engine.

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
`test/widget/`: the design system, player tile, drawing canvas (non-interactive render + no gestures while watching),
chat panel, word display masking, lobby screen, game screen scaffold.
Use `ProviderScope(overrides: [...])` with fake repositories. No network in tests.

## 14. Accessibility

- Min tap target 48x48 everywhere (`AppButton` enforces).
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
