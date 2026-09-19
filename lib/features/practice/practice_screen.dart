import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/rules/rules.dart';
import 'package:scribble_guess/core/utils/id_generator.dart';
import 'package:scribble_guess/features/game/widgets/tool_tray_sheet.dart';
import 'package:scribble_guess/features/practice/practice_session.dart';
import 'package:scribble_guess/models/drawing_board.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Solo practice: draw a word, guess it yourself, no room and no network.
///
/// ## Why the state lives in the widget
///
/// Every other game surface reads its state from a provider because the
/// *server* owns it and several widgets need the same answer. Here there is no
/// server and no second reader: the session belongs to this screen, dies with
/// it, and is deliberately not reachable from anywhere else. Putting it in a
/// provider would make a local scratchpad look like shared truth.
///
/// ## Why nothing here is saved
///
/// The score and the board vanish on pop. That is the feature, not an
/// omission — see the class comment on [PracticeSession]. Practice cannot award
/// XP, unlock achievements or move a leaderboard because it has no code path to
/// the server at all, which is a stronger guarantee than a flag the backend
/// would have to trust.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  late final PracticeEngine _engine;
  late PracticeSession _session;

  DrawingBoard _board = DrawingBoard.empty;
  Stroke? _pending;

  final TextEditingController _guessController = TextEditingController();

  /// Drives the countdown and the hints.
  ///
  /// Half a second rather than a frame: the only things it moves are a seconds
  /// display and a hint that lands a handful of times a turn, so a 60Hz ticker
  /// would wake the engine a hundred times for every visible change. The engine
  /// derives everything from the clock reading it is passed, so a late tick
  /// catches up rather than losing time — which is what makes a backgrounded
  /// app resume correctly instead of quietly pausing the turn.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();

    // The interface language picks the word bank, which is the one place the
    // two genuinely should agree: somebody practising in Tamil wants Tamil
    // words, and there is no room setting here to say otherwise.
    final AppLanguage language = ref.read(settingsProvider).language;

    _engine = PracticeEngine(bank: PracticeEngine.bankFor(language));
    _session = _engine.start(
      RoomSettings(language: language),
      DateTime.now().millisecondsSinceEpoch,
    );

    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _guessController.dispose();
    super.dispose();
  }

  void _tick() {
    if (!_session.isDrawing) return;
    setState(() {
      _session = _engine.tick(
        _session,
        DateTime.now().millisecondsSinceEpoch,
      );
    });
  }

  void _choose(WordItem word) {
    setState(() {
      _session = _engine.choose(
        _session,
        word,
        DateTime.now().millisecondsSinceEpoch,
      );
      _board = DrawingBoard.empty;
      _pending = null;
      _guessController.clear();
    });
  }

  void _submitGuess(String text) {
    if (text.trim().isEmpty || !_session.isDrawing) return;
    setState(() {
      _session = _engine.guess(
        _session,
        text,
        DateTime.now().millisecondsSinceEpoch,
      );
      _guessController.clear();
    });
  }

  void _giveUp() {
    setState(() => _session = _engine.finish(_session, correct: false));
  }

  void _next() {
    setState(() {
      _session = _engine.next(_session, DateTime.now().millisecondsSinceEpoch);
      _board = DrawingBoard.empty;
      _pending = null;
      _guessController.clear();
    });
  }

  // --- Drawing -------------------------------------------------------------
  //
  // Simpler than the game screen's handlers by exactly what the network added:
  // no batching timer, no repository call and no author id that matters,
  // because the only consumer of these strokes is the painter below.

  void _onPanStart(StrokePoint point) {
    final DrawToolState tool = ref.read(drawToolProvider);

    final Stroke stroke = Stroke(
      id: IdGenerator.shortId(),
      points: <StrokePoint>[
        tool.tool.usesPressure ? point : StrokePoint(x: point.x, y: point.y),
      ],
      colorValue: tool.colorValue,
      width: tool.width,
      tool: tool.tool,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );

    // A fill has no drag to wait for; it commits on touch.
    if (tool.tool.isInstant) {
      setState(() => _board = _board.addStroke(stroke));
      return;
    }

    setState(() => _pending = stroke);
  }

  void _onPanUpdate(StrokePoint point) {
    final Stroke? current = _pending;
    if (current == null) return;

    // A shape is its anchor and wherever the finger is now — two points, the
    // second replaced rather than appended.
    setState(() {
      _pending = current.tool.isShape
          ? current.copyWithPoints(<StrokePoint>[current.points.first, point])
          : current.copyWithPoints(<StrokePoint>[...current.points, point]);
    });
  }

  void _onPanEnd() {
    final Stroke? current = _pending;
    if (current == null) return;

    setState(() {
      // A shape that never moved is a degenerate drag nobody meant, and is
      // dropped rather than committed as a dot.
      final bool keep = !current.tool.isShape || current.points.length >= 2;
      if (keep) {
        _board = _board.addStroke(current);
      }
      _pending = null;
    });
  }

  void _undo() => setState(() => _board = _board.undo());

  /// Practice keeps its own board, so redo is that board's own pure operation
  /// rather than a repository call. The game screen's redo goes through the
  /// server because everybody else has to see it too.
  void _redo() => setState(() => _board = _board.redo());

  void _clear() => setState(() {
        _board = DrawingBoard.empty;
        _pending = null;
      });

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: context.l10n.practiceTitle,
      padded: false,
      constrained: false,
      child: Column(
        children: <Widget>[
          _PracticeHeader(session: _session),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DrawingCanvas(
                      board: _board,
                      pending: _pending,
                      interactive: _session.isDrawing,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                    ),
                  ),
                  if (_session.phase == PracticePhase.choosing)
                    Positioned.fill(
                      child: _ChoiceOverlay(
                        choices: _session.choices,
                        onChoose: _choose,
                      ),
                    ),
                  if (_session.phase == PracticePhase.finished)
                    Positioned.fill(
                      child: _FinishedOverlay(
                        session: _session,
                        onNext: _next,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_session.isDrawing)
            _PracticeControls(
              board: _board,
              controller: _guessController,
              verdict: _session.lastVerdict,
              onUndo: _undo,
              onRedo: _redo,
              onClear: _clear,
              onGuess: _submitGuess,
              onGiveUp: _giveUp,
            ),
        ],
      ),
    );
  }
}

/// Score, masked word and the clock.
class _PracticeHeader extends StatelessWidget {
  const _PracticeHeader({required this.session});

  final PracticeSession session;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final int seconds =
        session.secondsRemaining(DateTime.now().millisecondsSinceEpoch);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            '${context.l10n.practiceScore} ${session.score}',
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          Expanded(
            child: Center(
              child: Text(
                session.isDrawing ? session.maskedWord : '',
                // Letter spacing is what turns the mask into a row of slots
                // rather than a word with holes in it.
                style: text.titleLarge?.copyWith(
                  color: colors.text,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          if (session.isDrawing)
            Text(
              '$seconds',
              style: text.titleMedium?.copyWith(
                color: seconds <= 10 ? colors.danger : colors.text,
              ),
            ),
        ],
      ),
    );
  }
}

/// The word choices, over a blank canvas.
class _ChoiceOverlay extends StatelessWidget {
  const _ChoiceOverlay({required this.choices, required this.onChoose});

  final List<WordItem> choices;
  final ValueChanged<WordItem> onChoose;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return ColoredBox(
      color: colors.surface.withValues(alpha: 0.94),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                context.l10n.practiceChooseWord,
                style: text.titleMedium?.copyWith(color: colors.text),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final WordItem choice in choices) ...<Widget>[
                AppButton(
                  label: choice.text,
                  expand: true,
                  onPressed: () => onChoose(choice),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The reveal, and the way on to the next word.
class _FinishedOverlay extends StatelessWidget {
  const _FinishedOverlay({required this.session, required this.onNext});

  final PracticeSession session;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final bool won = session.lastVerdict == GuessVerdict.correct;

    return ColoredBox(
      color: colors.surface.withValues(alpha: 0.94),
      child: Center(
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                won ? Icons.check_circle_outline : Icons.schedule,
                color: won ? colors.success : colors.textMuted,
                size: 40,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                won ? context.l10n.practiceGotIt : context.l10n.practiceTimeUp,
                style: text.titleMedium?.copyWith(color: colors.text),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                session.word?.text ?? '',
                style: text.headlineSmall?.copyWith(color: colors.text),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: context.l10n.practiceNextWord,
                icon: Icons.arrow_forward,
                variant: AppButtonVariant.primary,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tools on one line, the guess field on the next.
class _PracticeControls extends StatelessWidget {
  const _PracticeControls({
    required this.board,
    required this.controller,
    required this.verdict,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onGuess,
    required this.onGiveUp,
  });

  final DrawingBoard board;
  final TextEditingController controller;
  final GuessVerdict? verdict;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final ValueChanged<String> onGuess;
  final VoidCallback onGiveUp;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: context.l10n.practiceTools,
                  icon: const Icon(Icons.palette_outlined),
                  color: colors.text,
                  // Practice has no colour row of its own, so the tray is the
                  // only palette on this screen — and it carries the same
                  // three board actions as the row beside it.
                  onPressed: () => showToolTray(
                    context,
                    actions: DrawingToolActions(
                      onUndo: board.canUndo ? onUndo : null,
                      onRedo: board.canRedo ? onRedo : null,
                      onClear: board.canUndo ? onClear : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.practiceUndo,
                  icon: const Icon(Icons.undo),
                  color: colors.text,
                  onPressed: board.canUndo ? onUndo : null,
                ),
                IconButton(
                  tooltip: context.l10n.practiceClear,
                  icon: const Icon(Icons.delete_outline),
                  color: colors.text,
                  onPressed: board.canUndo ? onClear : null,
                ),
                const Spacer(),
                TextButton(
                  onPressed: onGiveUp,
                  child: Text(
                    context.l10n.practiceGiveUp,
                    style: text.bodyMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: onGuess,
              decoration: InputDecoration(
                hintText: context.l10n.practiceGuessHint,
                // A close guess is worth saying so: it is the one piece of
                // feedback the real game gives that a solo player would
                // otherwise have to infer from nothing at all.
                helperText: switch (verdict) {
                  GuessVerdict.close => context.l10n.practiceClose,
                  GuessVerdict.wrong => context.l10n.practiceWrong,
                  _ => null,
                },
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  color: colors.text,
                  onPressed: () => onGuess(controller.text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
