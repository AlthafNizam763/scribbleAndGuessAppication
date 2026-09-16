import 'package:scribble_guess/models/drawing_replay.dart';
import 'package:scribble_guess/models/stroke.dart';

/// Where a replay has got to, as a count of points revealed.
///
/// ## Why progress is a point count and not a timestamp
///
/// Strokes carry a `ts` — when each one *began* — but points inside a stroke
/// carry no timing at all, and adding one would have meant a third number on
/// the highest-frequency payload in the game to serve a screen nobody looks at
/// during play. So playback advances through the drawing rather than through
/// the clock: every point takes the same slice of time, and the gaps *between*
/// strokes are derived from their timestamps.
///
/// The practical effect is a replay that draws at an even hand rather than
/// reproducing the drawer's exact hesitations — which is what most people
/// picture when they imagine watching a drawing being made, and is honest
/// about the data actually stored.
class ReplayProgress {
  /// Creates a progress marker.
  const ReplayProgress({required this.strokeIndex, required this.pointIndex});

  /// How many whole strokes are already complete.
  final int strokeIndex;

  /// How many points of the stroke at [strokeIndex] are revealed.
  final int pointIndex;

  /// The very beginning.
  static const ReplayProgress start =
      ReplayProgress(strokeIndex: 0, pointIndex: 0);
}

/// Turns a [DrawingReplay] into the partial drawing visible at a given step.
///
/// Pure, and deliberately separate from the screen: the stepping rule is the
/// interesting part of this feature and is worth testing without a widget
/// tree, a ticker or a canvas.
class ReplayPlayback {
  /// Creates a playback over [replay].
  ReplayPlayback(this.replay)
      : _totalPoints = replay.pointCount,
        _prefix = _prefixCounts(replay.strokes);

  /// The drawing being played.
  final DrawingReplay replay;

  final int _totalPoints;

  /// Points completed before each stroke, so a step maps to a position in O(1)
  /// per stroke rather than by re-summing the whole drawing every frame.
  final List<int> _prefix;

  static List<int> _prefixCounts(List<Stroke> strokes) {
    final List<int> counts = <int>[0];
    int running = 0;
    for (final Stroke stroke in strokes) {
      running += stroke.points.length;
      counts.add(running);
    }
    return counts;
  }

  /// How many points the whole replay contains.
  int get totalPoints => _totalPoints;

  /// Whether there is anything to play.
  bool get isEmpty => _totalPoints == 0;

  /// How long one point takes at normal speed.
  ///
  /// Chosen so a typical turn replays in a few seconds rather than in the
  /// eighty it took to draw: a replay is a summary, not a re-enactment, and
  /// one that ran in real time would be skipped every time.
  static const Duration pointInterval = Duration(milliseconds: 8);

  /// The extra pause inserted between two strokes, at normal speed.
  ///
  /// A flat beat rather than the real gap. The stored `ts` values would give
  /// the true pause, but a drawer who stopped to think for twenty seconds
  /// would make everybody watching wait twenty seconds — so the pause is
  /// uniform and short, and the server caps the stored gaps anyway.
  static const Duration strokeGap = Duration(milliseconds: 90);

  /// The drawing as it stood after [step] points had been drawn.
  ///
  /// Returns whole strokes for everything already finished and a partial
  /// stroke for the one in progress, so the painter receives exactly the shape
  /// it draws during a live turn — no special replay rendering path.
  List<Stroke> strokesAt(int step) {
    if (_totalPoints == 0) return const <Stroke>[];

    final int clamped = step.clamp(0, _totalPoints);
    if (clamped >= _totalPoints) return replay.strokes;

    final List<Stroke> visible = <Stroke>[];

    for (int i = 0; i < replay.strokes.length; i++) {
      final int before = _prefix[i];
      if (before >= clamped) break;

      final Stroke stroke = replay.strokes[i];
      final int revealed = clamped - before;

      if (revealed >= stroke.points.length) {
        visible.add(stroke);
        continue;
      }

      // The stroke under the pen. A single revealed point still renders — the
      // painter draws a dot for a one-point stroke — so there is no flicker as
      // each stroke begins.
      visible.add(stroke.copyWithPoints(stroke.points.take(revealed).toList()));
      break;
    }

    return visible;
  }

  /// Whether [step] lands exactly on the end of a stroke.
  ///
  /// The screen uses this to insert [strokeGap], which is what makes a replay
  /// read as a series of pen strokes rather than one continuous line.
  bool isStrokeBoundary(int step) {
    if (step <= 0 || step >= _totalPoints) return false;
    // A binary search would be tidier; a drawing has at most a few hundred
    // strokes and this runs once per frame, so a scan is not worth the
    // indirection.
    return _prefix.contains(step);
  }

  /// How far through the replay [step] is, `0..1`.
  double fractionAt(int step) =>
      _totalPoints == 0 ? 1 : (step / _totalPoints).clamp(0, 1).toDouble();
}

/// The speeds the replay screen offers.
///
/// A short, fixed list rather than a slider: the useful range is narrow, and a
/// slider that could land on 1.37× would be a control nobody wants to aim.
enum ReplaySpeed {
  /// Half speed, for a drawing with fine detail.
  half(0.5, '0.5x'),

  /// The default.
  normal(1, '1x'),

  /// Twice as fast.
  double_(2, '2x'),

  /// Four times, for a long turn somebody wants the gist of.
  quadruple(4, '4x');

  const ReplaySpeed(this.multiplier, this.label);

  /// How much faster than normal this plays.
  final double multiplier;

  /// What the button reads.
  final String label;

  /// The next speed in the cycle, so one button serves all four.
  ReplaySpeed get next =>
      ReplaySpeed.values[(index + 1) % ReplaySpeed.values.length];
}
