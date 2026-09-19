import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/id_generator.dart';
import 'package:scribble_guess/core/utils/responsive.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/features/game/widgets/drawing_toolbar.dart';
import 'package:scribble_guess/features/game/widgets/word_choice_sheet.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/drawing_board.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/repositories/repositories.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The match: canvas, word, timer, scoreboard and chat.
///
/// The same screen serves the drawer and the guessers; the only difference is
/// whether the canvas takes input and whether the word is legible.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  /// The stroke under the finger, before it is committed to the board.
  ///
  /// A [ValueNotifier] rather than plain state, because this changes on every
  /// pointer move — about sixty times a second while a finger is down. Driving
  /// it through `setState` rebuilt the entire game screen at that rate: the
  /// header, the scoreboard, the chat panel and the toolbar, none of which had
  /// changed. Only the canvas listens now, so a drag rebuilds one widget.
  final ValueNotifier<Stroke?> _pending = ValueNotifier<Stroke?>(null);

  /// Points captured since the last flush.
  final List<StrokePoint> _buffer = <StrokePoint>[];

  /// Batches point traffic so a fast scribble does not emit a packet per
  /// pixel. Points still render locally at full rate.
  Timer? _flushTimer;

  /// The turn whose word sheet is open or has already been answered.
  ///
  /// Word selection is driven from the authoritative game state rather than
  /// from a one-shot event, so the sheet has to be idempotent: the state that
  /// asks for it is re-sent on every hint, every score change and every
  /// reconnect. This key is what turns "the room is choosing a word" into "and
  /// this device has not dealt with it yet".
  String? _wordSheetTurn;

  /// Whether a results route pushed from here is still on the stack.
  bool _resultOpen = false;

  @override
  void dispose() {
    _flushTimer?.cancel();
    // A notifier left undisposed keeps its listeners alive with it, which is
    // the ordinary way a closed screen stays in memory.
    _pending.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ drawing ---

  /// Whether a point is far enough from the last one to be worth keeping.
  ///
  /// Input smoothing, and the cheapest kind there is: a finger dragged slowly
  /// emits samples a fraction of a pixel apart, and every one of them is a
  /// point stored on the board, relayed to every guesser and replayed on
  /// reconnect. Dropping the ones too close to see costs nothing visually —
  /// the painter curves through the survivors — and takes a meaningful bite
  /// out of the highest-frequency payload in the game.
  ///
  /// The threshold is in normalised units, so it is the same fraction of the
  /// canvas on every device.
  static const double _minPointDistance = 0.004;

  bool _isFarEnough(StrokePoint from, StrokePoint to) {
    final double dx = to.x - from.x;
    final double dy = to.y - from.y;
    return (dx * dx + dy * dy) >= (_minPointDistance * _minPointDistance);
  }

  void _onPanStart(StrokePoint point) {
    final DrawToolState tool = ref.read(drawToolProvider);

    // Pressure is captured by the canvas for every point; it is kept only for
    // the one tool that renders with it, so no other stroke pays the extra
    // number per point on the wire.
    final StrokePoint first =
        tool.tool.usesPressure ? point : StrokePoint(x: point.x, y: point.y);

    final Stroke stroke = Stroke(
      id: IdGenerator.shortId(),
      authorId: ref.read(selfIdProvider),
      points: <StrokePoint>[first],
      colorValue: tool.colorValue,
      width: tool.width,
      tool: tool.tool,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    // A fill has no drag to wait for: it covers the canvas the moment it is
    // touched, so it is sent complete and never becomes a preview.
    if (tool.tool.isInstant) {
      final DrawingRepository drawing = ref.read(drawingRepositoryProvider);
      drawing.beginStroke(stroke);
      drawing.endStroke(stroke.id);
      return;
    }

    _pending.value = stroke;

    // A shape is previewed locally and sent once, on release — see
    // [DrawTool.isShape]. Announcing it now would put a degenerate
    // zero-size rectangle on every other screen for the length of the drag.
    if (tool.tool.isShape) return;

    ref.read(drawingRepositoryProvider).beginStroke(stroke);
    _startFlushTimer();
  }

  void _onPanUpdate(StrokePoint point) {
    final Stroke? current = _pending.value;
    if (current == null) {
      return;
    }

    // A shape has exactly two points: the drag's anchor and wherever the
    // finger is now. Replacing the second rather than appending is what keeps
    // it a rectangle instead of a scribble.
    if (current.tool.isShape) {
      _pending.value = current.copyWithPoints(
        <StrokePoint>[current.points.first, point],
      );
      return;
    }

    if (!_isFarEnough(current.points.last, point)) {
      return;
    }

    _pending.value = current.copyWithPoints(
      <StrokePoint>[...current.points, point],
    );
    _buffer.add(point);
  }

  void _onPanEnd() {
    final Stroke? current = _pending.value;
    if (current == null) {
      return;
    }

    final DrawingRepository drawing = ref.read(drawingRepositoryProvider);

    if (current.tool.isShape) {
      // The geometry has settled, so now it goes out — once, complete. A drag
      // that never moved is a degenerate shape nobody meant to draw, and is
      // dropped rather than sent as a dot.
      if (current.points.length >= 2) {
        drawing.beginStroke(current);
        drawing.endStroke(current.id);
      }
      _pending.value = null;
      return;
    }

    _flush();
    _flushTimer?.cancel();
    _flushTimer = null;
    drawing.endStroke(current.id);
    // Every point has now been flushed, and the repository echoes each flush
    // onto the board's event stream, so the committed stroke and the preview
    // are the same line. Dropping the preview is what stops it being drawn
    // twice. (Before the echo existed the server never sent the drawer their
    // own strokes back, so this line deleted the drawing instead.)
    _pending.value = null;
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.strokeBatchMs),
      (_) => _flush(),
    );
  }

  void _flush() {
    final Stroke? current = _pending.value;
    if (current == null || _buffer.isEmpty) {
      return;
    }
    final List<StrokePoint> batch = <StrokePoint>[..._buffer];
    _buffer.clear();
    ref.read(drawingRepositoryProvider).appendPoints(current.id, batch);
  }

  // ------------------------------------------------------------ actions ---

  Future<void> _sendGuess(String text) async {
    final Result<void> result =
        await ref.read(chatRepositoryProvider).send(text);
    if (!mounted) {
      return;
    }
    result.whenErr(
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  Future<void> _clearCanvas() async {
    final bool yes = await confirm(
      context,
      title: context.l10n.gameClearTitle,
      message: context.l10n.gameClearBody,
      confirmLabel: context.l10n.gameClear,
      destructive: true,
    );
    if (yes) {
      await ref.read(drawingRepositoryProvider).clear();
    }
  }

  Future<void> _quit() async {
    final bool yes = await confirm(
      context,
      title: context.l10n.gameQuitTitle,
      message: context.l10n.gameQuitBody,
      confirmLabel: context.l10n.leave,
      destructive: true,
    );
    if (!yes || !mounted) {
      return;
    }
    await ref.read(roomControllerProvider).leaveRoom();
    if (mounted) {
      context.goNamed(AppRoutes.home);
    }
  }

  // --------------------------------------------------------------- view ---

  @override
  Widget build(BuildContext context) {
    final GameState game = ref.watch(gameProvider);
    final Room? room = ref.watch(roomProvider);
    final bool isDrawer = ref.watch(isDrawerProvider);
    final DrawingBoard board = ref.watch(boardProvider);

    _listenForPhaseChanges(game);
    _syncWordSheet(game, isDrawer);

    if (room == null) {
      return const AppScaffold(
        showBack: false,
        banner: ConnectionBanner(),
        child: AppLoadingState(),
      );
    }

    final Widget canvas = game.phase == GamePhase.paused
        ? const _PausedCanvas()
        // Only this subtree rebuilds while a finger is down. The builder is
        // what confines a sixty-per-second stroke preview to the canvas
        // instead of the whole screen — see the note on [_pending].
        : ValueListenableBuilder<Stroke?>(
            valueListenable: _pending,
            builder: (BuildContext context, Stroke? pending, _) => DrawingCanvas(
              board: board,
              pending: pending,
              interactive: isDrawer && game.phase == GamePhase.drawing,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
            ),
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _quit();
        }
      },
      child: AppScaffold(
        showBack: false,
        padded: false,
        constrained: false,
        banner: const ConnectionBanner(),
        child: Column(
          children: <Widget>[
            _GameHeader(onQuit: _quit),
            Expanded(
              child: context.isCompact
                  ? _CompactLayout(
                      canvas: canvas,
                      isDrawer: isDrawer,
                      onClear: _clearCanvas,
                      onSend: _sendGuess,
                    )
                  : _WideLayout(
                      canvas: canvas,
                      isDrawer: isDrawer,
                      onClear: _clearCanvas,
                      onSend: _sendGuess,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Follows the server's phase into and out of the results screen.
  ///
  /// The results route is pushed at most once per visit: `roundEnd` and, right
  /// after it, `gameEnd` are two transitions but one screen, and pushing on
  /// both used to stack a second copy on top of the first.
  void _listenForPhaseChanges(GameState game) {
    ref.listen<GameState>(gameProvider, (GameState? previous, GameState next) {
      if (previous?.phase == next.phase) {
        return;
      }
      final bool showingResults = next.phase == GamePhase.roundEnd ||
          next.phase == GamePhase.gameEnd;

      if (showingResults && !_resultOpen) {
        _resultOpen = true;
        // The results screen pops itself when play resumes, so this flag is
        // cleared from there rather than guessed at here.
        context.pushNamed(AppRoutes.result).whenComplete(() {
          if (mounted) _resultOpen = false;
        });
      }

      if (next.phase == GamePhase.drawing) {
        // A fresh turn starts with a clean local preview.
        _pending.value = null;
        _buffer.clear();
      }
      if (next.phase == GamePhase.paused) {
        // The board was abandoned server-side; drop whatever was under the
        // finger so a half-drawn line cannot reappear when play resumes.
        _pending.value = null;
        _buffer.clear();
      }
    });
  }

  /// Opens and closes the word picker from the authoritative game state.
  ///
  /// ## Why not from `wordChoicesStream`
  ///
  /// The choices are pushed as a turn opens, which is while this device may
  /// still be showing the previous turn's scoreboard. Reacting to that push
  /// directly put the sheet *above* the results route, and the results route's
  /// own dismissal then popped the sheet instead of itself — so the drawer
  /// watched their picker vanish and the server chose a word for them fifteen
  /// seconds later.
  ///
  /// Reading it from the phase instead fixes both halves. The sheet opens only
  /// once the room is genuinely in [GamePhase.wordSelection] — the same signal
  /// that dismisses the results route — and it is deferred to after the frame
  /// so that dismissal has happened first. Being state-driven also makes it
  /// survive a reconnect: the restored game state carries the choices again,
  /// and a drawer who dropped mid-selection gets their picker back.
  void _syncWordSheet(GameState game, bool isDrawer) {
    final String turn = _turnKey(game);

    if (!isDrawer ||
        game.phase != GamePhase.wordSelection ||
        game.wordChoices.isEmpty) {
      // Leaving the selection phase releases the key so the *next* turn can
      // open its own sheet. The sheet itself has already closed by then.
      if (game.phase != GamePhase.wordSelection) _wordSheetTurn = null;
      return;
    }

    if (_wordSheetTurn == turn) {
      return;
    }
    _wordSheetTurn = turn;

    final List<WordItem> choices = List<WordItem>.unmodifiable(game.wordChoices);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_chooseWord(choices));
    });
  }

  /// Shows the picker and sends whatever the drawer chose.
  Future<void> _chooseWord(List<WordItem> choices) async {
    final int? index = await showWordChoiceSheet(context, choices: choices);
    if (index == null || !mounted) {
      // The window closed on its own; the server has already picked for us.
      return;
    }

    final Result<void> outcome =
        await ref.read(gameRepositoryProvider).selectWord(index);
    if (!mounted) {
      return;
    }
    outcome.whenErr(
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  /// Identifies one turn, so a sheet is offered once per turn and no more.
  ///
  /// Built from the three fields the server advances together when the pen
  /// changes hands; the phase is left out on purpose, since the whole point is
  /// to stay stable across the repeated `word_selection` states of one turn.
  String _turnKey(GameState game) =>
      '${game.currentRound}:${game.turnIndex}:${game.drawerId ?? ''}';
}

/// What the canvas becomes while the match is on hold.
///
/// The game is not over and the room has not been left — it is waiting for
/// somebody to arrive, and it resumes by itself when they do. Nothing here is
/// interactive, which is the point: the last player must not be able to carry
/// on alone.
class _PausedCanvas extends StatelessWidget {
  const _PausedCanvas();

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.border, width: AppSpacing.hairline),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.hourglass_empty_rounded,
                size: 36,
                color: colors.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.gamePaused,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(color: colors.text),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.gamePausedBody,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round counter, word, timer and the quit button.
class _GameHeader extends ConsumerWidget {
  const _GameHeader({required this.onQuit});

  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    final GameState game = ref.watch(gameProvider);
    final Room? room = ref.watch(roomProvider);
    final bool isDrawer = ref.watch(isDrawerProvider);
    final Player? drawer = ref.watch(drawerProvider);
    final int? seconds = ref.watch(secondsRemainingProvider);

    // The drawer sees the word; everyone else sees it masked. Once a guesser
    // has it right the mask comes off for them too.
    final bool revealed = isDrawer || ref.watch(hasGuessedProvider);
    final String word = revealed ? (game.word ?? '') : game.maskedWord;

    final String caption = switch (game.phase) {
      GamePhase.wordSelection => isDrawer
          ? context.l10n.gameChooseWord
          : context.l10n.gameWaitingForWord,
      GamePhase.drawing =>
        isDrawer ? context.l10n.gameYouDraw : context.l10n.gameGuessThis,
      GamePhase.starting => context.l10n.gameGetReady,
      GamePhase.roundEnd => context.l10n.gameTimeUp,
      GamePhase.paused => context.l10n.gamePaused,
      _ => drawer == null ? '' : context.l10n.gameWatching,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.border,
            width: AppSpacing.hairline,
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              HudBadge(
                label: 'R${game.currentRound}/${game.totalRounds}',
                icon: Icons.repeat_rounded,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  caption,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: colors.textMuted),
                ),
              ),
              // Voice sits with the other per-turn status in the header: a
              // microphone button for a guesser, a line of text for the
              // drawer, nothing between turns. It renders itself entirely from
              // `voiceChatProvider`, so nothing else in this screen has to
              // know whose turn it is twice.
              const VoiceControl(),
              const SizedBox(width: AppSpacing.xs),
              if (drawer != null) ...<Widget>[
                PlayerAvatar.ofPlayer(drawer, size: 26),
                const SizedBox(width: AppSpacing.xs),
              ],
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: context.l10n.leave,
                onPressed: onQuit,
              ),
            ],
          ),
          if (word.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            WordMaskDisplay(text: word, revealed: revealed),
          ],
          if (seconds != null && room != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TurnTimerBar(
              secondsRemaining: seconds,
              totalSeconds: game.phase == GamePhase.wordSelection
                  ? room.settings.wordSelectSeconds
                  : room.settings.drawTimeSeconds,
            ),
          ],
        ],
      ),
    );
  }
}

/// Phone layout: canvas on top, chat below, players in a sheet.
class _CompactLayout extends ConsumerWidget {
  const _CompactLayout({
    required this.canvas,
    required this.isDrawer,
    required this.onClear,
    required this.onSend,
  });

  final Widget canvas;
  final bool isDrawer;
  final VoidCallback onClear;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: AspectRatio(
            aspectRatio: AppConstants.canvasAspectRatio,
            child: canvas,
          ),
        ),
        if (isDrawer)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: DrawingToolbar(onClear: onClear),
          ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(child: _ChatPane(onSend: onSend)),
      ],
    );
  }
}

/// Tablet layout: canvas beside a fixed sidebar of players and chat.
class _WideLayout extends ConsumerWidget {
  const _WideLayout({
    required this.canvas,
    required this.isDrawer,
    required this.onClear,
    required this.onSend,
  });

  final Widget canvas;
  final bool isDrawer;
  final VoidCallback onClear;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final List<Player> players = ref.watch(playersProvider);
    final String selfId = ref.watch(selfIdProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: canvas,
                ),
              ),
              if (isDrawer)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: DrawingToolbar(onClear: onClear),
                ),
            ],
          ),
        ),
        Container(
          width: 320,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: colors.border,
                width: AppSpacing.hairline,
              ),
            ),
          ),
          child: Column(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: <Widget>[
                    for (final Player player in players)
                      PlayerRow(
                        player: player,
                        isSelf: player.id == selfId,
                        showScore: true,
                      ),
                  ],
                ),
              ),
              Divider(color: colors.border, height: AppSpacing.hairline),
              Expanded(flex: 3, child: _ChatPane(onSend: onSend)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The transcript and guess box, with the rules about who may type.
class _ChatPane extends ConsumerWidget {
  const _ChatPane({required this.onSend});

  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ChatMessage> messages = ref.watch(chatProvider);
    final String selfId = ref.watch(selfIdProvider);
    final bool isDrawer = ref.watch(isDrawerProvider);
    final bool hasGuessed = ref.watch(hasGuessedProvider);
    final Player? self = ref.watch(selfPlayerProvider);
    final bool muted = self?.isMuted ?? false;

    // The drawer must not type the word, and a player who has already guessed
    // must not spoil it for the rest. Both keep the box visible but inert.
    final (bool enabled, String hint) = switch ((isDrawer, hasGuessed, muted)) {
      (_, _, true) => (false, context.l10n.chatMuted),
      (true, _, _) => (false, context.l10n.chatDrawerHint),
      (_, true, _) => (false, context.l10n.chatGuessedHint),
      _ => (true, context.l10n.chatGuessHint),
    };

    return Column(
      children: <Widget>[
        Expanded(child: ChatList(messages: messages, selfId: selfId)),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: ChatComposer(
            onSend: onSend,
            enabled: enabled,
            hint: hint,
          ),
        ),
      ],
    );
  }
}
