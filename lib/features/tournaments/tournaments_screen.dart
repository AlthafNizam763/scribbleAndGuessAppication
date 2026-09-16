import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/time_utils.dart';
import 'package:scribble_guess/features/tournaments/tournament_widgets.dart';
import 'package:scribble_guess/models/auto_tournament.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Today's tournaments.
///
/// ## What this screen does not have
///
/// A create button. There is no admin panel behind it either, and no settings
/// to change — the day's three tournaments are published, filled, bracketed
/// and run by the server, and the only verbs a player has are join, check in,
/// and enter the match they were called to. That is the whole feature, and the
/// absence of everything else is the design rather than a gap in it.
///
/// There is no Quick Play button here either. This screen is about
/// tournaments; an ordinary game is one tap away on the home screen, and
/// putting a second, unrelated verb on every visit made the two kinds of play
/// look interchangeable — a player who pressed it expecting to enter the
/// tournament they were reading about landed in a public room instead.
///
/// ## Why at most three cards, and why finished ones stay
///
/// Three is the day, not a page size: the server publishes a morning, an
/// afternoon and an evening tournament and cannot publish a fourth. A finished
/// one keeps its card because its result is the most interesting thing on the
/// screen afterwards — and because the player who won it should be able to
/// find it. Nothing is removed from a day when it ends.
class TournamentsScreen extends ConsumerWidget {
  /// Creates the screen.
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TournamentDay> day = ref.watch(tournamentsProvider);
    final TournamentsNotifier notifier =
        ref.read(tournamentsProvider.notifier);

    return SketchScaffold(
      title: context.l10n.tournamentsTitle,
      padded: false,
      child: day.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => SketchEmptyState(
          message: error is Failure ? error.message : context.l10n.errorUnknown,
          icon: Icons.cloud_off_outlined,
          action: SketchButton(
            label: context.l10n.retry,
            onPressed: notifier.refresh,
          ),
        ),
        data: (TournamentDay value) => RefreshIndicator(
          onRefresh: notifier.refresh,
          child: _DayList(day: value),
        ),
      ),
    );
  }
}

/// The day's tournaments, under a one-line explanation of what they are.
class _DayList extends StatelessWidget {
  const _DayList({required this.day});

  final TournamentDay day;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return ListView(
      // Always scrollable, so pull-to-refresh works even on a day with nothing
      // on it — which is the state somebody is most likely to want to refresh.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pagePadding(context),
      children: <Widget>[
        Text(
          context.l10n.tournamentAutoSubtitle,
          style: text.bodyMedium?.copyWith(color: colors.inkSoft),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (day.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Column(
              children: <Widget>[
                const TrophyMark(size: 56),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.l10n.tournamentNoneToday,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: colors.ink),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.tournamentNoneTodayHint,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: colors.inkFaint),
                ),
              ],
            ),
          )
        else
          for (final AutoTournament tournament in day.tournaments) ...<Widget>[
            _TournamentCard(tournament: tournament, timeZone: day.timeZone),
            const SizedBox(height: AppSpacing.md),
          ],

        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// One of the day's tournaments.
class _TournamentCard extends ConsumerStatefulWidget {
  const _TournamentCard({required this.tournament, required this.timeZone});

  final AutoTournament tournament;
  final String timeZone;

  @override
  ConsumerState<_TournamentCard> createState() => _TournamentCardState();
}

class _TournamentCardState extends ConsumerState<_TournamentCard> {
  bool _busy = false;

  AutoTournament get _tournament => widget.tournament;

  /// Runs one write and reports whatever the server said about it.
  Future<void> _act(
    Future<Result<AutoTournament>> Function() action,
    String successMessage,
  ) async {
    setState(() => _busy = true);

    final Result<AutoTournament> result = await action();

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<AutoTournament>():
        notify(context, successMessage);
      case Err<AutoTournament>(:final Failure failure):
        // The server's own sentence, not a generic one. "Registration has
        // closed for this tournament" is a different thing to be told from
        // "that tournament is full", and the difference is what a player acts
        // on.
        notify(context, failure.message, isError: true);
    }
  }

  void _open() {
    context.pushNamed(
      AppRoutes.tournamentDetail,
      pathParameters: <String, String>{'tournamentId': _tournament.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final AutoTournament tournament = _tournament;

    return SketchCard(
      onTap: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      tournament.name,
                      style: text.titleMedium?.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tournament.dailySlot.label}'
                      '  ·  ${TimeUtils.formatClock(tournament.startAtMs)}'
                      '  ·  ${context.l10n.tournamentFormatKnockout}'
                      '  ·  ${context.l10n.tournamentFreeEntry}',
                      style: text.bodySmall?.copyWith(color: colors.inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TournamentStatusChip(status: tournament.status),
            ],
          ),

          // A finished tournament shows its result where its player counts
          // would be. It has no roster to fill any more, and the winner is the
          // only thing anybody opens it for.
          if (tournament.status == AutoTournamentStatus.completed)
            ..._completed(context, tournament)
          else if (tournament.status == AutoTournamentStatus.cancelled)
            ..._cancelled(context, tournament)
          else
            ..._live(context, tournament),

          const SizedBox(height: AppSpacing.md),
          _CardActions(
            tournament: tournament,
            busy: _busy,
            onJoin: () => _act(
              () => ref
                  .read(tournamentsProvider.notifier)
                  .register(tournament.id),
              context.l10n.tournamentRegistered,
            ),
            onCancelRegistration: () => _act(
              () => ref
                  .read(tournamentsProvider.notifier)
                  .withdraw(tournament.id),
              context.l10n.tournamentWithdrawn,
            ),
            onCheckIn: () => _act(
              () =>
                  ref.read(tournamentsProvider.notifier).checkIn(tournament.id),
              context.l10n.tournamentCheckedIn,
            ),
            onOpen: _open,
          ),
        ],
      ),
    );
  }

  /// The body of a card for a tournament that has not finished.
  List<Widget> _live(BuildContext context, AutoTournament tournament) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return <Widget>[
      const SizedBox(height: AppSpacing.md),
      TournamentPlayerCounts(tournament: tournament),

      if (tournament.status == AutoTournamentStatus.running &&
          tournament.totalRounds > 0) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${context.l10n.tournamentRound} '
          '${tournament.currentRound} / ${tournament.totalRounds}',
          style: text.bodySmall?.copyWith(color: colors.inkSoft),
        ),
      ],

      if (tournament.status == AutoTournamentStatus.checkIn) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          tournament.viewer.isCheckedIn
              ? context.l10n.tournamentCheckedInShort
              : context.l10n.tournamentCheckInOpen,
          style: text.bodySmall?.copyWith(
            color: tournament.viewer.isCheckedIn
                ? colors.success
                : colors.warning,
          ),
        ),
      ],

      if (tournament.activeDeadlineMs != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        TournamentCountdown(
          label: _countdownLabel(context, tournament),
          deadlineMs: tournament.activeDeadlineMs!,
          // The deadline passing is exactly when the server has changed
          // something, so the listing asks again rather than showing a
          // countdown stuck at zero.
          onElapsed: () =>
              unawaited(ref.read(tournamentsProvider.notifier).refresh()),
        ),
      ],

      if (tournament.viewer.blockedReason != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        Text(
          tournament.viewer.blockedReason!,
          style: text.bodySmall?.copyWith(color: colors.warning),
        ),
      ],
    ];
  }

  /// The body of a finished tournament's card: who won it.
  List<Widget> _completed(BuildContext context, AutoTournament tournament) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final TournamentParticipant? winner = tournament.winner;

    if (winner == null) {
      return <Widget>[
        const SizedBox(height: AppSpacing.md),
        Text(
          context.l10n.tournamentFinished,
          style: text.bodyMedium?.copyWith(color: colors.inkSoft),
        ),
      ];
    }

    return <Widget>[
      const SizedBox(height: AppSpacing.md),
      Text(
        context.l10n.tournamentWinner,
        style: text.bodySmall?.copyWith(color: colors.inkFaint),
      ),
      // The same row the bracket and the results table draw. It already knows
      // to give an AI a robot glyph rather than a player avatar, which is the
      // one mistake this card must not make — and reusing it is why it cannot
      // be made here separately.
      TournamentPlayerLine(
        player: winner,
        trailing: Icon(Icons.emoji_events, size: 20, color: colors.accentYellow),
      ),
    ];
  }

  /// The body of a cancelled tournament's card.
  List<Widget> _cancelled(BuildContext context, AutoTournament tournament) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return <Widget>[
      const SizedBox(height: AppSpacing.md),
      Text(
        tournament.cancelReason ?? context.l10n.tournamentCancelled,
        style: text.bodyMedium?.copyWith(color: colors.inkSoft),
      ),
      const SizedBox(height: AppSpacing.xs),
      // The replacement is simply the next card on the screen. Nothing is
      // created to take a cancelled tournament's place, so this says where to
      // look rather than promising something that is coming.
      Text(
        context.l10n.tournamentCancelledHint,
        style: text.bodySmall?.copyWith(color: colors.inkFaint),
      ),
    ];
  }

  /// What the clock on this card is counting down to.
  String _countdownLabel(BuildContext context, AutoTournament tournament) =>
      switch (tournament.status) {
        AutoTournamentStatus.upcoming => context.l10n.tournamentJoiningOpensIn,
        AutoTournamentStatus.registration => context.l10n.tournamentClosesIn,
        AutoTournamentStatus.checkIn => context.l10n.tournamentStartsIn,
        _ => context.l10n.tournamentStartsIn,
      };
}

/// The buttons on a card, which depend entirely on the server's `viewer`.
///
/// Nothing here works out whether an action is allowed — `canRegister`,
/// `canCheckIn` and `canWithdraw` arrive decided, because the rules behind them
/// are server rules. A client deriving them would be a second implementation
/// that could disagree, and the disagreement would look like a button that
/// does nothing.
///
/// The set of buttons that can appear is closed: join, cancel registration,
/// check in, enter match, view bracket, view result. There is no create, no
/// admin control, and no play-now — a second, unrelated verb on a tournament
/// card is how a player ends up in an ordinary room believing they entered the
/// tournament.
class _CardActions extends StatelessWidget {
  const _CardActions({
    required this.tournament,
    required this.busy,
    required this.onJoin,
    required this.onCancelRegistration,
    required this.onCheckIn,
    required this.onOpen,
  });

  final AutoTournament tournament;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onCancelRegistration;
  final VoidCallback onCheckIn;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final ViewerTournamentState viewer = tournament.viewer;

    // A match waiting for this player beats everything else on the card: they
    // are on a clock, and missing it costs them the tournament. It is also the
    // only condition under which an "enter match" button exists at all — a
    // player with no assigned match is never shown one.
    if (viewer.activeMatch != null) {
      return SketchButton(
        label: context.l10n.tournamentEnterMatch,
        variant: SketchButtonVariant.primary,
        icon: Icons.play_arrow_rounded,
        expand: true,
        onPressed: onOpen,
      );
    }

    // A cancelled tournament has nothing to press. No join, no details worth
    // opening — the card has already said what happened.
    if (tournament.status == AutoTournamentStatus.cancelled) {
      return const SizedBox.shrink();
    }

    // A finished one has a result to read, and nothing to join.
    if (tournament.status == AutoTournamentStatus.completed) {
      return Row(
        children: <Widget>[
          Expanded(
            child: SketchButton(
              label: context.l10n.tournamentViewResult,
              variant: SketchButtonVariant.secondary,
              expand: true,
              onPressed: onOpen,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: onOpen,
            child: Text(context.l10n.tournamentViewBracket),
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        if (viewer.canCheckIn)
          Expanded(
            child: SketchButton(
              label: context.l10n.tournamentCheckIn,
              variant: SketchButtonVariant.primary,
              busy: busy,
              expand: true,
              onPressed: onCheckIn,
            ),
          )
        else if (viewer.canRegister)
          Expanded(
            child: SketchButton(
              label: context.l10n.tournamentJoin,
              variant: SketchButtonVariant.primary,
              busy: busy,
              expand: true,
              onPressed: onJoin,
            ),
          )
        else if (viewer.isRegistered)
          Expanded(
            child: Row(
              children: <Widget>[
                Icon(Icons.check, size: 18, color: colors.success),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    viewer.isCheckedIn
                        ? context.l10n.tournamentCheckedInShort
                        : context.l10n.tournamentRegisteredShort,
                    style: text.bodyMedium?.copyWith(color: colors.inkSoft),
                  ),
                ),
                // Only where the server says it is still allowed — which is
                // while registration is open, because past that a seat is a
                // pairing and removing it would leave a hole in the draw.
                if (viewer.canWithdraw)
                  TextButton(
                    onPressed: busy ? null : onCancelRegistration,
                    child: Text(context.l10n.tournamentCancelRegistration),
                  ),
              ],
            ),
          )
        else
          const Spacer(),

        const SizedBox(width: AppSpacing.sm),
        TextButton(
          onPressed: onOpen,
          child: Text(
            tournament.status == AutoTournamentStatus.running
                ? context.l10n.tournamentViewBracket
                : context.l10n.tournamentDetails,
          ),
        ),
      ],
    );
  }
}

/// Fires a future and deliberately ignores it.
///
/// The countdown's `onElapsed` is a `VoidCallback`, and the refresh it kicks
/// off has nowhere to be awaited — the screen rebuilds from the provider when
/// it lands. Named rather than a bare `unawaited` import so the intent is on
/// the page.
void unawaited(Future<void> future) {
  future.ignore();
}
