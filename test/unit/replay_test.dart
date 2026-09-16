import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/features/replay/replay_playback.dart';
import 'package:scribble_guess/models/drawing_replay.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';

/// Replay playback: the stepping rule, and the wire format it plays.
///
/// ## Why the stepping rule is tested and not the screen
///
/// The interesting part of this feature is turning "N points revealed" into a
/// partial drawing, and it has exactly the properties a screen makes hard to
/// check: it must produce whole strokes for everything finished, one partial
/// stroke for the one in progress, never a stroke out of order, and the
/// complete drawing at the end. [ReplayPlayback] is pure so all of that can be
/// asserted without a ticker, a canvas or a widget tree.
void main() {
  /// A freehand stroke of [count] points.
  Stroke freehand(String id, int count) => Stroke(
        id: id,
        authorId: 'drawer-1',
        points: <StrokePoint>[
          for (int i = 0; i < count; i++) StrokePoint(x: i / count, y: 0.5),
        ],
      );

  DrawingReplay replayOf(List<Stroke> strokes) => DrawingReplay(
        summary: const ReplaySummary(
          turnNumber: 1,
          roundNumber: 1,
          drawerName: 'Ana',
          word: 'guitar',
        ),
        strokes: strokes,
      );

  group('ReplayPlayback stepping', () {
    test('shows nothing at the start', () {
      final ReplayPlayback playback =
          ReplayPlayback(replayOf(<Stroke>[freehand('a', 5)]));

      expect(playback.strokesAt(0), isEmpty);
    });

    test('reveals the first stroke point by point', () {
      final ReplayPlayback playback =
          ReplayPlayback(replayOf(<Stroke>[freehand('a', 5)]));

      expect(playback.strokesAt(1).single.points, hasLength(1));
      expect(playback.strokesAt(3).single.points, hasLength(3));
      expect(playback.strokesAt(5).single.points, hasLength(5));
    });

    /// The property that makes the replay look like drawing rather than like a
    /// slideshow: completed strokes are whole, and exactly one is partial.
    test('keeps earlier strokes whole while the current one fills in', () {
      final ReplayPlayback playback = ReplayPlayback(
        replayOf(<Stroke>[freehand('a', 4), freehand('b', 6)]),
      );

      final List<Stroke> midway = playback.strokesAt(7);

      expect(midway, hasLength(2));
      expect(midway.first.points, hasLength(4));
      expect(midway.last.points, hasLength(3));
    });

    test('returns the complete drawing at the end', () {
      final DrawingReplay replay =
          replayOf(<Stroke>[freehand('a', 4), freehand('b', 6)]);
      final ReplayPlayback playback = ReplayPlayback(replay);

      expect(playback.strokesAt(playback.totalPoints), same(replay.strokes));
    });

    test('clamps a step past the end rather than overrunning', () {
      final ReplayPlayback playback =
          ReplayPlayback(replayOf(<Stroke>[freehand('a', 4)]));

      expect(playback.strokesAt(9999), hasLength(1));
      expect(playback.strokesAt(-5), isEmpty);
    });

    test('preserves drawing order', () {
      final ReplayPlayback playback = ReplayPlayback(
        replayOf(<Stroke>[freehand('a', 2), freehand('b', 2), freehand('c', 2)]),
      );

      expect(
        playback.strokesAt(5).map((Stroke s) => s.id),
        <String>['a', 'b', 'c'],
      );
    });

    test('counts every point across every stroke', () {
      final ReplayPlayback playback = ReplayPlayback(
        replayOf(<Stroke>[freehand('a', 4), freehand('b', 6)]),
      );

      expect(playback.totalPoints, 10);
    });
  });

  group('stroke boundaries', () {
    test('marks where one stroke ends and the next begins', () {
      final ReplayPlayback playback = ReplayPlayback(
        replayOf(<Stroke>[freehand('a', 4), freehand('b', 6)]),
      );

      expect(playback.isStrokeBoundary(4), isTrue);
      expect(playback.isStrokeBoundary(3), isFalse);
      expect(playback.isStrokeBoundary(5), isFalse);
    });

    /// Neither end is a boundary: there is no pause to insert before the first
    /// stroke or after the last.
    test('does not mark the start or the end', () {
      final ReplayPlayback playback = ReplayPlayback(
        replayOf(<Stroke>[freehand('a', 4), freehand('b', 6)]),
      );

      expect(playback.isStrokeBoundary(0), isFalse);
      expect(playback.isStrokeBoundary(10), isFalse);
    });
  });

  group('progress', () {
    test('runs from nothing to everything', () {
      final ReplayPlayback playback =
          ReplayPlayback(replayOf(<Stroke>[freehand('a', 10)]));

      expect(playback.fractionAt(0), 0);
      expect(playback.fractionAt(5), 0.5);
      expect(playback.fractionAt(10), 1);
    });

    /// A drawing with nothing in it reports a full bar rather than dividing by
    /// zero — the screen shows its "nobody drew anything" fallback instead.
    test('reports a full bar for an empty drawing', () {
      final ReplayPlayback playback = ReplayPlayback(replayOf(<Stroke>[]));

      expect(playback.isEmpty, isTrue);
      expect(playback.fractionAt(0), 1);
      expect(playback.strokesAt(0), isEmpty);
    });
  });

  group('ReplaySpeed', () {
    test('cycles through every speed and back to the start', () {
      ReplaySpeed speed = ReplaySpeed.normal;
      final Set<ReplaySpeed> seen = <ReplaySpeed>{};

      for (int i = 0; i < ReplaySpeed.values.length; i++) {
        seen.add(speed);
        speed = speed.next;
      }

      expect(seen, ReplaySpeed.values.toSet());
      expect(speed, ReplaySpeed.normal);
    });

    test('gives every speed a positive multiplier and a label', () {
      for (final ReplaySpeed speed in ReplaySpeed.values) {
        expect(speed.multiplier, greaterThan(0));
        expect(speed.label, isNotEmpty);
      }
    });
  });

  group('DrawingReplay wire format', () {
    test('parses a replay with its summary and strokes', () {
      final DrawingReplay replay = DrawingReplay.fromJson(const <String, dynamic>{
        'turnNumber': 3,
        'roundNumber': 2,
        'drawerId': 'u-1',
        'drawerName': 'Ana',
        'word': 'guitar',
        'durationMs': 80000,
        'correctGuessers': 2,
        'strokeCount': 1,
        'compacted': true,
        'endedAtMs': 1700000000000,
        'strokes': <dynamic>[
          <String, dynamic>{
            'id': 's-1',
            'a': 'u-1',
            'p': <dynamic>[
              <double>[0.1, 0.1],
              <double>[0.2, 0.2],
            ],
            'c': 0xFF1A1A1A,
            'w': 4,
            't': 'pen',
            'ts': 1700000000000,
          },
        ],
      });

      expect(replay.summary.word, 'guitar');
      expect(replay.summary.drawerName, 'Ana');
      expect(replay.summary.compacted, isTrue);
      expect(replay.strokes, hasLength(1));
      expect(replay.strokes.single.tool, DrawTool.pen);
      expect(replay.pointCount, 2);
    });

    /// A turn nobody drew in is a real outcome, not a failure: the screen
    /// keys off `isEmpty` to show its fallback rather than an error.
    test('reads a turn with no drawing as empty', () {
      final DrawingReplay replay = DrawingReplay.fromJson(const <String, dynamic>{
        'turnNumber': 1,
        'word': 'guitar',
        'strokes': <dynamic>[],
      });

      expect(replay.isEmpty, isTrue);
      expect(replay.summary.word, 'guitar');
    });

    test('drops a stroke with no points rather than rendering nothing for it', () {
      final DrawingReplay replay = DrawingReplay.fromJson(const <String, dynamic>{
        'turnNumber': 1,
        'strokes': <dynamic>[
          <String, dynamic>{'id': 'empty', 'p': <dynamic>[]},
          'not a map',
        ],
      });

      expect(replay.strokes, isEmpty);
    });

    test('survives a response with nothing in it', () {
      final DrawingReplay replay =
          DrawingReplay.fromJson(const <String, dynamic>{});

      expect(replay.isEmpty, isTrue);
      expect(replay.summary.isEmpty, isTrue);
    });
  });

  group('ReplaySummary', () {
    test('knows whether there is a drawing to play', () {
      expect(const ReplaySummary(turnNumber: 1, strokeCount: 3).hasDrawing, isTrue);
      expect(const ReplaySummary(turnNumber: 1).hasDrawing, isFalse);
    });
  });
}
