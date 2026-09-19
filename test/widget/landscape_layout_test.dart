import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/features/games/bluff_bar/bluff_bar_game_screen.dart';
import 'package:scribble_guess/features/games/kazhutha/kazhutha_game_screen.dart';
import 'package:scribble_guess/features/games/ludo/ludo_game_screen.dart';
import 'package:scribble_guess/features/games/ludo/widgets/ludo_board.dart';
import 'package:scribble_guess/features/games/space_mystery/space_mystery_game_screen.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/platform_match.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The three landscape tables, at every shape a phone or tablet actually is.
///
/// ## Why this test exists
///
/// Because "it compiles" says nothing about whether a card falls off the
/// bottom of a 20:9 phone, and neither does looking at one device. These
/// layouts were written against a scaling model — see `GameMetrics` — and the
/// only way to know the model holds is to drive it to the edges of its range
/// and check that Flutter does not report an overflow.
///
/// A `RenderFlex overflowed` is an *exception* in a widget test, not a yellow
/// stripe, so `tester.takeException()` returning null is a real assertion that
/// nothing was clipped. That is the whole mechanism here.
///
/// ## What this does and does not prove
///
/// It proves the layouts survive every shape listed below with live-looking
/// state in them: a dealt hand, opponents round the table, an overlay up. It
/// does **not** prove they look good — no automated test can — and it is not a
/// substitute for holding a phone. What it replaces is the much larger class
/// of problem where a layout is fine on the reviewer's device and broken on a
/// tall one.
void main() {
  /// The shapes worth testing, as landscape sizes in logical pixels.
  ///
  /// Each is a real device class rather than a round number: 16:9 is an older
  /// phone and most tablets in portrait-turned-landscape, 20:9 is a current
  /// tall phone, and the last is a tablet with genuine room. The tall ones are
  /// where things break, because landscape height is what everything here
  /// scales from.
  const Map<String, Size> shapes = <String, Size>{
    '16:9 phone': Size(640, 360),
    '18:9 phone': Size(720, 360),
    '19.5:9 phone': Size(780, 360),
    '20:9 phone': Size(800, 360),
    'tablet': Size(1280, 800),
    // A small tablet held the other way: the narrowest landscape this app can
    // plausibly be asked to draw, and the one that finds a fixed width.
    'compact tablet': Size(1024, 768),
  };

  /// A room with a full table: one human and five bots, at three difficulties.
  PlatformRoom roomFor(GameId gameId) => PlatformRoom.fromJson(<String, dynamic>{
        'roomId': 'room-1',
        'roomCode': 'ABCDEF',
        'gameId': gameId.wire,
        'ownerId': 'me',
        'status': 'playing',
        'isPrivate': true,
        'maxPlayers': 6,
        'matchId': 'match-1',
        'createdAtMs': 0,
        'players': <Map<String, dynamic>>[
          const <String, dynamic>{
            'playerId': 'me',
            'userId': 'me',
            // A long name on purpose: a seat badge that fits "Al" and not
            // "Bartholomew" is a seat badge that overflows for somebody.
            'username': 'Bartholomew',
            'avatarId': 1,
            'avatarColorIndex': 0,
            'isBot': false,
            'isReady': true,
            'connected': true,
            'joinedAtMs': 0,
          },
          for (int i = 0; i < 5; i++)
            <String, dynamic>{
              'playerId': 'bot-$i',
              'userId': null,
              'username': <String>[
                'Mr Whiskers', 'Professor Paws', 'Chaos Kitty',
                'Nervous Nancy', 'Big Yawn',
              ][i],
              'avatarId': i + 2,
              'avatarColorIndex': i,
              'isBot': true,
              'botDifficulty': <String>['EASY', 'NORMAL', 'HARD', 'EASY', 'HARD'][i],
              'isReady': true,
              'connected': true,
              'joinedAtMs': 0,
            },
        ],
      });

  /// A Kazhutha table mid-hand: a full fan, pairs down, somebody nearly out.
  Map<String, dynamic> kazhuthaState() => <String, dynamic>{
        'gameId': 'KAZHUTHA',
        'status': 'playing',
        'currentPlayerId': 'me',
        'donkeyCard': 'QS',
        'players': <Map<String, dynamic>>[
          <String, dynamic>{'playerId': 'me', 'cardCount': 9, 'out': false, 'finishPosition': 0},
          for (int i = 0; i < 5; i++)
            <String, dynamic>{
              'playerId': 'bot-$i',
              'cardCount': <int>[7, 1, 4, 0, 11][i],
              'out': i == 3,
              'finishPosition': i == 3 ? 1 : 0,
            },
        ],
        // Nine cards is a big hand, which is the case the fan has to tighten
        // for rather than run off the edge of the screen.
        'hand': <String>['AS', 'KH', 'QS', 'TD', '7C', '3H', '9S', 'JD', '2C'],
        'discards': <Map<String, dynamic>>[
          for (int i = 0; i < 8; i++)
            <String, dynamic>{
              'playerId': 'bot-0',
              'rank': '9',
              'cards': <String>['9S', '9H'],
              'atMs': 0,
            },
        ],
        'finishOrder': <String>['bot-3'],
        'lastAction': null,
        'kazhuthaId': '',
      };

  Map<String, dynamic> bluffBarState() => <String, dynamic>{
        'gameId': 'BLUFF_BAR',
        'status': 'playing',
        'currentPlayerId': 'me',
        'tableRank': 'A',
        'roundNumber': 3,
        'deckComposition': <String, dynamic>{'A': 10, 'K': 9, 'Q': 9, 'JOKER': 2},
        'players': <Map<String, dynamic>>[
          <String, dynamic>{
            'playerId': 'me', 'cardCount': 5, 'alive': true,
            'glassesRemaining': 2, 'shotsTaken': 4, 'outOfRound': false,
          },
          for (int i = 0; i < 5; i++)
            <String, dynamic>{
              'playerId': 'bot-$i',
              'cardCount': <int>[3, 0, 5, 1, 2][i],
              'alive': i != 1,
              'glassesRemaining': <int>[6, 0, 1, 4, 3][i],
              'shotsTaken': <int>[0, 6, 5, 2, 3][i],
              'outOfRound': i == 1,
            },
        ],
        'hand': <Map<String, dynamic>>[
          for (final String card in <String>['AS', 'KH', 'QD', 'X1', 'AC'])
            <String, dynamic>{'id': 'c$card', 'card': card},
        ],
        'pileCount': 7,
        'claims': <Map<String, dynamic>>[
          <String, dynamic>{'playerId': 'bot-0', 'count': 3},
          <String, dynamic>{'playerId': 'bot-2', 'count': 2},
        ],
        'lastClaim': <String, dynamic>{'playerId': 'bot-2', 'count': 2, 'atMs': 1},
        'eliminated': <String>['bot-1'],
      };

  /// A Ludo board mid-game: counters in yards, on the track, in lanes, home.
  ///
  /// Deliberately every state a counter can be in at once, because the
  /// renderer places each of them differently and a board that only ever held
  /// counters in one place would test one branch.
  Map<String, dynamic> ludoState() => <String, dynamic>{
        'gameId': 'LUDO',
        'status': 'playing',
        'currentPlayerId': 'me',
        'dice': 6,
        'order': <String>['me', 'bot-0', 'bot-1', 'bot-2'],
        'positions': <String, dynamic>{
          // In the yard, on the track, in the lane, and finished.
          'me': <int>[-1, 12, 53, 56],
          'bot-0': <int>[-1, -1, 25, 56],
          // Two on the same square, which is the stacking case.
          'bot-1': <int>[7, 7, 40, -1],
          'bot-2': <int>[51, 52, 55, 56],
        },
        'lastRoll': <String, dynamic>{'playerId': 'me', 'dice': 6, 'atMs': 1},
        'lastMove': <String, dynamic>{
          'playerId': 'bot-1', 'tokenIndex': 0, 'from': 1, 'to': 7,
          'captured': <String>['bot-0'], 'atMs': 2,
        },
      };

  Map<String, dynamic> spaceState() => <String, dynamic>{
        'gameId': 'SPACE_MYSTERY',
        'status': 'playing',
        'phase': 'station',
        'serverMs': 1000,
        'map': <String, dynamic>{
          'world': <String, dynamic>{'width': 100, 'height': 60},
          'rooms': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'cafeteria', 'name': 'Cafeteria',
              'x': 38, 'y': 22, 'width': 24, 'height': 16,
            },
            <String, dynamic>{
              'id': 'reactor', 'name': 'Reactor',
              'x': 2, 'y': 24, 'width': 16, 'height': 14,
            },
          ],
          'corridors': <Map<String, dynamic>>[
            <String, dynamic>{'x': 15, 'y': 28, 'width': 26, 'height': 6},
          ],
          'stations': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'clear-trays', 'roomId': 'cafeteria', 'name': 'Clear the trays',
              'x': 42, 'y': 26, 'durationMs': 3000,
            },
          ],
          'vents': <Map<String, dynamic>>[],
          'breachStations': <Map<String, dynamic>>[],
          'meetingTable': <String, dynamic>{'x': 50, 'y': 30},
          'playerRadius': 1.2,
        },
        'you': <String, dynamic>{
          'playerId': 'me', 'role': 'traitor', 'alive': true, 'x': 50, 'y': 30,
          'tasks': <Map<String, dynamic>>[
            <String, dynamic>{'stationId': 'clear-trays', 'done': false},
          ],
          'working': null,
          'killCooldownMs': 12000,
          'ventId': null,
          'emergenciesLeft': 1,
          'allies': <String>['bot-4'],
        },
        'players': <Map<String, dynamic>>[
          <String, dynamic>{
            'playerId': 'me', 'username': 'Bartholomew', 'isBot': false,
            'x': 50, 'y': 30, 'facing': 1, 'alive': true,
            'venting': false, 'working': false, 'role': 'traitor',
          },
          for (int i = 0; i < 5; i++)
            <String, dynamic>{
              'playerId': 'bot-$i', 'username': 'Professor Paws', 'isBot': true,
              'x': 44 + i * 2, 'y': 28, 'facing': -1, 'alive': i != 2,
              'venting': false, 'working': i == 0, 'role': null,
            },
        ],
        'seats': <String>['me', 'bot-0', 'bot-1', 'bot-2', 'bot-3', 'bot-4'],
        'bodies': <Map<String, dynamic>>[
          <String, dynamic>{'playerId': 'bot-2', 'x': 46, 'y': 31},
        ],
        'taskProgress': 0.4,
        'taskDone': 8,
        'taskTotal': 20,
        'sabotage': null,
        'meeting': null,
        'events': <Map<String, dynamic>>[],
        'result': null,
      };

  /// The same table, mid-meeting, which is a different layout entirely.
  Map<String, dynamic> spaceMeetingState() {
    final Map<String, dynamic> base = spaceState();
    base['phase'] = 'meeting';
    base['meeting'] = <String, dynamic>{
      'reason': 'body',
      'callerId': 'bot-0',
      'bodyOf': 'bot-2',
      'phase': 'voting',
      'remainingMs': 18000,
      'voted': <String>['bot-0', 'bot-1'],
      'said': <Map<String, dynamic>>[
        for (int i = 0; i < 6; i++)
          <String, dynamic>{
            'playerId': 'bot-$i',
            'text': 'I was in the reactor the whole time, I saw nobody at all.',
            'atMs': i,
          },
      ],
    };
    return base;
  }

  /// Seeds a session with a room and a match, and builds [screen] inside it.
  Widget harness({
    required GameId gameId,
    required Map<String, dynamic> state,
    required Widget screen,
  }) {
    return ProviderScope(
      overrides: <Override>[
        // The real app seeds this from disk in main(); a test has no disk.
        bootstrapSettingsProvider.overrideWithValue(AppSettings.defaults),
        selfIdProvider.overrideWithValue('me'),
        platformSessionProvider.overrideWith(
          () => _SeededSession(
            PlatformSession(
              gameId: gameId,
              room: roomFor(gameId),
              match: PlatformMatch.fromJson(<String, dynamic>{
                'matchId': 'match-1',
                'roomId': 'room-1',
                'gameId': gameId.wire,
                'status': 'playing',
                'state': state,
              }),
              // Space Mystery draws from the frame; the others from the match.
              frame: gameId == GameId.spaceMystery ? state : null,
              connection: ConnectionStatus.connected,
            ),
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: screen),
    );
  }

  /// Pumps [build] at [size] and fails if anything overflowed.
  Future<void> layout(
    WidgetTester tester,
    Size size,
    Widget Function() build,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(build());
    // Two pumps: the first builds, the second settles the entrance animations
    // that several of these screens start in `initState`.
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      tester.takeException(),
      isNull,
      reason: 'laying out at ${size.width.toInt()}x${size.height.toInt()} threw',
    );
  }

  group('Kazhutha in landscape', () {
    for (final MapEntry<String, Size> shape in shapes.entries) {
      testWidgets('lays out on a ${shape.key}', (WidgetTester tester) async {
        await layout(
          tester,
          shape.value,
          () => harness(
            gameId: GameId.kazhutha,
            state: kazhuthaState(),
            screen: const KazhuthaGameScreen(),
          ),
        );
      });
    }
  });

  group('Bluff Bar in landscape', () {
    for (final MapEntry<String, Size> shape in shapes.entries) {
      testWidgets('lays out on a ${shape.key}', (WidgetTester tester) async {
        await layout(
          tester,
          shape.value,
          () => harness(
            gameId: GameId.bluffBar,
            state: bluffBarState(),
            screen: const BluffBarGameScreen(),
          ),
        );
      });
    }
  });

  group('Ludo in landscape', () {
    for (final MapEntry<String, Size> shape in shapes.entries) {
      testWidgets('lays out on a ${shape.key}', (WidgetTester tester) async {
        // The board is square and wants the whole height, which makes this the
        // game most sensitive to a tall screen: a 20:9 phone leaves two wide
        // columns either side and a 4:3 tablet leaves almost none.
        await layout(
          tester,
          shape.value,
          () => harness(
            gameId: GameId.ludo,
            state: ludoState(),
            screen: const LudoGameScreen(),
          ),
        );

        // Ludo gets three assertions the other tables do not need, because
        // "no overflow" is a weak claim for a board game: a board scaled to a
        // quarter of the screen overflows nothing and is also unplayable.

        // One: still square. A Ludo board stretched to fill a 20:9 phone is
        // not a Ludo board — the 15x15 grid has to stay a grid.
        final Size board = tester.getSize(
          find.byWidgetPredicate(
            (Widget widget) =>
                widget is CustomPaint && widget.painter is LudoBoardPainter,
          ),
        );
        expect(
          board.width,
          closeTo(board.height, 0.5),
          reason: 'the board stopped being square at ${shape.key}',
        );

        // Two: still large. The board takes the height it is given rather
        // than everything shrinking together to make room for the side
        // columns — which is the specific failure the brief rules out.
        expect(
          board.height,
          greaterThan(shape.value.height * 0.7),
          reason: 'the board was shrunk to ${board.height} on a '
              '${shape.value.height.toInt()}-tall ${shape.key}',
        );

        // Three: the die survived the reflow. On the narrowest shapes the
        // layout moves it out of the side column and over the board rather
        // than dropping it, and a Ludo screen with no die is a dead end.
        expect(
          find.byType(LudoDie),
          findsOneWidget,
          reason: 'the die vanished at ${shape.key}',
        );
      });
    }
  });

  group('Space Mystery in landscape', () {
    for (final MapEntry<String, Size> shape in shapes.entries) {
      testWidgets('lays out on a ${shape.key}', (WidgetTester tester) async {
        await layout(
          tester,
          shape.value,
          () => harness(
            gameId: GameId.spaceMystery,
            state: spaceState(),
            screen: const SpaceMysteryGameScreen(),
          ),
        );
      });

      testWidgets('lays out a meeting on a ${shape.key}', (WidgetTester tester) async {
        // The meeting is the densest screen in the product: six seats, a
        // transcript, a timer and a footer, all at once. If anything
        // overflows anywhere, it is here and it is on the shortest device.
        await layout(
          tester,
          shape.value,
          () => harness(
            gameId: GameId.spaceMystery,
            state: spaceMeetingState(),
            screen: const SpaceMysteryGameScreen(),
          ),
        );
      });
    }
  });
}

/// A session notifier that starts from a fixed state instead of a socket.
class _SeededSession extends PlatformSessionNotifier {
  _SeededSession(this._seed);

  final PlatformSession _seed;

  @override
  PlatformSession build() => _seed;
}
