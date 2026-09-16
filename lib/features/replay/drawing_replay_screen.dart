import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/features/replay/replay_playback.dart';
import 'package:scribble_guess/models/drawing_board.dart';
import 'package:scribble_guess/models/drawing_replay.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Plays back one finished turn, stroke by stroke.
///
/// ## The canvas is the live one
///
/// Playback hands [DrawingCanvas] a partial stroke list and it renders exactly
/// as it does during a turn — same painter, same tools, same smoothing. There
/// is no replay-specific rendering path, which is what guarantees a replay
/// looks like what the room actually saw.
///
/// ## Three states, and the middle one matters
///
/// A replay can load and be *empty*: a turn where the drawer never drew is a
/// real outcome, not a failure, and it gets its own message rather than an
/// error or a blank canvas. That is the fallback the brief asks for.
class DrawingReplayScreen extends ConsumerStatefulWidget {
  /// Creates the screen for one turn of one match.
  const DrawingReplayScreen({
    required this.gameId,
    required this.turnNumber,
    super.key,
  });

  /// Which match.
  final String gameId;

  /// Which turn of it.
  final int turnNumber;

  @override
  ConsumerState<DrawingReplayScreen> createState() =>
      _DrawingReplayScreenState();
}

class _DrawingReplayScreenState extends ConsumerState<DrawingReplayScreen> {
  /// How many points of the drawing are revealed.
  int _step = 0;

  bool _playing = true;
  ReplaySpeed _speed = ReplaySpeed.normal;
  bool _sharing = false;

  Timer? _timer;

  /// The boundary rasterised when the drawing is shared.
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------- playback ---

  /// Schedules the next point.
  ///
  /// A one-shot timer per point rather than a periodic one, because the
  /// interval is not constant: a point that lands on a stroke boundary is
  /// followed by a pause, which is what makes the replay read as a series of
  /// pen strokes rather than one continuous line.
  void _schedule(ReplayPlayback playback) {
    _timer?.cancel();

    if (!_playing || _step >= playback.totalPoints) return;

    final bool boundary = playback.isStrokeBoundary(_step);
    final int base = ReplayPlayback.pointInterval.inMicroseconds +
        (boundary ? ReplayPlayback.strokeGap.inMicroseconds : 0);

    _timer = Timer(
      Duration(microseconds: (base / _speed.multiplier).round()),
      () {
        if (!mounted) return;
        setState(() => _step = _step + 1);
        _schedule(playback);
      },
    );
  }

  void _togglePlay(ReplayPlayback playback) {
    setState(() {
      // Playing from the end restarts, which is what the button obviously
      // means when the replay has finished and the only control is Play.
      if (!_playing && _step >= playback.totalPoints) _step = 0;
      _playing = !_playing;
    });
    _schedule(playback);
  }

  void _restart(ReplayPlayback playback) {
    setState(() {
      _step = 0;
      _playing = true;
    });
    _schedule(playback);
  }

  void _cycleSpeed(ReplayPlayback playback) {
    setState(() => _speed = _speed.next);
    // Re-scheduled so the change takes effect on the next point rather than
    // after the one already in flight.
    _schedule(playback);
  }

  void _seek(double fraction, ReplayPlayback playback) {
    setState(() {
      _step = (fraction * playback.totalPoints).round();
      _playing = false;
    });
    _timer?.cancel();
  }

  // -------------------------------------------------------------- share ---

  /// Rasterises the canvas and hands the PNG to the platform share sheet.
  ///
  /// The share sheet is also how a player *saves* it — "Save to Photos" and
  /// "Save to Files" are entries in it — so one action serves both of the
  /// brief's asks without a gallery-write permission.
  Future<void> _share(DrawingReplay replay) async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final RenderObject? object =
          _boundaryKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;

      // 3x so the shared image is legible rather than a screen-sized thumbnail.
      final ui.Image image = await object.toImage(pixelRatio: 3);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;

      final Directory directory = await getTemporaryDirectory();
      final File file = File(
        '${directory.path}/scribble-${replay.summary.turnNumber}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          text: '"${replay.summary.word}" by ${replay.summary.drawerName}',
        ),
      );
    } catch (error, stackTrace) {
      // Sharing is a side errand: a failure here must not take down the
      // replay the player is watching.
      AppLogger.w('Replay: share failed', error, stackTrace);
      if (mounted) {
        notify(context, context.l10n.replayShareFailed, isError: true);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // --------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DrawingReplay> replay = ref.watch(
      replayProvider((gameId: widget.gameId, turnNumber: widget.turnNumber)),
    );

    return SketchScaffold(
      title: context.l10n.replayTitle,
      child: replay.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => SketchEmptyState(
          message: error is Failure ? error.message : context.l10n.replayUnavailable,
          icon: Icons.movie_outlined,
          action: SketchButton(
            label: context.l10n.retry,
            onPressed: () => ref.invalidate(
              replayProvider(
                (gameId: widget.gameId, turnNumber: widget.turnNumber),
              ),
            ),
          ),
        ),
        data: _buildReplay,
      ),
    );
  }

  Widget _buildReplay(DrawingReplay replay) {
    // A turn nobody drew in. A real outcome rather than an error, so it gets
    // the word and the drawer it would otherwise have shown, and says plainly
    // that there is nothing to play.
    if (replay.isEmpty) {
      return Column(
        children: <Widget>[
          _Header(summary: replay.summary),
          Expanded(
            child: SketchEmptyState(
              message: context.l10n.replayNoDrawing,
              icon: Icons.brush_outlined,
            ),
          ),
        ],
      );
    }

    final ReplayPlayback playback = ReplayPlayback(replay);

    // Kicked off on the first build. Cheap to call repeatedly: it cancels the
    // outstanding timer before scheduling, so a rebuild cannot stack timers.
    if (_playing && _timer == null && _step < playback.totalPoints) {
      _schedule(playback);
    }

    final List<Stroke> visible = playback.strokesAt(_step);

    return Column(
      children: <Widget>[
        _Header(summary: replay.summary),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: DrawingCanvas(
                board: DrawingBoard(strokes: visible),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Controls(
          playing: _playing,
          speed: _speed,
          sharing: _sharing,
          fraction: playback.fractionAt(_step),
          onPlayPause: () => _togglePlay(playback),
          onRestart: () => _restart(playback),
          onSpeed: () => _cycleSpeed(playback),
          onSeek: (double value) => _seek(value, playback),
          onShare: () => _share(replay),
        ),
      ],
    );
  }
}

/// The word, the drawer, and a note if the drawing was thinned.
class _Header extends StatelessWidget {
  const _Header({required this.summary});

  final ReplaySummary summary;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.replayWord.toUpperCase(),
          style: text.labelSmall?.copyWith(color: colors.inkSoft),
        ),
        Text(
          summary.word,
          style: text.headlineSmall?.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${context.l10n.replayDrawnBy} ${summary.drawerName}',
          style: text.bodySmall?.copyWith(color: colors.inkSoft),
        ),
        if (summary.compacted) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.replayCompacted,
            style: text.labelSmall?.copyWith(color: colors.inkFaint),
          ),
        ],
      ],
    );
  }
}

/// Play/pause, restart, speed, scrub and share.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.playing,
    required this.speed,
    required this.sharing,
    required this.fraction,
    required this.onPlayPause,
    required this.onRestart,
    required this.onSpeed,
    required this.onSeek,
    required this.onShare,
  });

  final bool playing;
  final ReplaySpeed speed;
  final bool sharing;
  final double fraction;
  final VoidCallback onPlayPause;
  final VoidCallback onRestart;
  final VoidCallback onSpeed;
  final ValueChanged<double> onSeek;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Slider(value: fraction, onChanged: onSeek),
        Row(
          children: <Widget>[
            SketchButton(
              label: playing ? context.l10n.replayPause : context.l10n.replayPlay,
              icon: playing ? Icons.pause : Icons.play_arrow,
              variant: SketchButtonVariant.primary,
              onPressed: onPlayPause,
            ),
            const SizedBox(width: AppSpacing.sm),
            SketchButton(
              label: context.l10n.replayRestart,
              icon: Icons.replay,
              onPressed: onRestart,
            ),
            const SizedBox(width: AppSpacing.sm),
            // One button cycling four speeds, rather than four buttons or a
            // slider nobody wants to aim at 1.37x.
            SketchButton(
              label: speed.label,
              icon: Icons.speed,
              onPressed: onSpeed,
            ),
            const Spacer(),
            SketchButton(
              label: context.l10n.replayShare,
              icon: Icons.ios_share,
              busy: sharing,
              onPressed: onShare,
            ),
          ],
        ),
      ],
    );
  }
}
