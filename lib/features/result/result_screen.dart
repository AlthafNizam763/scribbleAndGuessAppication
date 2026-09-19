import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/features/progression/achievement_card.dart';
import 'package:scribble_guess/features/progression/xp_progress_widget.dart';
import 'package:scribble_guess/features/result/game_result_share_card.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/player_score.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/models/round_result.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Standings between rounds and at the end of a game.
///
/// One screen for both: the round view auto-dismisses when the next turn
/// begins, while the final view waits for the player.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _recorded = false;
  bool _busy = false;
  bool _popScheduled = false;

  /// Whether the room has moved on to something this screen is not about.
  ///
  /// [GamePhase.paused] counts. A match that dropped below the minimum number
  /// of players has no next turn to wait for, so sitting on "next turn
  /// starting soon" would be a promise the server is not going to keep.
  static bool _playMovedOn(GamePhase phase) =>
      phase == GamePhase.wordSelection ||
      phase == GamePhase.drawing ||
      phase == GamePhase.paused;

  /// Pops this route, but only when it is the one on top.
  ///
  /// `isCurrent` matters. `context.pop()` pops whatever is on top of this
  /// navigator, not necessarily this route, so popping while something else is
  /// above would dismiss that instead — which is precisely how the drawer's
  /// word picker used to disappear the instant the next turn opened. When
  /// something is above, the pop is abandoned rather than retried; the next
  /// phase change picks it up once this route is back on top.
  void _popIfCurrent() {
    if (!mounted) {
      return;
    }
    final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (isCurrent && context.canPop()) {
      context.pop();
    }
  }

  /// The same pop, asked for from inside `build`, where it cannot happen yet.
  void _popAfterFrame() {
    if (_popScheduled) {
      return;
    }
    _popScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Cleared first: if the route could not be popped this frame, a later
      // rebuild has to be able to ask again.
      _popScheduled = false;
      _popIfCurrent();
    });
  }

  Future<void> _playAgain() async {
    setState(() => _busy = true);
    final Result<void> result =
        await ref.read(gameRepositoryProvider).playAgain();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    result.fold(
      (_) => context.goNamed(AppRoutes.lobby),
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  Future<void> _goHome() async {
    await ref.read(roomControllerProvider).leaveRoom();
    if (mounted) {
      context.goNamed(AppRoutes.home);
    }
  }

  /// Folds the finished game into the local leaderboard, exactly once.
  void _recordOnce(GameResult result) {
    if (_recorded) {
      return;
    }
    _recorded = true;
    // Deferred so the write does not run during the build that noticed it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(leaderboardProvider.notifier).record(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final GameState game = ref.watch(gameProvider);
    final GameResult? finalResult = ref.watch(gameResultProvider).valueOrNull;
    final RoundResult? roundResult = ref.watch(roundResultProvider).valueOrNull;
    final bool isFinal = game.phase == GamePhase.gameEnd && finalResult != null;

    if (isFinal) {
      _recordOnce(finalResult);
    }

    // Between rounds the server starts the next turn on its own; when it does,
    // this screen has nothing left to say. A paused match dismisses it too:
    // there is no next turn to wait for until the room is back at strength, and
    // the game screen underneath is where that is explained.
    //
    // Asked twice, on purpose, because the two ask different questions.
    //
    // The listener handles an ordinary turn change, and it is the one that
    // runs *before* the next frame — which is what keeps the drawer's word
    // picker from being opened above a route that is about to pop.
    //
    // The build-time check handles what a listener cannot see at all: a phase
    // that moved on between the push and this route's first build. The game
    // screen pushes on `round_result`, and the route is built a frame later,
    // so anything the server says in between arrives before there is a
    // listener to hear it. That is the normal course of events when the room
    // drops to one player: `round_result` and `paused` are broadcast one
    // after the other, the screen mounts already stale, and — since a paused
    // room says nothing further until somebody joins — no change was ever
    // going to arrive to wake the listener up.
    ref.listen<GameState>(gameProvider, (GameState? previous, GameState next) {
      if (_playMovedOn(next.phase)) {
        _popIfCurrent();
      }
    });
    if (_playMovedOn(game.phase)) {
      _popAfterFrame();
    }

    return PopScope(
      canPop: false,
      child: AppScaffold(
        showBack: false,
        banner: const ConnectionBanner(),
        bottom: isFinal
            ? Row(
                children: <Widget>[
                  Expanded(
                    child: AppButton(
                      label: context.l10n.resultsBackHome,
                      icon: Icons.home_outlined,
                      expand: true,
                      onPressed: _goHome,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      label: context.l10n.resultsPlayAgain,
                      icon: Icons.replay,
                      expand: true,
                      variant: AppButtonVariant.primary,
                      busy: _busy,
                      onPressed: ref.watch(isHostProvider) ? _playAgain : null,
                    ),
                  ),
                ],
              )
            : null,
        child: isFinal
            ? _FinalStandings(result: finalResult)
            : _RoundSummary(result: roundResult),
      ),
    );
  }
}

/// The between-rounds view: the word, and who got it.
class _RoundSummary extends ConsumerWidget {
  const _RoundSummary({required this.result});

  final RoundResult? result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final List<Player> players = ref.watch(playersProvider);
    final String selfId = ref.watch(selfIdProvider);

    if (result == null) {
      return const AppLoadingState();
    }

    final RoundResult round = result!;
    final bool nobodyGuessed = round.correctOrder.isEmpty;

    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.resultsRoundTitle,
          textAlign: TextAlign.center,
          style: text.displaySmall?.copyWith(color: colors.text),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          selected: true,
          tone: colors.tertiary,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Column(
            children: <Widget>[
              Text(
                context.l10n.resultsWordWas.toUpperCase(),
                style: text.labelSmall?.copyWith(color: colors.tertiary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                round.word,
                textAlign: TextAlign.center,
                style: text.displaySmall?.copyWith(color: colors.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // The replay becomes readable at exactly this moment: the turn has
        // ended, so the server will serve its drawing and its word. Offered
        // only when the result named a persisted match — a turn without one
        // has nothing to fetch, and a button that could only fail is worse
        // than no button.
        if (round.gameId.isNotEmpty && round.turnNumber > 0) ...<Widget>[
          AppButton(
            label: context.l10n.replayWatch,
            icon: Icons.play_circle_outline,
            expand: true,
            onPressed: () => context.pushNamed(
              AppRoutes.replay,
              pathParameters: <String, String>{
                'gameId': round.gameId,
                'turnNumber': '${round.turnNumber}',
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        if (nobodyGuessed)
          Text(
            context.l10n.resultsNobodyGuessed,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.resultsThisRound.toUpperCase(),
          style: text.labelSmall?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final Player player in players)
          PlayerRow(
            player: player,
            isSelf: player.id == selfId,
            showScore: true,
            trailing: _Delta(points: round.scoreDeltas[player.id] ?? 0),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          context.l10n.resultsNextRoundSoon,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// Points gained this round, shown only when there were any.
class _Delta extends StatelessWidget {
  const _Delta({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    if (points <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Text(
        '+$points',
        style: text.titleSmall?.copyWith(color: colors.success),
      ),
    );
  }
}

/// The end-of-game podium.
/// The share button and the off-screen card it rasterises.
///
/// The card is rendered into an [Offstage] rather than shown: the on-screen
/// standings are already laid out for a phone, and a picture worth sharing
/// wants a fixed width and everything visible at once. Rasterising what is
/// on screen would produce a card cropped to whatever the player had
/// scrolled to.
class _ShareResult extends ConsumerStatefulWidget {
  const _ShareResult({required this.result});

  final GameResult result;

  @override
  ConsumerState<_ShareResult> createState() => _ShareResultState();
}

class _ShareResultState extends ConsumerState<_ShareResult> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final RenderObject? object = _cardKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;

      // 3x so the shared image is legible rather than a thumbnail.
      final ui.Image image = await object.toImage(pixelRatio: 3);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;

      final Directory directory = await getTemporaryDirectory();
      final File file = File(
        '${directory.path}/scribble-result-${widget.result.roomCode}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(file.path)], text: _summary()),
      );
    } catch (error, stackTrace) {
      // Sharing is a side errand: a failure must not disturb the
      // standings the players are looking at.
      AppLogger.w('Result: share failed', error, stackTrace);
      if (mounted) {
        notify(context, context.l10n.resultShareFailed, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The standings as plain text, for the copy action and the share caption.
  String _summary() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('${context.l10n.appName} — ${widget.result.gameMode.label}');

    for (final PlayerScore score in widget.result.standings) {
      buffer.writeln('${score.rank}. ${score.name} — ${score.score}');
    }

    return buffer.toString().trimRight();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _summary()));
    if (mounted) notify(context, context.l10n.resultCopied);
  }

  @override
  Widget build(BuildContext context) {
    final int xp =
        ref.watch(matchProgressionProvider).valueOrNull?.xpEarned ?? 0;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                label: context.l10n.resultCopy,
                icon: Icons.copy,
                expand: true,
                onPressed: _copy,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppButton(
                label: context.l10n.resultShare,
                icon: Icons.ios_share,
                expand: true,
                busy: _busy,
                onPressed: _share,
              ),
            ),
          ],
        ),

        // Laid out but never painted to the screen. `Offstage` keeps it out
        // of the visual tree while leaving it renderable, which is what the
        // boundary needs to produce an image of it.
        Offstage(
          child: RepaintBoundary(
            key: _cardKey,
            child: SizedBox(
              width: 380,
              child: GameResultShareCard(
                result: widget.result,
                xpEarned: xp,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FinalStandings extends ConsumerWidget {
  const _FinalStandings({required this.result});

  final GameResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final String selfId = ref.watch(selfIdProvider);
    final PlayerScore? winner = result.winner;
    final bool selfWon = winner?.playerId == selfId;

    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        const SizedBox(height: AppSpacing.lg),
        Text(
          selfWon ? context.l10n.resultsYouWon : context.l10n.resultsFinalTitle,
          textAlign: TextAlign.center,
          style: text.headlineMedium?.copyWith(
            color: selfWon ? colors.success : colors.text,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (winner != null)
          Center(
            child: Column(
              children: <Widget>[
                PlayerAvatar(
                  avatarId: winner.avatarId,
                  colorIndex: winner.avatarColorIndex,
                  size: 88,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  winner.name,
                  style: text.titleLarge?.copyWith(color: colors.text),
                ),
                Text(
                  '${winner.score}',
                  style: text.displaySmall?.copyWith(color: colors.text),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xl),

        // What this match paid the local player. Arrives on `s:game:end`
        // beside the standings — the server builds one report per recipient,
        // so this is never anybody else's — and is absent for a match that
        // paid nothing, which is what an abandoned game pays.
        ref.watch(matchProgressionProvider).maybeWhen(
              data: (MatchProgression report) => _MatchPayout(report: report),
              orElse: () => const SizedBox.shrink(),
            ),

        Text(
          context.l10n.resultsTotals.toUpperCase(),
          style: text.labelSmall?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final PlayerScore score in result.standings)
          _StandingRow(score: score, isSelf: score.playerId == selfId),
        const SizedBox(height: AppSpacing.xl),

        // Sharing sits below the standings rather than in the bottom bar: the
        // bar is for leaving and playing again, which are the two things the
        // room is waiting on.
        _ShareResult(result: result),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.score, required this.isSelf});

  final PlayerScore score;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        selected: isSelf,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Text(
                '${score.rank}',
                style: text.titleMedium?.copyWith(color: colors.textMuted),
              ),
            ),
            PlayerAvatar(
              avatarId: score.avatarId,
              colorIndex: score.avatarColorIndex,
              size: 38,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                score.name,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(color: colors.text),
              ),
            ),
            Text(
              '${score.score}',
              style: text.titleMedium?.copyWith(color: colors.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// What one finished match paid the local player.
///
/// ## It renders a report, it does not compute one
///
/// Every figure here — the XP, the level, which achievements unlocked — was
/// decided by the server and written before this widget existed. The client
/// adds nothing up. That is what keeps the number on this screen the same as
/// the one on the profile a moment later.
///
/// Absent entirely when there is nothing to show, rather than a card reading
/// "+0 XP": a match that paid nothing is one the server declined to rank, and
/// saying so in a box would invite the question.
class _MatchPayout extends StatelessWidget {
  const _MatchPayout({required this.report});

  final MatchProgression report;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) return const SizedBox.shrink();

    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  context.l10n.progressionEarned.toUpperCase(),
                  style: text.labelSmall?.copyWith(color: colors.textMuted),
                ),
                const Spacer(),
                Text(
                  context.l10n.progressionXpEarned(report.xpEarned),
                  style: AppTypography.numeric(colors.tertiary, size: 18),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            XpProgressWidget(level: report.level),

            if (report.leveledUp) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: colors.accentYellow,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    context.l10n.progressionLevelUp(
                      report.level.level,
                      report.level.title,
                    ),
                    style: text.titleSmall?.copyWith(
                      color: colors.text,
                      fontWeight: AppTypography.black,
                    ),
                  ),
                ],
              ),
            ],

            if (report.unlocked.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text(
                context.l10n.progressionUnlocked.toUpperCase(),
                style: text.labelSmall?.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final Achievement entry in report.unlocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AchievementCard(achievement: entry),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
