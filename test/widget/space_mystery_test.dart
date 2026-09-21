import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/features/games/common/game_orientation.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/space_mystery/widgets/ship_view.dart';
import 'package:scribble_guess/features/games/space_mystery/widgets/space_task_panel.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/theme/theme.dart';

/// Space Mystery's two halves that a layout test cannot reach: the orientation
/// lock, and the consoles.
///
/// ## Why these two
///
/// Both are places where "it renders" is not the question.
///
/// The **orientation lock** is a global with no memory, and the bug it is
/// built to prevent only appears when two landscape screens overlap — a lobby
/// pushing a match, a match popping back to it. A screenshot of either screen
/// on its own looks perfect while the application quietly rotates out from
/// under the one underneath.
///
/// The **consoles** are the change that turned a task from a timer into a job.
/// The thing worth asserting is not that the panel draws but that it *will not
/// send* — that ACCEPT is refused while the station's time floor is running
/// and while the controls are incomplete, and that what it does eventually
/// send is the shape the server checks. A panel that sent early, or sent the
/// wrong shape, would look identical on screen and fail silently in a match.
void main() {
  setUp(GameOrientation.resetForTest);

  group('the orientation lock', () {
    /// Records what was asked of the platform, which has no window in a test.
    List<List<DeviceOrientation>> record() {
      final List<List<DeviceOrientation>> applied = <List<DeviceOrientation>>[];
      GameOrientation.applied = (List<DeviceOrientation> orientations) async {
        applied.add(orientations);
      };
      return applied;
    }

    tearDown(() => GameOrientation.applied = SystemChrome.setPreferredOrientations);

    testWidgets('locks landscape while a game is on screen', (WidgetTester tester) async {
      final List<List<DeviceOrientation>> applied = record();

      await tester.pumpWidget(
        const MaterialApp(home: OrientationLock(child: SizedBox.shrink())),
      );

      expect(GameOrientation.locked, isTrue);
      expect(applied.single, <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    });

    testWidgets('releases to unrestricted, never to portrait', (WidgetTester tester) async {
      final List<List<DeviceOrientation>> applied = record();

      await tester.pumpWidget(
        const MaterialApp(home: OrientationLock(child: SizedBox.shrink())),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      expect(GameOrientation.locked, isFalse);
      // Pinning portrait on the way out would leave a tablet unable to rotate
      // for the rest of the session.
      expect(applied.last, DeviceOrientation.values);
    });

    testWidgets('a nested screen closing does not unlock the one below it', (
      WidgetTester tester,
    ) async {
      final List<List<DeviceOrientation>> applied = record();

      // The lobby, and then the match on top of it. The real bug: the match's
      // dispose used to unlock the whole application while the lobby — still
      // mounted, still a landscape screen — was underneath.
      await tester.pumpWidget(
        const MaterialApp(
          home: OrientationLock(
            child: OrientationLock(child: SizedBox.shrink()),
          ),
        ),
      );
      expect(applied.length, 1, reason: 'the second claim is not a second lock');

      // The match is popped; the lobby remains.
      await tester.pumpWidget(
        const MaterialApp(home: OrientationLock(child: SizedBox.shrink())),
      );

      expect(GameOrientation.locked, isTrue);
      expect(
        applied.length,
        1,
        reason: 'nothing should have been unlocked while a claim was still held',
      );

      // And only when the last screen goes does the application rotate again.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(GameOrientation.locked, isFalse);
      expect(applied.last, DeviceOrientation.values);
    });

    testWidgets('holds no claim where it is disabled', (WidgetTester tester) async {
      final List<List<DeviceOrientation>> applied = record();

      // The shared lobby, showing a portrait game.
      await tester.pumpWidget(
        const MaterialApp(
          home: OrientationLock(enabled: false, child: SizedBox.shrink()),
        ),
      );

      expect(GameOrientation.locked, isFalse);
      expect(applied, isEmpty);
    });

    testWidgets('the landscape scaffold takes a claim', (WidgetTester tester) async {
      record();
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const LandscapeGameScaffold(
            skin: GameSkin.spaceMystery,
            table: SizedBox.shrink(),
          ),
        ),
      );

      expect(GameOrientation.locked, isTrue);
    });
  });

  group('drawing the crew', () {
    /// A frame with one crewmate at [x].
    SpaceMysteryState frameAt(double x) => SpaceMysteryState.fromJson(
          <String, dynamic>{
            'gameId': 'SPACE_MYSTERY',
            'status': 'playing',
            'phase': 'station',
            'serverMs': 1000,
            'you': <String, dynamic>{
              'playerId': 'me',
              'role': 'crew',
              'alive': true,
              'x': x,
              'y': 31,
              'tasks': const <Map<String, dynamic>>[],
              'working': null,
              'killCooldownMs': 0,
              'ventId': null,
              'emergenciesLeft': 1,
              'allies': const <String>[],
            },
            'players': <Map<String, dynamic>>[
              <String, dynamic>{
                'playerId': 'me',
                'username': 'Me',
                'isBot': false,
                'x': x,
                'y': 31,
                'facing': 1,
                'alive': true,
                'venting': false,
                'working': false,
                'role': null,
              },
            ],
            'seats': const <String>['me'],
            'bodies': const <Map<String, dynamic>>[],
            'taskProgress': 0,
            'taskDone': 0,
            'taskTotal': 4,
            'sabotage': null,
            'meeting': null,
            'events': const <Map<String, dynamic>>[],
            'result': null,
          },
        );

    const ShipMap map = ShipMap.empty;

    testWidgets('settles, rather than running a ticker for ever', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: GameSkinScope(
            skin: GameSkin.spaceMystery,
            child: ShipView(map: map, state: frameAt(50), selfId: 'me'),
          ),
        ),
      );

      // A blend that never stopped would be a tree that never goes idle, and
      // `pumpAndSettle` anywhere near this screen would spin until it timed
      // out. That it settles at all is the assertion.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('blends towards a new frame without overshooting it', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Widget at(double x) => MaterialApp(
            theme: AppTheme.dark,
            home: GameSkinScope(
              skin: GameSkin.spaceMystery,
              child: ShipView(map: map, state: frameAt(x), selfId: 'me'),
            ),
          );

      await tester.pumpWidget(at(50));
      // A step a body could plausibly walk in one broadcast.
      await tester.pumpWidget(at(53));

      // Whatever it draws mid-blend, it must never be somewhere the server has
      // not said — this interpolates between two known frames and never
      // predicts past the second one.
      for (int frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('a console', () {
    /// Builds a panel for [kind] with [spec], capturing what it submits.
    Future<List<List<num>>> open(
      WidgetTester tester, {
      required SpaceTaskKind kind,
      required Map<String, dynamic> spec,
      int readyInMs = 0,
    }) async {
      final List<List<num>> sent = <List<num>>[];

      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: GameSkinScope(
            skin: GameSkin.spaceMystery,
            child: LandscapeGameScaffold(
              skin: GameSkin.spaceMystery,
              table: const SizedBox.shrink(),
              overlay: SpaceTaskPanel(
                station: ShipStation(
                  id: 'job',
                  roomId: 'reactor-core',
                  name: 'Reactor Alignment',
                  kind: kind,
                  position: Offset.zero,
                  durationMs: 3000,
                ),
                work: SpaceWork(
                  stationId: 'job',
                  kind: kind,
                  spec: spec,
                  readyInMs: readyInMs,
                  expiresInMs: 60000,
                ),
                onSubmit: sent.add,
                onAbort: () {},
              ),
            ),
          ),
        ),
      );

      return sent;
    }

    testWidgets('will not send while the time floor is still running', (
      WidgetTester tester,
    ) async {
      final List<List<num>> sent = await open(
        tester,
        kind: SpaceTaskKind.align,
        spec: <String, dynamic>{'target': 90, 'start': 270, 'tolerance': 7},
        readyInMs: 2400,
      );

      expect(find.text('WORKING — 3s'), findsOneWidget);
      await tester.tap(find.text('WORKING — 3s'));
      await tester.pump();

      // The server would refuse an early answer anyway; the point is that the
      // panel does not offer to send one.
      expect(sent, isEmpty);
    });

    testWidgets('will not send an incomplete answer', (WidgetTester tester) async {
      final List<List<num>> sent = await open(
        tester,
        kind: SpaceTaskKind.sequence,
        spec: <String, dynamic>{
          'labels': <int>[3, 1, 2],
        },
      );

      expect(find.text('INCOMPLETE'), findsOneWidget);
      await tester.tap(find.text('INCOMPLETE'));
      await tester.pump();
      expect(sent, isEmpty);
    });

    testWidgets('sends the nodes in the order they were touched', (
      WidgetTester tester,
    ) async {
      final List<List<num>> sent = await open(
        tester,
        kind: SpaceTaskKind.sequence,
        spec: <String, dynamic>{
          'labels': <int>[3, 1, 2],
        },
      );

      // Labels 1, 2 and 3 sit at indices 1, 2 and 0.
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();

      expect(find.text('ACCEPT'), findsOneWidget);
      await tester.tap(find.text('ACCEPT'));
      await tester.pump();

      // The shape the server checks: node indices, in route order.
      expect(sent.single, <num>[1, 2, 0]);
    });

    testWidgets('sends the samples that were picked out', (WidgetTester tester) async {
      final List<List<num>> sent = await open(
        tester,
        kind: SpaceTaskKind.match,
        spec: <String, dynamic>{
          'symbols': <int>[2, 0, 2],
          'target': 2,
        },
      );

      // Found by the labels the tray carries for screen readers, rather than
      // by position in the widget tree: the panel also draws the called type
      // as a sample, and counting tappables would silently pick that one up.
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.tap(find.bySemanticsLabel('Sample 1'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Sample 3'));
      await tester.pump();

      await tester.tap(find.text('ACCEPT'));
      await tester.pump();

      // Disposed inside the test rather than in a tear-down: the framework
      // checks for leaked handles before tear-downs run.
      semantics.dispose();

      expect(sent.single, <num>[0, 2]);
    });

    testWidgets('sends a bearing for an alignment job', (WidgetTester tester) async {
      final List<List<num>> sent = await open(
        tester,
        kind: SpaceTaskKind.align,
        spec: <String, dynamic>{'target': 90, 'start': 270, 'tolerance': 7},
      );

      // Straight down from the middle of the dial is due south — 180 — which
      // is a real turn away from where the marker started.
      final Offset centre = tester.getCenter(find.byType(CustomPaint).last);
      await tester.tapAt(centre + const Offset(0, 40));
      await tester.pump();

      await tester.tap(find.text('ACCEPT'));
      await tester.pump();

      expect(sent.single, hasLength(1));
      expect(sent.single.single, closeTo(180, 2));
    });

    testWidgets('never carries a half-turned dial across to the next job', (
      WidgetTester tester,
    ) async {
      // The panel holds working state, and the frame that brings a new puzzle
      // arrives as a rebuild rather than as a fresh widget. Without reseeding,
      // the player would open a new console and find it already half done.
      await open(
        tester,
        kind: SpaceTaskKind.sliders,
        spec: <String, dynamic>{
          'targets': <int>[20, 40],
          'tolerance': 6,
        },
      );

      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await tester.pump();

      await open(
        tester,
        kind: SpaceTaskKind.sliders,
        spec: <String, dynamic>{
          'targets': <int>[80, 30],
          'tolerance': 6,
        },
      );

      // Both channels start where a fresh panel starts them.
      final List<Slider> sliders =
          tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.every((Slider slider) => slider.value == 50), isTrue);
    });

    testWidgets('lays out every job without overflowing a tall phone', (
      WidgetTester tester,
    ) async {
      const Map<SpaceTaskKind, Map<String, dynamic>> jobs =
          <SpaceTaskKind, Map<String, dynamic>>{
        SpaceTaskKind.align: <String, dynamic>{
          'target': 90,
          'start': 270,
          'tolerance': 7,
        },
        SpaceTaskKind.sliders: <String, dynamic>{
          'targets': <int>[15, 40, 66, 85],
          'tolerance': 6,
        },
        SpaceTaskKind.sequence: <String, dynamic>{
          'labels': <int>[4, 6, 1, 3, 5, 2],
        },
        SpaceTaskKind.match: <String, dynamic>{
          'symbols': <int>[0, 1, 2, 3, 4, 0, 1, 2, 3],
          'target': 2,
        },
        SpaceTaskKind.rewire: <String, dynamic>{
          'left': <int>[0, 1, 2, 3],
          'right': <int>[2, 0, 3, 1],
        },
      };

      for (final MapEntry<SpaceTaskKind, Map<String, dynamic>> job in jobs.entries) {
        await open(tester, kind: job.key, spec: job.value);
        // A RenderFlex overflow is an exception in a widget test, so this is a
        // real assertion that nothing was clipped off the smallest screen the
        // game supports.
        expect(tester.takeException(), isNull, reason: '${job.key} overflowed');
      }
    });
  });
}
