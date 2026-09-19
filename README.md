# Scribble & Guess

**Draw it. Guess it. Win it.**

A real-time multiplayer drawing and guessing game. Flutter on the front, Firebase
as the authoritative backend, and a small Socket.IO relay for the one thing
Firestore is the wrong tool for: the pencil.

---

## Contents

- [Architecture](#architecture)
- [Folder structure](#folder-structure)
- [Prerequisites](#prerequisites)
- [Firebase setup](#firebase-setup)
- [Environment configuration](#environment-configuration)
- [Running locally](#running-locally)
- [Seeding the word bank](#seeding-the-word-bank)
- [Testing](#testing)
- [Deploying](#deploying)
- [Building the apps](#building-the-apps)
- [Branding](#branding)
- [Sound](#sound)
- [Security model](#security-model)
- [Troubleshooting](#troubleshooting)

---

## Architecture

Three processes, with a clear split of responsibility.

```
┌──────────────────────┐
│   Flutter client     │  UI, canvas, local preferences
└──────────┬───────────┘
           │  callable functions (writes)
           │  Firestore snapshots (reads)
┌──────────▼───────────┐
│  Firebase            │  THE AUTHORITY
│  ├── Auth            │  anonymous identity
│  ├── Firestore       │  rooms, players, messages, rounds
│  ├── Functions       │  every rule, every point, every deadline
│  └── Storage         │  avatars
└──────────┬───────────┘
           │  reads "who is the drawer?"
┌──────────▼───────────┐
│  Drawing relay       │  strokes only, in memory, never authoritative
│  (Node + Socket.IO)  │
└──────────────────────┘
```

**Why two backends.** Everything that decides who wins — the drawer rotation,
the secret word, the countdown, every score — lives in Cloud Functions, where
the client cannot reach it. But a stroke is tens of points per second per
drawer, and a Firestore write per point would be both unusably slow and
absurdly expensive. So drawing gets its own websocket, and that relay is
deliberately powerless: it holds no game state, decides nothing, and asks
Firestore whether a given uid may draw before it relays a single point.

**Layering.** The client follows `UI → Provider → Repository → Service →
Firebase`. Widgets never touch Firebase directly, and the repository layer is
an interface, so the Firebase implementation can be swapped for a fake in tests
without any screen knowing.

### The client never decides anything

The client sends *intentions* — "I picked word 2", "I guessed cat", "I clicked
ready". The server validates every one of them. There is no code path by which
a client sets a score, chooses the drawer, ends a round early, or reads the
answer.

---

## Folder structure

```
scribble_and_guess/
├── lib/
│   ├── main.dart               bootstrap: Firebase → prefs → sign-in → runApp
│   ├── app/                    app widget, router, build-time config
│   ├── core/
│   │   ├── constants/          app, game and Firebase constants
│   │   ├── errors/             AppException + the closed Failure vocabulary
│   │   ├── rules/              pure game logic (mirrors functions/, for prediction)
│   │   ├── utils/              validators, logger, responsive, result
│   │   └── widgets/            the app UI kit: buttons, cards, states, dialogs
│   ├── models/                 plain value types; no Firebase imports
│   ├── services/               Firebase and socket access
│   ├── repositories/           interfaces + impl/ (Firebase and socket backed)
│   ├── providers/              Riverpod wiring
│   ├── features/               one folder per screen
│   ├── theme/                  design tokens: colour, type, spacing, depth, motion
│   └── routes/                 route names
│
├── functions/                  THE AUTHORITATIVE BACKEND (TypeScript)
│   └── src/
│       ├── callable/           createRoom, joinRoom, selectWord, submitGuess…
│       ├── services/           game engine, scoring, words, moderation, presence
│       ├── utils/              validation, permissions, rate limiting, random
│       ├── scripts/            word-bank seeding
│       └── models/             Firestore document shapes
│
├── server/                     drawing relay only
│   ├── src/                    auth (Firebase token verify), boards, relay
│   └── legacy/                 the pre-migration game server, kept as reference
│
├── assets/words/               word banks: en, ml, hi, de, ja, ru, es, fr
├── assets/sounds/              synthesized effects (see tool/generate_sound_assets.dart)
├── test/                       unit/ and widget/
├── firestore.rules             production security rules
├── storage.rules
├── firestore.indexes.json
└── firebase.json
```

---

## Prerequisites

| Tool | Version | Check |
|---|---|---|
| Flutter | 3.41+ | `flutter --version` |
| Dart | 3.11+ | bundled with Flutter |
| Node.js | 20+ | `node --version` |
| Firebase CLI | 13+ | `firebase --version` |
| FlutterFire CLI | latest | `dart pub global activate flutterfire_cli` |

```bash
flutter doctor          # should be clean for your target platforms
firebase login
```

---

## Firebase setup

### 1. Create the projects

Three environments, so a broken deploy never touches real players:

```bash
firebase projects:create scribble-and-guess-dev
firebase projects:create scribble-and-guess-staging
firebase projects:create scribble-and-guess-prod
```

`.firebaserc` already maps these aliases. Switch with `firebase use staging`.

### 2. Enable the services

In the Firebase console, for each project:

- **Authentication** → Sign-in method → enable **Anonymous**
- **Firestore Database** → create, production mode, pick a region
- **Storage** → create
- **App Check** → register your apps (Play Integrity, App Attest, reCAPTCHA v3)
- **Crashlytics** and **Analytics** → enable

### 3. Generate the client configuration

```bash
flutterfire configure --project=scribble-and-guess-dev
```

This overwrites `lib/firebase_options.dart` with your project's real values.
Until you run it, that file reads its values from `--dart-define` instead, so a
fresh checkout builds and runs against the emulator with no project at all.

> Firebase client config is **not secret** — an API key identifies a project, it
> does not authorise anything. Access is decided by the security rules, App
> Check and the functions' own permission checks. It is still worth keeping out
> of version control, because a committed config makes it far too easy to point
> a debug build at production by accident.

### 4. Install backend dependencies

```bash
cd functions && npm install
cd ../server && npm install
```

---

## Environment configuration

Copy `.env.example` to `.env` and fill it in. The Flutter app takes its
configuration from `--dart-define`, so the file is a convenience for the
backends and for assembling build commands.

| Define | Meaning |
|---|---|
| `FLAVOR` | `development` \| `staging` \| `production` |
| `API_BASE_URL` | REST origin. Defaults to the deployment (see below) |
| `SOCKET_URL` | Socket.IO origin. Defaults to `AppConfig.deployedRealtimeUrl`, then `API_BASE_URL` |
| `DRAWING_SOCKET_URL` | Older name for `SOCKET_URL`; still honoured |
| `USE_FIREBASE_EMULATORS` | Force the emulator suite on |
| `EMULATOR_HOST` | Defaults to `10.0.2.2` on Android, `localhost` elsewhere |
| `FIREBASE_*` | Only needed until you run `flutterfire configure` |

Telemetry follows the flavor: Analytics and Crashlytics are **off** outside
production, so local experiments never pollute production dashboards.

---

## The backend

The game backend is `scribbleAndGuessWeb`. Deployed, it is **two** origins —
a serverless REST API and a persistent realtime server, for the reason in
[Realtime needs a long-lived server](#realtime-needs-a-long-lived-server-on-its-own-origin).
Both addresses are written down once, in `lib/app/app_config.dart`:

```dart
static const String deployedBackendUrl =
    'https://scribble-and-guess-web.vercel.app';

/// Fill in after deploying the realtime half; empty falls back to the REST
/// origin, which is correct only for a local single-process backend.
static const String deployedRealtimeUrl = '';
```

Run everything locally and they collapse back into one address, because
`server.ts` serves both on one port.

That is the default for **every** flavor, so the app talks to the deployment
with no defines at all:

```bash
flutter run
```

Three things can override it, in order of precedence:

1. The **server address** field in the settings screen, if the player has
   typed one. Left empty — the default — it defers to the build.
2. `--dart-define=API_BASE_URL=...` at build time.
3. Otherwise `deployedBackendUrl`.

Point a build at a backend running on your own machine with:

```bash
# Android emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
# desktop or web
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

### Realtime needs a long-lived server, on its own origin

REST works against any host. Socket.IO does not: the backend attaches it to a
Node HTTP server in `scribbleAndGuessWeb/server.ts`, which a serverless
platform never executes. Against such a deployment `GET /api/health` answers
`"socket":"detached"`, `/socket.io` 404s, and the app authenticates but cannot
reach a lobby — every room, stroke, guess and score travels over the socket.
That is what the **"No connection. Check your network and try again."** screen
means when guest sign-in has already succeeded.

The backend therefore deploys as two pieces, and the app is told about both:

| | Origin | Serves |
|---|---|---|
| REST | `AppConfig.deployedBackendUrl` | guest sign-in, session, profile, leaderboard |
| Realtime | `AppConfig.deployedRealtimeUrl` | rooms, game, drawing, guessing, chat, timers |

Deploy `scribbleAndGuessWeb`'s realtime half to a host that keeps a process
alive (Render, Railway, Fly.io, a container — see that project's `render.yaml`
and `Dockerfile`), then point the app at it, either by filling in
`deployedRealtimeUrl` in `lib/app/app_config.dart` or per build:

```bash
flutter run --dart-define=SOCKET_URL=https://your-realtime-host
```

Left unset, the socket falls back to `API_BASE_URL`, which is right for a local
`npm run dev` — one process really does serve both there — and wrong against
the serverless deployment. The app detects exactly that case and logs it as a
configuration error rather than a generic network failure, so check the log
before assuming the network is at fault:

```
Socket connection failed:
  reason:    ...
  url:       https://scribble-and-guess-web.vercel.app
  transport: websocket
  token:     sent
  hint:      the socket is pointed at the REST deployment ... which is
             serverless and cannot hold a websocket open ...
```

To verify a deployment end to end, run the app's own client code against it:

```bash
flutter test test/integration/backend_contract_test.dart --tags integration \
  --dart-define=BACKEND_URL=https://scribble-and-guess-web.vercel.app \
  --dart-define=SOCKET_URL=https://your-realtime-host
```

---

## Running locally

You need three terminals.

**1 — Firebase emulators**

```bash
firebase emulators:start --only auth,firestore,functions,storage
```

The UI is at <http://localhost:4000>. Functions must be built first
(`cd functions && npm run build`), or use `npm --prefix functions run build:watch`.

**2 — Drawing relay**

```bash
cd server
FIRESTORE_EMULATOR_HOST=localhost:8080 \
FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
FIREBASE_PROJECT_ID=scribble-and-guess-dev \
npm run dev
```

**3 — The app**

```bash
flutter run --dart-define=FLAVOR=development
```

Development builds attach to the emulator suite automatically. To play a real
multiplayer game locally, run a second instance (`flutter run -d chrome`) and
join with the room code from the first.

---

## Seeding the word bank

The word bank lives in Firestore and the game cannot start a round without it.

```bash
cd functions
npm run build
FIRESTORE_EMULATOR_HOST=localhost:8080 npm run seed
```

Against a real project:

```bash
GOOGLE_APPLICATION_CREDENTIALS=./service-account.json \
FIREBASE_PROJECT=scribble-and-guess-dev \
npm run seed
```

The script reads `assets/words/words_<lang>.json` and is **idempotent** — word
ids are derived from the language and the word, so re-running updates rather
than duplicates.

> **On the word banks.** English, German, Spanish and French are substantial
> (~1,900 words). Malayalam, Hindi, Japanese and Russian ship as smaller
> starter sets of common, concrete nouns — enough to play, but worth a native
> speaker's review before you put them in front of real players. Guess matching
> for the non-Latin banks relies on NFKC normalisation rather than the Latin-1
> accent folding; see `normalize()` in `functions/src/services/wordService.ts`.

---

## Testing

```bash
flutter analyze                 # static analysis — must be clean
flutter test                    # unit + widget tests
cd functions && npm run lint && npm test
cd server && npm test
```

| Suite | Covers |
|---|---|
| `functions/src/services/rules.test.ts` | scoring, guess matching, hints, validation |
| `server/test/boards.test.js` | stroke order, undo/redo ownership, caps, rate limiting |
| `test/unit/rules_test.dart` | client-side prediction rules, timer maths |
| `test/unit/models_test.dart` | wire-format round-trips |
| `test/widget/design_system_test.dart` | the tokens, both themes, and the widget kit |

---

## Deploying

Always deploy rules and functions together — a function that writes a field the
rules do not expect will fail in production only.

```bash
firebase use staging

firebase deploy --only firestore:rules,storage:rules
firebase deploy --only firestore:indexes
firebase deploy --only functions
```

Deploying a single function while iterating:

```bash
firebase deploy --only functions:submitGuess
```

### The drawing relay

It is a plain Node service; anything that runs a container will do. It needs:

- `FIREBASE_PROJECT_ID`
- `GOOGLE_APPLICATION_CREDENTIALS` or `FIREBASE_SERVICE_ACCOUNT` (inline JSON)
- `CORS_ORIGIN` — set this to your web origin in production, not `*`
- `PORT`

```bash
cd server && npm start     # /health reports uptime and live room count
```

### Web hosting

```bash
flutter build web --release --dart-define=FLAVOR=production
firebase deploy --only hosting
```

---

## Building the apps

**Android**

```bash
flutter build appbundle --release \
  --dart-define=FLAVOR=production \
  --dart-define=DRAWING_SOCKET_URL=https://draw.example.com
```

Put `google-services.json` in `android/app/`. Signing goes in
`android/key.properties` — never commit it.

**iOS**

```bash
flutter build ipa --release --dart-define=FLAVOR=production
```

Put `GoogleService-Info.plist` in `ios/Runner/`. App Attest needs the App
Attest capability enabled in Xcode.

**Web**

```bash
flutter build web --release --dart-define=FLAVOR=production
```

App Check on web needs a reCAPTCHA v3 site key passed as
`--dart-define=RECAPTCHA_SITE_KEY=...`.

---

## Branding

The mark is a cat sitting on its haunches, eyes squeezed shut, one paw clapped
over its mouth because it cannot keep a straight face — the moment *after* the
stupid thing happened.

**There is no source image.** The mark is geometry, defined once in
[`lib/theme/brand.dart`](lib/theme/brand.dart) and drawn by `BrandMarkPainter`.
Everything else — the in-app logo, the launcher icons on five platforms, the
splash art — is that same set of paths scaled to fit, so a launcher icon can
never drift out of sync with the logo on the splash screen. Re-bake the bitmaps
after a change to the geometry or the brand colours with
`flutter test tool/generate_brand_assets.dart`.

**In the app**, reach for the widgets in
[`lib/core/widgets/brand_logo.dart`](lib/core/widgets/brand_logo.dart), all of
which follow the active brightness:

| Widget          | Use                                          |
| --------------- | -------------------------------------------- |
| `BrandLogo`     | The full lockup — splash and main menu        |
| `BrandMark`     | Symbol alone, where space is tight            |
| `BrandWordmark` | Hand-lettered name over its swash             |

**On the platforms**, the bitmaps are generated, not drawn by hand:

```bash
flutter test tool/generate_brand_assets.dart
```

That writes 69 files: Android launcher icons at five densities plus adaptive,
round and Android 13 monochrome layers; iOS and macOS app icon sets; web
favicon, PWA and maskable icons; a multi-size Windows `.ico`; light and dark
splash art for both Android and iOS; and 1024px masters in `brand/` for store
listings. Re-run it after any change to `brand.dart` and commit the result.

The generator is deliberately not named `*_test.dart`, so an ordinary
`flutter test` run never rewrites checked-in art.

---

## Sound

Thirteen short chiptune blips, none longer than a second and a half. They are
**generated, not recorded**:

```bash
dart run tool/generate_sound_assets.dart
```

That writes every file in `assets/sounds/` from the note data at the bottom of
the generator — pitch, timing, waveform and decay per note — so a cue is a
readable score in source control rather than a binary nobody can diff. Re-run it
after editing a score and commit the result. The whole set is under 200 KB.

**What plays when** is decided in one place,
[`lib/providers/sound_provider.dart`](lib/providers/sound_provider.dart), which
listens to the authoritative game state rather than to the screens. Almost every
cue is a consequence of the server pushing something — somebody guessed, a
letter was revealed, the turn ended — and those land during exactly the phase
changes that are also swapping one screen for another. Attached to the state,
above the router, a sound cannot be lost because the widget that would have
played it was mid-rebuild.

| Cue                             | Sound                                     |
| ------------------------------- | ----------------------------------------- |
| You guessed the word            | Rising triad an octave up, with a bass root |
| Somebody else guessed           | The same triad, plainer                   |
| Your guess was one letter off   | An unresolved whole step                  |
| A letter was revealed           | A single quiet blip                       |
| You must pick a word            | A repeated fifth — the only nagging cue   |
| The drawing started             | A quick upward run                        |
| The turn ended, somebody got it | A downward cadence                        |
| The turn ended, nobody did      | Two detuned low squares, bending down     |
| The game ended                  | A run up the triad into a held C major    |
| Last five seconds               | One tick per second                       |
| A player joined / left          | Two notes, rising / falling               |
| Any button, toggle or chip      | A dry click                               |

Each cue also carries a haptic, declared beside it on `SoundEffect`, so the two
Settings toggles — **Sound effects** and **Vibration** — are honoured in a single
place inside
[`SoundService.play`](lib/services/sound_service.dart).

Audio is treated as decoration throughout: every path swallows its exceptions,
and a device with no working audio plays nothing rather than failing a turn. The
players are configured as *sonification* with no audio focus (and `ambient` on
iOS), so the game never pauses the music somebody is already listening to, and
respects the iOS mute switch.

---

## Security model

The short version: **the client states intentions, the server decides facts.**

| Concern | How it is enforced |
|---|---|
| The secret word | Stored in `rooms/{id}/secret/{turn}`, which the rules deny to *every* client. Reaches the drawer only as a callable's return value. |
| Scores | Written exclusively by Cloud Functions. The rules make `score` unwritable by clients. |
| The drawer | Chosen by the server from a shuffled order fixed at kickoff. |
| The timer | `roundEndsAt` is a server timestamp. Clients may *ask* to end a round; the server checks its own clock and refuses if the deadline has not passed. |
| Drawing | The relay verifies a Firebase ID token, then asks Firestore whether that uid is the current drawer *and* the round is in its drawing phase. |
| Chat leaking the answer | `sendMessage` refuses to publish a line that matches the live word — including from the drawer. |
| Rate limiting | Fixed-window counters on the player document, updated inside the same transaction that accepts the message. |
| Bans | `bannedUserIds` on the room; `joinRoom` checks it. |

Race conditions that actually happen in play — two people guessing at the same
instant, two people taking the last seat, the deadline landing on the last
guess — are handled with Firestore transactions, and the state transitions are
idempotent so a retry cannot double-score.

---

## Troubleshooting

**"Firebase is not configured"**
`flutterfire configure` has not been run and no `FIREBASE_*` defines were
passed. The screen tells you the command.

**Rounds never start / the timer sticks**
The word bank is empty — run the seed script. Failing that, check the
`sweepGames` scheduled function is deployed; it is the safety net that finishes
rounds whose scheduled task was lost.

**Strokes do not appear for other players**
Everything in a round travels over the socket, so this is a realtime problem,
not a drawing one. Check the realtime server's `/healthz` — it reports
`"socket":"attached"` only when Socket.IO is really running — and that
`SOCKET_URL` names it rather than the serverless REST origin.

**"No connection. Check your network and try again." right after signing in**
Sign-in is REST and the lobby is the socket, so succeeding at one and failing
at the other points squarely at the realtime server. In order: does
`GET /api/health` report `socket.status: "up"`? Does the realtime host's
`/healthz` say `"socket":"attached"`? Is `SOCKET_URL` pointed at that host
rather than the REST one? Is its `JWT_SECRET` identical to the REST
deployment's — a mismatch rejects every handshake with `AUTH_ERROR`. The
socket log names whichever of these it is.

**Emulators unreachable from an Android device**
An emulator reaches the host at `10.0.2.2`, which is the default. A *physical*
device needs your machine's LAN IP: `--dart-define=EMULATOR_HOST=192.168.x.x`.

**`permission-denied` writing a profile**
The create rule requires `gamesPlayed`, `gamesWon` and `totalScore` to start at
zero — those are server-owned aggregates. Writing a profile with any other
value is refused by design.

**Functions deploy fails on lint**
`npm --prefix functions run lint` runs as a predeploy step. Fix it locally
first; `--max-warnings 0` is deliberate.

**Web build fails: `The method 'isA' isn't defined for the type 'Object'`**

> ⚠️ **Known upstream issue — the web build does not currently compile.**

This is a bug in `firebase_core_web` 3.11.0 (the latest release), not in this
project. Two lines call `e.isA<JSObject>()` inside a `catch (e)` block, where
`e` is statically `Object`; the `isA` extension is declared on `JSAny?`, so
under Dart 3.11.5 it does not resolve:

```
firebase_core_web-3.11.0/lib/src/firebase_core_web.dart:397:16
firebase_core_web-3.11.0/lib/src/firebase_core_web.dart:448:14
```

It affects both `dart2js` and `--wasm`, and it cannot be pinned around:
`firebase_core_web` 3.9.0 and 3.10.0 conflict with `firebase_crashlytics ^5.3.0`,
so version solving fails.

Android and iOS are unaffected — they do not use this package, and
`flutter build apk` succeeds.

Options, in order of preference:

1. **Wait for the upstream fix** and bump `firebase_core`. This is two lines in
   a package that is actively maintained.
2. **Pin a Dart/Flutter version** where the extension still resolves.
3. **Patch locally** with a `dependency_overrides` entry pointing at a forked
   `firebase_core_web` whose two `e.isA<JSObject>()` calls read
   `(e as JSAny?).isA<JSObject>()`.
4. **Drop Crashlytics from the web build** to free the version constraint, if
   web matters more to you than web crash reporting.
