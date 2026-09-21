import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/features/home/home_screen.dart';
import 'package:scribble_guess/models/discovered_room.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';

/// What the hub must draw, and what it must not invent.
///
/// ## Why these particular assertions
///
/// The hub is the screen most likely to be restyled again, and a restyle is
/// exactly the edit that quietly turns a real number into a good-looking
/// constant. Three of the four groups below are about that: the head count on
/// a game card is the server's open rooms added up, the level and the XP line
/// are the server's progression, and a game nobody is playing gets no crowd
/// badge at all. The fourth pins the filter, which is the only behaviour on
/// this screen that is neither a provider read nor a navigation.
///
/// ## Why nothing is tapped except a chip
///
/// There is no router in the host, and every other control on the hub
/// navigates. A tap on one would be a test of go_router rather than of this
/// screen; the filter chip is the one control that changes what this screen
/// draws.
void main() {
  /// Pumps [widget] on a tall, narrow surface.
  ///
  /// Narrow because 400pt is the phone this layout has to survive; tall
  /// because a [ListView] builds only what is on screen, and these assertions
  /// are about the whole hub rather than about its first 600 points.
  Future<void> pumpHub(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(400, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  DiscoveredRoom room({
    required GameId game,
    required String name,
    int players = 3,
    int maxPlayers = 6,
  }) => DiscoveredRoom(
    gameId: game,
    gameName: GameCatalog.byId(game).displayName,
    roomId: 'r-$name',
    code: 'ABCD',
    name: name,
    hostName: 'Host',
    playerCount: players,
    maxPlayers: maxPlayers,
  );

  Widget hub({
    List<DiscoveredRoom> rooms = const <DiscoveredRoom>[],
    Progression progression = const Progression(),
    PlayerProfile? profile = const PlayerProfile(id: 'p1', name: 'Nizam'),
    double textScale = 1,
  }) => ProviderScope(
    overrides: <Override>[
      bootstrapProfileProvider.overrideWithValue(profile),
      connectionProvider.overrideWithValue(ConnectionStatus.connected),
      pendingInvitationCountProvider.overrideWithValue(2),
      unreadNotificationCountProvider.overrideWithValue(0),
      progressionProvider.overrideWith(() => _FixedProgression(progression)),
      roomDiscoveryProvider.overrideWith(
        () => _FixedRooms(RoomDiscoveryPage(items: rooms)),
      ),
      myWorldRankProvider.overrideWith(
        (Ref ref) async => (rank: 12, total: 400, entry: null),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppTextDelegate(),
      ],
      // Reduced motion, for two reasons at once: it is the branch that stops
      // the live dot's perpetual pulse — and an animation that never ends is
      // one `pumpAndSettle` waits for forever — and it makes every assertion
      // below double as a check that the hub renders with animation off.
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: const HomeScreen(),
    ),
  );

  group('the slab', () {
    testWidgets('carries the player, their level and their XP', (
      WidgetTester tester,
    ) async {
      await pumpHub(
        tester,
        hub(
          progression: const Progression(
            level: PlayerLevel(
              level: 7,
              title: 'Doodler',
              xp: 1200,
              xpIntoLevel: 120,
              xpForNextLevel: 400,
              progress: 0.3,
            ),
          ),
        ),
      );

      expect(find.text('Nizam'), findsOneWidget);
      expect(find.text('Doodler'), findsOneWidget);
      // The header pill and the badge on the avatar read the same level, which
      // is the whole reason there is one widget for it.
      expect(find.text('LVL 7'), findsNWidgets(2));
      expect(find.text('120 / 400 XP'), findsOneWidget);
      expect(find.text('280 XP to level 8'), findsOneWidget);
      expect(find.text('Global #12'), findsOneWidget);
      expect(find.text('QUICK PARTY MATCH'), findsOneWidget);
    });

    testWidgets('survives having no profile yet', (WidgetTester tester) async {
      await pumpHub(tester, hub(profile: null));

      expect(find.text('Player'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the head count', () {
    testWidgets('adds up the open rooms, per game and overall', (
      WidgetTester tester,
    ) async {
      await pumpHub(
        tester,
        hub(
          rooms: <DiscoveredRoom>[
            room(game: GameId.ludo, name: 'Board night', players: 3),
            room(game: GameId.ludo, name: 'Second table', players: 2),
            room(game: GameId.kazhutha, name: 'Cards', players: 4),
          ],
        ),
      );

      // Ludo's two rooms are one badge of five; the slab counts every room on
      // the screen, so it reads nine.
      expect(find.text('9 playing'), findsOneWidget);
      expect(find.text('5 playing'), findsOneWidget);
      expect(find.text('4 playing'), findsOneWidget);
    });

    testWidgets('gives a game with no rooms no crowd at all', (
      WidgetTester tester,
    ) async {
      await pumpHub(tester, hub());

      expect(find.textContaining('playing'), findsNothing);
    });
  });

  group('the catalogue', () {
    testWidgets('lists every game, and narrows to the chosen filter', (
      WidgetTester tester,
    ) async {
      await pumpHub(tester, hub());

      expect(find.byType(GameCard), findsNWidgets(GameCatalog.all.length));

      // Cards rather than Board, only because the Board chip sits off the
      // right edge of a 400pt strip and this test is about the filter, not
      // about scrolling it.
      await tester.tap(find.text(GameFilter.cards.label));
      await tester.pumpAndSettle();

      expect(find.byType(GameCard), findsNWidgets(2));
      expect(find.text('KAZHUTHA'), findsOneWidget);
      expect(find.text('BLUFF BAR'), findsOneWidget);
      expect(find.text('LUDO'), findsNothing);
    });
  });

  group('the bar', () {
    testWidgets('offers the five destinations, with invites badged', (
      WidgetTester tester,
    ) async {
      await pumpHub(tester, hub());

      for (final HubTab tab in HubTab.values) {
        expect(find.text(tab.label), findsOneWidget);
      }
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('the layout', () {
    testWidgets('does not overflow a narrow phone at large text', (
      WidgetTester tester,
    ) async {
      // 400pt wide with everything a third larger is where a row of five tabs,
      // a header carrying a wordmark and three controls, and a card with two
      // long buttons on it all stop fitting. Nothing here asserts a string:
      // the assertion is that no render object complained.
      await pumpHub(
        tester,
        hub(
          textScale: 1.3,
          rooms: <DiscoveredRoom>[
            room(game: GameId.scribbleGuess, name: 'A room with a long name'),
          ],
          progression: const Progression(
            level: PlayerLevel(level: 24, title: 'Master Scribbler'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}

/// Progression, fixed, without the API underneath it.
class _FixedProgression extends ProgressionNotifier {
  _FixedProgression(this._value);

  final Progression _value;

  @override
  Future<Progression> build() async => _value;
}

/// Quick Match, fixed, without the API underneath it.
class _FixedRooms extends RoomDiscoveryNotifier {
  _FixedRooms(this._value);

  final RoomDiscoveryPage _value;

  @override
  Future<RoomDiscoveryPage> build() async => _value;
}
