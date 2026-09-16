import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/utils/replay_stream.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/drawing_board.dart';
import 'package:scribble_guess/models/drawing_event.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';
import 'package:scribble_guess/repositories/impl/socket_drawing_repository.dart';

import '../support/fake_gateway.dart';

/// Replays [events] onto a board the way `BoardNotifier` does, so a test can
/// assert on the picture rather than on the event log.
DrawingBoard applyAll(Iterable<DrawingEvent> events) {
  DrawingBoard board = DrawingBoard.empty;
  for (final DrawingEvent event in events) {
    board = switch (event) {
      StrokeBegan(:final Stroke stroke) => board.addStroke(stroke),
      StrokeAppended(:final String strokeId, :final List<StrokePoint> points) =>
        _append(board, strokeId, points),
      StrokeEnded() => board,
      StrokeUndone(:final String strokeId) => board.undo(strokeId),
      StrokeRedone(:final Stroke stroke) => board.redo(stroke),
      BoardCleared() => board.clear(),
      BoardSnapshot(:final List<Stroke> strokes) =>
        DrawingBoard(strokes: strokes),
    };
  }
  return board;
}

DrawingBoard _append(
  DrawingBoard board,
  String strokeId,
  List<StrokePoint> points,
) {
  final int index = board.strokes.indexWhere((Stroke s) => s.id == strokeId);
  if (index < 0) {
    return board;
  }
  final Stroke existing = board.strokes[index];
  return board.replaceStroke(
    existing.copyWithPoints(<StrokePoint>[...existing.points, ...points]),
  );
}

Stroke _stroke(String id) => Stroke(
      id: id,
      authorId: 'me',
      points: const <StrokePoint>[StrokePoint(x: 0.1, y: 0.1)],
      colorValue: 0xFF112233,
      width: 6,
      timestampMs: 1,
    );

void main() {
  group('the drawer sees their own strokes', () {
    late FakeGateway gateway;
    late SocketDrawingRepository repository;
    late List<DrawingEvent> observed;
    late StreamSubscription<DrawingEvent> subscription;

    setUp(() {
      gateway = FakeGateway();
      repository = SocketDrawingRepository(gateway);
      observed = <DrawingEvent>[];
      subscription = repository.events.listen(observed.add);
    });

    tearDown(() async {
      await subscription.cancel();
      repository.dispose();
      gateway.dispose();
    });

    test('a finished stroke survives on the board without a server echo',
        () async {
      // The whole bug in one test. The server never sends the drawer their own
      // stroke back, so if the repository does not mirror it locally the board
      // stays empty and the drawing disappears the instant the live preview is
      // dropped.
      final Stroke stroke = _stroke('s1');

      await repository.beginStroke(stroke);
      await repository.appendPoints(
        's1',
        const <StrokePoint>[StrokePoint(x: 0.2, y: 0.2), StrokePoint(x: 0.3, y: 0.3)],
      );
      await repository.endStroke('s1');
      await pumpEventQueue();

      final DrawingBoard board = applyAll(observed);
      expect(board.strokes, hasLength(1));
      expect(board.strokes.single.id, 's1');
      expect(board.strokes.single.points, hasLength(3));
    });

    test('the stroke is not duplicated when points arrive in several batches',
        () async {
      await repository.beginStroke(_stroke('s1'));
      for (int i = 0; i < 20; i++) {
        await repository.appendPoints(
          's1',
          <StrokePoint>[StrokePoint(x: i / 20, y: i / 20)],
        );
      }
      await pumpEventQueue();

      final DrawingBoard board = applyAll(observed);
      expect(board.strokes, hasLength(1));
      // One from `begin`, twenty appended: nothing lost during a fast scribble.
      expect(board.strokes.single.points, hasLength(21));
    });

    test('rapid strokes keep their order', () async {
      for (final String id in <String>['a', 'b', 'c']) {
        await repository.beginStroke(_stroke(id));
      }
      await pumpEventQueue();

      final DrawingBoard board = applyAll(observed);
      expect(
        board.strokes.map((Stroke s) => s.id).toList(),
        <String>['a', 'b', 'c'],
      );
    });

    test('every local operation is still sent to the server', () async {
      await repository.beginStroke(_stroke('s1'));
      await repository.appendPoints('s1', const <StrokePoint>[StrokePoint(x: 0.5, y: 0.5)]);
      await repository.endStroke('s1');

      expect(
        gateway.sent.map((({String event, Map<String, dynamic> data}) m) => m.event),
        <String>[
          SocketEvents.clientDrawBegin,
          SocketEvents.clientDrawAppend,
          SocketEvents.clientDrawEnd,
        ],
      );
    });

    test('nothing is echoed when the transport refused it', () async {
      // An optimistic echo of a stroke that never left the device would put a
      // line on this board that no other player can see.
      gateway.goOffline();

      final Result<void> outcome = await repository.beginStroke(_stroke('s1'));
      await pumpEventQueue();

      expect(outcome, isA<Err<void>>());
      expect(observed, isEmpty);
    });

    test('undo, redo and clear wait for the server to decide', () async {
      // The server picks which stroke moves, so applying these locally would be
      // a guess. They are sent and nothing else happens until it answers.
      await repository.beginStroke(_stroke('s1'));
      await pumpEventQueue();
      observed.clear();

      await repository.undo();
      await repository.clear();
      await pumpEventQueue();

      expect(observed, isEmpty);
      expect(
        gateway.sent.map((({String event, Map<String, dynamic> data}) m) => m.event),
        containsAllInOrder(<String>[
          SocketEvents.clientDrawUndo,
          SocketEvents.clientDrawClear,
        ]),
      );
    });

    test('the server undo removes the drawer stroke once it arrives', () async {
      await repository.beginStroke(_stroke('s1'));
      await pumpEventQueue();

      gateway.push(SocketEvents.serverDrawUndo, <String, dynamic>{'strokeId': 's1'});
      await pumpEventQueue();

      expect(applyAll(observed).strokes, isEmpty);
    });

    test('a remote stroke and a local one live on the same board', () async {
      await repository.beginStroke(_stroke('mine'));
      gateway.push(SocketEvents.serverDrawBegin, <String, dynamic>{
        'stroke': <String, dynamic>{
          'id': 'theirs',
          'a': 'somebody-else',
          'p': <List<double>>[
            <double>[0.4, 0.4],
          ],
        },
      });
      await pumpEventQueue();

      expect(
        applyAll(observed).strokes.map((Stroke s) => s.id).toList(),
        <String>['mine', 'theirs'],
      );
    });

    test('a snapshot replaces whatever the board had, which is the repair path',
        () async {
      await repository.beginStroke(_stroke('stale'));
      await pumpEventQueue();

      gateway.push(SocketEvents.serverDrawSnapshot, <String, dynamic>{
        'strokes': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'authoritative',
            'a': 'me',
            'p': <List<double>>[
              <double>[0.1, 0.2],
            ],
          },
        ],
      });
      await pumpEventQueue();

      final DrawingBoard board = applyAll(observed);
      expect(board.strokes, hasLength(1));
      expect(board.strokes.single.id, 'authoritative');
    });
  });

  group('replaying', () {
    test('hands the cached value to a listener that arrives late', () async {
      final StreamController<int> source = StreamController<int>.broadcast();
      int? latest;
      final Stream<int> stream = replaying<int>(source, () => latest);

      latest = 7;
      source.add(7);

      // Subscribing only now is the situation a screen is in when the push that
      // caused it to open arrived before it was built.
      expect(await stream.first, 7);

      await source.close();
    });

    test('loses nothing added in the same turn as the subscription', () async {
      // The `async*` version of this helper dropped exactly this value: it
      // suspended on its first yield and had not yet attached to the source.
      final StreamController<int> source = StreamController<int>.broadcast();
      int? latest;
      final List<int> seen = <int>[];

      final StreamSubscription<int> subscription =
          replaying<int>(source, () => latest).listen(seen.add);
      latest = 1;
      source.add(1);

      await pumpEventQueue();
      expect(seen, <int>[1]);

      await subscription.cancel();
      await source.close();
    });

    test('replays nothing when there is nothing cached yet', () async {
      final StreamController<int> source = StreamController<int>.broadcast();
      final List<int> seen = <int>[];

      final StreamSubscription<int> subscription =
          replaying<int>(source, () => null).listen(seen.add);
      await pumpEventQueue();

      expect(seen, isEmpty);

      await subscription.cancel();
      await source.close();
    });

    test('serves every listener independently', () async {
      final StreamController<int> source = StreamController<int>.broadcast();
      int? latest = 5;
      final Stream<int> stream = replaying<int>(source, () => latest);

      final List<int> first = <int>[];
      final StreamSubscription<int> a = stream.listen(first.add);
      await pumpEventQueue();

      latest = 6;
      final List<int> second = <int>[];
      final StreamSubscription<int> b = stream.listen(second.add);
      await pumpEventQueue();

      expect(first, <int>[5]);
      expect(second, <int>[6]);

      await a.cancel();
      await b.cancel();
      await source.close();
    });
  });
}
