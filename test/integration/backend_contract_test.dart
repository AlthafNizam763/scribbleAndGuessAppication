@Tags(<String>['integration'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/app/app_config.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/data/api/auth_api.dart';
import 'package:scribble_guess/models/drawing_event.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/models/round_result.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/repositories/impl/socket_chat_repository.dart';
import 'package:scribble_guess/repositories/impl/socket_drawing_repository.dart';
import 'package:scribble_guess/repositories/impl/socket_game_repository.dart';
import 'package:scribble_guess/repositories/impl/socket_room_repository.dart';
import 'package:scribble_guess/services/socket_service.dart';

/// The app's own client code, driven against a running backend.
///
/// This is deliberately *not* a mock. It builds the same `SocketService` and
/// the same `Socket*Repository` implementations the app builds, points them at
/// a real server, and plays a game. A protocol mismatch — a renamed field, a
/// changed envelope, a wrong enum spelling — shows up here and nowhere else,
/// because both sides parse defensively and would otherwise silently degrade
/// to a default rather than throwing.
///
/// It is tagged `integration` and skipped unless a server is reachable, so
/// `flutter test` stays hermetic:
///
///   cd ../scribbleAndGuessWeb && npm run dev
///   flutter test --tags integration
///
/// Against a local `npm run dev` one address serves both, because `server.ts`
/// attaches Socket.IO to the HTTP server Next is already using. In production
/// they are separate: the REST API is serverless and cannot hold a websocket
/// open, so the realtime server runs on its own host and is named separately.
///
///   flutter test --tags integration \
///     --dart-define=BACKEND_URL=http://localhost:3000
///
/// With no defines it tests the deployment the app itself ships against,
/// because both addresses come from [AppConfig] — the same resolution the
/// running app uses. That is the point: a test that hardcoded its own URLs
/// could pass while the app was pointed somewhere broken.
const String _backendOverride = String.fromEnvironment('BACKEND_URL');
final String backendUrl =
    _backendOverride.isNotEmpty ? _backendOverride : AppConfig.current.apiBaseUrl;

/// The realtime origin.
///
/// `SOCKET_URL` wins, then [AppConfig] — which already resolves that define
/// and knows to fall back to the REST origin for a local single-process
/// backend. `BACKEND_URL` alone therefore still describes a whole local
/// `npm run dev`, with no second define needed.
const String _socketUrlOverride = String.fromEnvironment('SOCKET_URL');
final String socketUrl = switch ((_socketUrlOverride, _backendOverride)) {
  (final String s, _) when s.isNotEmpty => s,
  (_, final String b) when b.isNotEmpty => b,
  _ => AppConfig.current.drawingSocketUrl,
};

/// One test client: an authenticated socket plus the app's repositories.
class _Client {
  _Client(this.name);

  final String name;

  late final ApiClient api;
  late final SocketService socket;
  late final SocketRoomRepository rooms;
  late final SocketGameRepository games;
  late final SocketDrawingRepository drawings;
  late final SocketChatRepository chats;

  late PlayerProfile profile;
  String token = '';

  /// Signs in as a guest and opens an authenticated socket.
  Future<void> start() async {
    api = ApiClient(
      baseUrl: backendUrl,
      tokenSource: () async => token,
    );

    final AuthApi auth = AuthApi(api);
    final Result<AuthSession> session = await auth.guest(
      PlayerProfile(id: '', name: name, avatarId: 1, avatarColorIndex: 2),
    );

    final AuthSession established = switch (session) {
      Ok<AuthSession>(:final AuthSession value) => value,
      Err<AuthSession>(:final Failure failure) =>
        throw StateError('$name could not sign in: ${failure.message}'),
    };

    token = established.token;
    profile = established.profile;

    socket = SocketService()..setCredentials(tokenSource: () async => token);

    final Result<void> connected = await socket.connect(socketUrl, profile);
    if (connected case Err<void>(:final Failure failure)) {
      throw StateError('$name could not connect: ${failure.message}');
    }

    rooms = SocketRoomRepository(socket);
    games = SocketGameRepository(socket);
    drawings = SocketDrawingRepository(socket);
    chats = SocketChatRepository(socket);
  }

  Future<void> stop() async {
    rooms.dispose();
    games.dispose();
    drawings.dispose();
    chats.dispose();
    await socket.disconnect();
    socket.dispose();
    api.dispose();
  }
}

/// Whether a backend is listening, so the suite can skip rather than fail.
///
/// Both halves are probed. Checking only REST is what made this suite fail
/// rather than skip when Socket.IO was not running: `/api/health` answered
/// happily from the serverless deployment while no realtime server existed at
/// all, so the run got as far as the handshake before dying with the app's
/// generic "No connection" copy.
Future<bool> _backendIsUp() async {
  // Generous enough for a hosted backend that has scaled to zero: a cold start
  // costs several seconds, and timing that out reports "no backend" for one
  // that is merely asleep.
  final ApiClient rest = ApiClient(
    baseUrl: backendUrl,
    tokenSource: () async => null,
    timeout: const Duration(seconds: 20),
  );
  try {
    // Retried once, because the first call to a serverless deployment pays for
    // a cold start and can outlast the timeout. Without the retry this suite
    // reports "no backend" and skips against infrastructure that is merely
    // waking up — which is worse than a slow test, because a skip reads as
    // "nothing to check here".
    Result<Map<String, dynamic>> health =
        await rest.get('/api/health', authenticated: false);
    if (health.isErr) {
      health = await rest.get('/api/health', authenticated: false);
    }
    if (health.isErr) return false;
  } finally {
    rest.dispose();
  }

  // The realtime server answers `/healthz`, and says whether Socket.IO is
  // actually attached rather than merely whether the process is alive.
  final ApiClient realtime = ApiClient(
    baseUrl: socketUrl,
    tokenSource: () async => null,
    timeout: const Duration(seconds: 20),
  );
  try {
    final Result<Map<String, dynamic>> health =
        await realtime.get('/healthz', authenticated: false);
    return switch (health) {
      Ok<Map<String, dynamic>>(:final Map<String, dynamic> value) =>
        value['socket'] == 'attached',
      Err<Map<String, dynamic>>() => false,
    };
  } finally {
    realtime.dispose();
  }
}

void main() {
  test(
    'the app\'s repositories play a full turn against the real backend',
    () async {
      // Probed inside the body rather than passed to `skip:`, because `skip`
      // is evaluated when the test is *registered* — before any setup has run
      // — so a value computed in `setUpAll` would still be uninitialised.
      if (!await _backendIsUp()) {
        markTestSkipped(
          'Backend not ready. REST: $backendUrl, realtime: $socketUrl. '
          'Run `npm run dev` for both on one port, or `npm run start:socket` '
          'for the realtime half.',
        );
        return;
      }

      final _Client host = _Client('HostBot');
      final _Client guest = _Client('GuestBot');

      await host.start();
      await guest.start();

      addTearDown(() async {
        await host.stop();
        await guest.stop();
      });

      // --- identity -------------------------------------------------------
      expect(host.profile.id, isNotEmpty, reason: 'the server assigns the id');
      expect(host.profile.name, 'HostBot');
      expect(host.profile.id, isNot(guest.profile.id));

      // --- create and join ------------------------------------------------
      final Result<Room> created = await host.rooms.createRoom(
        const RoomSettings(
          maxPlayers: 8,
          rounds: 1,
          drawTimeSeconds: 30,
          wordChoiceCount: 3,
          hintCount: 1,
          wordSelectSeconds: 5,
        ),
        host.profile,
      );

      final Room room = switch (created) {
        Ok<Room>(:final Room value) => value,
        Err<Room>(:final Failure failure) =>
          fail('createRoom failed: ${failure.message}'),
      };

      // Parsing the room at all proves the wire shape matches the model: a
      // wrong key would have produced a default, not an error.
      expect(room.code.length, 5);
      expect(room.hostId, host.profile.id);
      expect(room.players, hasLength(1));
      expect(room.settings.rounds, 1);
      expect(room.settings.drawTimeSeconds, 30);

      final Result<Room> joined =
          await guest.rooms.joinRoom(room.code, guest.profile);
      final Room afterJoin = switch (joined) {
        Ok<Room>(:final Room value) => value,
        Err<Room>(:final Failure failure) =>
          fail('joinRoom failed: ${failure.message}'),
      };

      expect(afterJoin.players, hasLength(2));
      expect(afterJoin.isHost(host.profile.id), isTrue);
      expect(afterJoin.isHost(guest.profile.id), isFalse);

      // --- permissions ----------------------------------------------------
      final Result<void> refused = await guest.games.startGame();
      expect(refused.isErr, isTrue, reason: 'only the host may start');
      expect(refused.failureOrNull?.code, AppErrorCode.notHost);

      // --- start, and find out who the server chose -----------------------
      final Completer<_Client> drawerFound = Completer<_Client>();
      final List<StreamSubscription<List<WordItem>>> choiceSubs =
          <StreamSubscription<List<WordItem>>>[];

      for (final _Client client in <_Client>[host, guest]) {
        choiceSubs.add(
          client.games.wordChoicesStream.listen((List<WordItem> choices) {
            if (choices.isNotEmpty && !drawerFound.isCompleted) {
              drawerFound.complete(client);
            }
          }),
        );
      }
      addTearDown(() async {
        for (final StreamSubscription<List<WordItem>> sub in choiceSubs) {
          await sub.cancel();
        }
      });

      final Result<void> started = await host.games.startGame();
      expect(started.isOk, isTrue, reason: 'the host may start');

      final _Client drawer = await drawerFound.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => fail('nobody was offered words'),
      );
      final _Client guesser = drawer == host ? guest : host;

      // --- word privacy ---------------------------------------------------
      final Result<void> selected = await drawer.games.selectWord(0);
      expect(selected.isOk, isTrue, reason: 'the drawer may select');

      final GameState drawerView = await drawer.games.gameStream
          .firstWhere((GameState state) => state.phase == GamePhase.drawing)
          .timeout(const Duration(seconds: 15));

      final GameState guesserView = await guesser.games.gameStream
          .firstWhere((GameState state) => state.phase == GamePhase.drawing)
          .timeout(const Duration(seconds: 15));

      final String word = drawerView.word ?? '';
      expect(word, isNotEmpty, reason: 'the drawer is told the word');
      expect(drawerView.isDrawer(drawer.profile.id), isTrue);

      expect(
        guesserView.word,
        isNull,
        reason: 'a guesser is never told the word before the round ends',
      );
      expect(guesserView.maskedWord, contains('_'));
      expect(guesserView.wordLength, greaterThan(0));
      expect(guesserView.turnEndMs, greaterThan(guesserView.turnStartMs));

      // --- drawing --------------------------------------------------------
      final Future<DrawingEvent> strokeArrived = guesser.drawings.events
          .firstWhere((DrawingEvent event) => event is StrokeBegan)
          .timeout(const Duration(seconds: 10));

      final Stroke stroke = Stroke(
        id: 'contract-stroke',
        authorId: drawer.profile.id,
        points: const <StrokePoint>[StrokePoint(x: 0.25, y: 0.25)],
        colorValue: 0xFF000000,
        width: 4,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );

      await drawer.drawings.beginStroke(stroke);
      await strokeArrived;

      // A guesser drawing must not reach anybody.
      bool leaked = false;
      final StreamSubscription<DrawingEvent> leakWatch =
          drawer.drawings.events.listen((DrawingEvent event) {
        if (event is StrokeBegan && event.stroke.id == 'illegal-stroke') {
          leaked = true;
        }
      });

      await guesser.drawings.beginStroke(
        stroke.copyWith(id: 'illegal-stroke', authorId: guesser.profile.id),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await leakWatch.cancel();

      expect(leaked, isFalse, reason: 'only the drawer may draw');

      // --- guessing -------------------------------------------------------
      final Result<void> wrong = await guesser.chats.send('not-the-word-at-all');
      expect(wrong.isOk, isTrue, reason: 'a wrong guess is ordinary chat');

      final Result<void> correct = await guesser.chats.send(word);
      expect(correct.isOk, isTrue);

      final GameState scored = await guesser.games.gameStream
          .firstWhere(
            (GameState state) =>
                state.correctGuesserIds.contains(guesser.profile.id),
          )
          .timeout(const Duration(seconds: 10));

      expect(scored.roundScores[guesser.profile.id], greaterThan(0));

      // --- the reveal -----------------------------------------------------
      final RoundResult result = await guesser.games.roundResultStream.first
          .timeout(const Duration(seconds: 45));

      expect(
        result.word,
        equalsIgnoringCase(word),
        reason: 'the answer is revealed only once the round has ended',
      );

      // --- the room stayed consistent throughout --------------------------
      final Room? live = guesser.rooms.currentRoom;
      expect(live, isNotNull);
      expect(live!.players, hasLength(2));

      final Player? scoredPlayer = live.playerById(guesser.profile.id);
      expect(scoredPlayer, isNotNull);
      expect(scoredPlayer!.score, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a dropped player comes back to the same seat rather than a new one',
    () async {
      if (!await _backendIsUp()) {
        markTestSkipped('Backend not ready. REST: $backendUrl, '
            'realtime: $socketUrl.');
        return;
      }

      final _Client host = _Client('StayBot');
      final _Client leaver = _Client('DropBot');

      await host.start();
      await leaver.start();
      addTearDown(() async {
        await host.stop();
        await leaver.stop();
      });

      final Result<Room> created = await host.rooms.createRoom(
        const RoomSettings(rounds: 1, drawTimeSeconds: 30),
        host.profile,
      );
      final Room room = switch (created) {
        Ok<Room>(:final Room value) => value,
        Err<Room>(:final Failure failure) =>
          throw StateError('could not create a room: ${failure.message}'),
      };

      final Result<Room> joined =
          await leaver.rooms.joinRoom(room.code, leaver.profile);
      expect(joined.isOk, isTrue);
      expect(joined.valueOrNull?.players, hasLength(2));

      // Drop the transport the way a tunnel or a lock screen does — without
      // leaving the room. The seat is kept server-side and only the presence
      // grace period expiring would give it up.
      final Future<Room> reseated = host.rooms.roomStream
          .firstWhere((Room r) => r.players.length == 2)
          .timeout(const Duration(seconds: 45));

      await leaver.socket.disconnect();
      expect(leaver.socket.currentStatus, ConnectionStatus.disconnected);

      // Reconnecting re-runs `c:hello`, which is what restores the seat.
      final Result<void> back =
          await leaver.socket.connect(socketUrl, leaver.profile);
      expect(back.isOk, isTrue, reason: 'the socket comes back');
      expect(leaver.socket.currentStatus, ConnectionStatus.connected);

      await reseated;

      // The point of the test: one seat, not two. A reconnect that registered
      // a fresh player would leave three rows here, and a reconnect that lost
      // the seat would leave one.
      final Room? after = host.rooms.currentRoom;
      expect(after, isNotNull);
      expect(
        after!.players,
        hasLength(2),
        reason: 'the reconnect reuses the seat instead of adding a player',
      );
      expect(
        after.playerById(leaver.profile.id),
        isNotNull,
        reason: 'the same player id is still seated',
      );
      expect(
        after.players.where((Player p) => p.id == leaver.profile.id),
        hasLength(1),
        reason: 'the player is seated exactly once',
      );
      expect(
        after.isHost(host.profile.id),
        isTrue,
        reason: 'a reconnect does not disturb who hosts',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
