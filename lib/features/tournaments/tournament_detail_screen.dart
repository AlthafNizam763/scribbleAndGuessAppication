import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/time_utils.dart';
import 'package:scribble_guess/features/tournaments/tournament_widgets.dart';
import 'package:scribble_guess/models/auto_tournament.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// One tournament: who is in it, what the rules are, and how the draw stands.
///
/// ## What a player comes here to do
///
/// Three things, in order of how much they matter: enter the match they have
/// been called to, check in before the draw, and see who they are up against.
/// Everything else on the page is context for those.
///
/// ## Why the roster shows the AI players rather than hiding them
///
/// Because a four-player tournament that is one person and three robots is a
/// different thing from four people, and the player about to spend twenty
/// minutes in it deserves to know which. Every entrant goes through
/// [TournamentPlayerLine], which draws the badge from the server's own flag.
class TournamentDetailScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [tournamentId].
  const TournamentDetailScreen({required this.tournamentId, super.key});

  /// Which tournament.
  final String tournamentId;

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailScreenState();
}

class _TournamentDetailScreenState
    extends ConsumerState<TournamentDetailScreen> {
  bool _busy = false;

  /// Re-reads everything this screen shows.
  ///
  /// One refresh rather than three, because the four providers describe one
  /// tournament and a screen showing a new bracket beside an old roster would
  /// be worse than a screen that was briefly a second behind.
  Future<void> _refresh() async {
    ref.invalidate(tournamentDetailProvider(widget.tournamentId));
    ref.invalidate(tournamentParticipantsProvider(widget.tournamentId));
    ref.invalidate(tournamentBracketProvider(widget.tournamentId));
    ref.invalidate(tournamentResultsProvider(widget.tournamentId));
    await ref.read(tournamentsProvider.notifier).refresh();
  }

  Future<void> _checkIn() async {
    setState(() => _busy = true);

    final Result<AutoTournament> result = await ref
        .read(tournamentsProvider.notifier)
        .checkIn(widget.tournamentId);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<AutoTournament>():
        notify(context, context.l10n.tournamentCheckedIn);
        await _refresh();
      case Err<AutoTournament>(:final Failure failure):
        notify(context, failure.message, isError: true);
    }
  }

  Future<void> _register() async {
    setState(() => _busy = true);

    final Result<AutoTournament> result = await ref
        .read(tournamentsProvider.notifier)
        .register(widget.tournamentId);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<AutoTournament>():
        notify(context, context.l10n.tournamentRegistered);
        await _refresh();
      case Err<AutoTournament>(:final Failure failure):
        notify(context, failure.message, isError: true);
    }
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);

    final Result<AutoTournament> result = await ref
        .read(tournamentsProvider.notifier)
        .withdraw(widget.tournamentId);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<AutoTournament>():
        notify(context, context.l10n.tournamentWithdrew);
        await _refresh();
      case Err<AutoTournament>(:final Failure failure):
        notify(context, failure.message, isError: true);
    }
  }

  /// Asks the server for the match's room code, then joins it.
  ///
  /// The join goes through the ordinary room path, which is the whole point:
  /// a tournament match is a room, and there is no second way into a game.
  Future<void> _enterMatch(ViewerMatch match) async {
    setState(() => _busy = true);

    final Result<TournamentMatchEntry> entry =
        await ref.read(tournamentsApiProvider).enterMatch(
              tournamentId: widget.tournamentId,
              matchId: match.matchId,
            );

    if (!mounted) return;

    switch (entry) {
      case Ok<TournamentMatchEntry>(value: final TournamentMatchEntry it):
        // The ordinary room join, with the ordinary room code. The room is
        // protected — it refuses anybody outside this pairing — but nothing
        // about *joining* it is special, which is exactly the point: a
        // tournament match is a room, and there is no second way into a game.
        final Result<Room> joined =
            await ref.read(roomControllerProvider).joinRoom(it.roomCode);

        if (!mounted) return;
        setState(() => _busy = false);

        switch (joined) {
          case Ok<Room>():
            context.goNamed(AppRoutes.lobby);
          case Err<Room>(:final Failure failure):
            notify(context, failure.message, isError: true);
        }

      case Err<TournamentMatchEntry>(:final Failure failure):
        setState(() => _busy = false);
        notify(context, failure.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AutoTournament> tournament =
        ref.watch(tournamentDetailProvider(widget.tournamentId));

    return AppScaffold(
      title: tournament.valueOrNull?.name ?? context.l10n.tournamentsTitle,
      padded: false,
      child: tournament.when(
        loading: () => const AppLoadingState(),
        error: (Object error, StackTrace stack) => AppEmptyState(
          message: error is Failure ? error.message : context.l10n.errorUnknown,
          icon: Icons.cloud_off_outlined,
          action: AppButton(
            label: context.l10n.retry,
            onPressed: _refresh,
          ),
        ),
        data: (AutoTournament row) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pagePadding(context),
            children: <Widget>[
              _Summary(
                tournament: row,
                busy: _busy,
                onRegister: _register,
                onWithdraw: _withdraw,
                onCheckIn: _checkIn,
                onEnterMatch: _enterMatch,
                onDeadlinePassed: _refresh,
              ),
              const SizedBox(height: AppSpacing.lg),
              _Rules(tournament: row),
              const SizedBox(height: AppSpacing.lg),
              _Roster(tournamentId: widget.tournamentId),
              if (row.totalRounds > 0) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _Bracket(tournamentId: widget.tournamentId),
              ],
              if (row.status == AutoTournamentStatus.completed) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _Results(tournamentId: widget.tournamentId),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top card: status, counts, countdown and the one thing to press.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.tournament,
    required this.busy,
    required this.onRegister,
    required this.onWithdraw,
    required this.onCheckIn,
    required this.onEnterMatch,
    required this.onDeadlinePassed,
  });

  final AutoTournament tournament;
  final bool busy;
  final VoidCallback onRegister;
  final VoidCallback onWithdraw;
  final VoidCallback onCheckIn;
  final void Function(ViewerMatch match) onEnterMatch;
  final VoidCallback onDeadlinePassed;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final ViewerTournamentState viewer = tournament.viewer;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${tournament.dailySlot.label}'
                  '  ·  ${TimeUtils.formatClock(tournament.startAtMs)}'
                  '  ·  ${context.l10n.tournamentFormatKnockout}',
                  style: text.bodySmall?.copyWith(color: colors.textFaint),
                ),
              ),
              TournamentStatusChip(status: tournament.status),
            ],
          ),
          if (tournament.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              tournament.description,
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          TournamentPlayerCounts(tournament: tournament),

          if (tournament.status == AutoTournamentStatus.running &&
              tournament.totalRounds > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${context.l10n.tournamentRound} '
              '${tournament.currentRound} / ${tournament.totalRounds}',
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],

          if (tournament.activeDeadlineMs != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TournamentCountdown(
              // The same three-way answer the card gives, because the clock
              // means the same thing on both screens: before the window it is
              // counting to joining, inside it to the window closing, and in
              // check-in to the published start.
              label: switch (tournament.status) {
                AutoTournamentStatus.upcoming =>
                  context.l10n.tournamentJoiningOpensIn,
                AutoTournamentStatus.registration =>
                  context.l10n.tournamentClosesIn,
                AutoTournamentStatus.checkIn =>
                  context.l10n.tournamentStartsIn,
                _ => context.l10n.tournamentStartsIn,
              },
              deadlineMs: tournament.activeDeadlineMs!,
              onElapsed: onDeadlinePassed,
            ),
          ],

          if (tournament.cancelReason != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${context.l10n.tournamentCancelledBecause} '
              '${tournament.cancelReason}',
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
          ],

          if (tournament.winner != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                const TrophyMark(size: 28),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${context.l10n.tournamentWinner} '
                    '${tournament.winner!.displayName}'
                    '${tournament.winner!.isBot ? ' 🤖' : ''}',
                    style: text.titleSmall?.copyWith(color: colors.text),
                  ),
                ),
              ],
            ),
          ],

          if (viewer.blockedReason != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              viewer.blockedReason!,
              style: text.bodySmall?.copyWith(color: colors.warning),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          _PrimaryAction(
            tournament: tournament,
            busy: busy,
            onRegister: onRegister,
            onWithdraw: onWithdraw,
            onCheckIn: onCheckIn,
            onEnterMatch: onEnterMatch,
          ),
        ],
      ),
    );
  }
}

/// The one thing this player should press, if anything.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.tournament,
    required this.busy,
    required this.onRegister,
    required this.onWithdraw,
    required this.onCheckIn,
    required this.onEnterMatch,
  });

  final AutoTournament tournament;
  final bool busy;
  final VoidCallback onRegister;
  final VoidCallback onWithdraw;
  final VoidCallback onCheckIn;
  final void Function(ViewerMatch match) onEnterMatch;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final ViewerTournamentState viewer = tournament.viewer;
    final ViewerMatch? match = viewer.activeMatch;

    // A match on a clock beats everything. Missing it costs the tournament.
    if (match != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppButton(
            label: context.l10n.tournamentEnterMatch,
            variant: AppButtonVariant.primary,
            icon: Icons.play_arrow_rounded,
            busy: busy,
            expand: true,
            onPressed: () => onEnterMatch(match),
          ),
          if (match.entryDeadlineMs > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TournamentCountdown(
                label: context.l10n.tournamentEnterWithin,
                deadlineMs: match.entryDeadlineMs,
              ),
            ),
          ],
        ],
      );
    }

    if (viewer.canCheckIn) {
      return AppButton(
        label: context.l10n.tournamentCheckIn,
        variant: AppButtonVariant.primary,
        busy: busy,
        expand: true,
        onPressed: onCheckIn,
      );
    }

    if (viewer.canRegister) {
      return AppButton(
        label: context.l10n.tournamentJoin,
        variant: AppButtonVariant.primary,
        busy: busy,
        expand: true,
        onPressed: onRegister,
      );
    }

    if (viewer.isRegistered) {
      return Row(
        children: <Widget>[
          Icon(Icons.check, size: 18, color: colors.success),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              viewer.isCheckedIn
                  ? context.l10n.tournamentCheckedInShort
                  : context.l10n.tournamentRegisteredShort,
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ),
          if (viewer.canWithdraw)
            TextButton(
              onPressed: busy ? null : onWithdraw,
              child: Text(context.l10n.tournamentWithdraw),
            ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

/// What this tournament's rules actually are.
///
/// Read from the tournament row rather than hardcoded, because the row carries
/// the rules it was *created* under — a tournament taking registrations keeps
/// what it advertised even if the deployment is reconfigured mid-window.
class _Rules extends StatelessWidget {
  const _Rules({required this.tournament});

  final AutoTournament tournament;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    final List<(String, String)> rows = <(String, String)>[
      (context.l10n.tournamentFormatKnockout, '${tournament.totalRounds > 0 ? tournament.totalRounds : '–'}'),
      (context.l10n.tournamentPlayers,
          '–'),
      (context.l10n.tournamentAiPlayers,
          tournament.allowBots ? 'up to ${tournament.maxBots}' : 'none'),
      (context.l10n.tournamentFreeEntry, '✓'),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tournamentRules,
            style: text.titleSmall?.copyWith(color: colors.text),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (String label, String value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ),
                  Text(
                    value,
                    style: text.bodySmall?.copyWith(color: colors.text),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Everybody in the tournament.
class _Roster extends ConsumerWidget {
  const _Roster({required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<TournamentParticipant>> roster =
        ref.watch(tournamentParticipantsProvider(tournamentId));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tournamentPlayers,
            style: text.titleSmall?.copyWith(color: colors.text),
          ),
          const SizedBox(height: AppSpacing.sm),
          roster.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: AppLoadingState(),
            ),
            error: (Object error, StackTrace stack) => Text(
              error is Failure ? error.message : context.l10n.errorUnknown,
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
            data: (List<TournamentParticipant> players) => players.isEmpty
                ? Text(
                    context.l10n.tournamentBoardEmpty,
                    style: text.bodySmall?.copyWith(color: colors.textMuted),
                  )
                : Column(
                    children: <Widget>[
                      for (final TournamentParticipant player in players)
                        TournamentPlayerLine(
                          player: player,
                          trailing: player.seed == null
                              ? null
                              : Text(
                                  '#${player.seed}',
                                  style: text.bodySmall
                                      ?.copyWith(color: colors.textFaint),
                                ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The draw, one round per block.
///
/// ## Why rounds stack rather than fanning out
///
/// A bracket drawn as a tree needs horizontal room a phone does not have, and
/// the usual fix — a pan-and-zoom canvas — makes the one thing a player
/// actually wants (their own next match) harder to find rather than easier.
/// Stacked rounds read top to bottom like everything else in the app, and
/// every match is legible at a glance.
class _Bracket extends ConsumerWidget {
  const _Bracket({required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<TournamentBracket> bracket =
        ref.watch(tournamentBracketProvider(tournamentId));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tournamentBracket,
            style: text.titleSmall?.copyWith(color: colors.text),
          ),
          const SizedBox(height: AppSpacing.sm),
          bracket.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: AppLoadingState(),
            ),
            error: (Object error, StackTrace stack) => Text(
              error is Failure ? error.message : context.l10n.errorUnknown,
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
            data: (TournamentBracket draw) => draw.isEmpty
                ? Text(
                    context.l10n.tournamentAwaiting,
                    style: text.bodySmall?.copyWith(color: colors.textMuted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final TournamentBracketRound round in draw.rounds)
                        _BracketRound(
                          round: round,
                          isCurrent: round.roundNumber == draw.currentRound,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One round of a draw.
class _BracketRound extends StatelessWidget {
  const _BracketRound({required this.round, required this.isCurrent});

  final TournamentBracketRound round;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                round.name,
                style: text.bodyMedium?.copyWith(
                  color: isCurrent ? colors.text : colors.textMuted,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (isCurrent) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final TournamentMatch match in round.matches)
            _MatchCell(match: match),
        ],
      ),
    );
  }
}

/// One pairing.
class _MatchCell extends StatelessWidget {
  const _MatchCell({required this.match});

  final TournamentMatch match;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    final bool decided = match.status == TournamentMatchStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: Border.all(
          // A match this player is in is the one thing on the page they need to
          // find, so it is the only cell that gets a drawn border.
          color: match.roomCode != null ? colors.success : colors.border,
          width: match.roomCode != null
              ? AppSpacing.border
              : AppSpacing.hairline,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        children: <Widget>[
          _MatchSeat(
            player: match.playerA,
            score: decided ? match.scoreA : null,
            isWinner: decided &&
                match.winnerRegistrationId == match.playerA?.registrationId,
          ),
          Divider(height: AppSpacing.sm, color: colors.textFaint, thickness: 0.5),
          _MatchSeat(
            player: match.playerB,
            score: decided ? match.scoreB : null,
            isWinner: decided &&
                match.winnerRegistrationId == match.playerB?.registrationId,
          ),
          if (match.isBye || match.isWalkover) ...<Widget>[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                match.isBye
                    ? context.l10n.tournamentBye
                    : context.l10n.tournamentWalkover,
                style: text.bodySmall?.copyWith(color: colors.textFaint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One seat of a pairing, or the fact that it is not decided yet.
class _MatchSeat extends StatelessWidget {
  const _MatchSeat({
    required this.player,
    required this.score,
    required this.isWinner,
  });

  final TournamentParticipant? player;
  final int? score;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    if (player == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Icon(Icons.more_horiz, size: 18, color: colors.textFaint),
            const SizedBox(width: AppSpacing.sm),
            Text(
              context.l10n.tournamentAwaiting,
              style: text.bodySmall?.copyWith(color: colors.textFaint),
            ),
          ],
        ),
      );
    }

    return TournamentPlayerLine(
      player: player!,
      dense: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isWinner)
            Icon(Icons.check, size: 15, color: colors.success)
          else if (score != null)
            const SizedBox(width: 15),
          if (score != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$score',
              style: text.bodySmall?.copyWith(
                color: isWinner ? colors.text : colors.textMuted,
                fontWeight: isWinner ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The placement table, once the tournament is over.
class _Results extends ConsumerWidget {
  const _Results({required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<TournamentParticipant>> results =
        ref.watch(tournamentResultsProvider(tournamentId));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tournamentResults,
            style: text.titleSmall?.copyWith(color: colors.text),
          ),
          const SizedBox(height: AppSpacing.sm),
          results.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: AppLoadingState(),
            ),
            error: (Object error, StackTrace stack) => Text(
              error is Failure ? error.message : context.l10n.errorUnknown,
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
            data: (List<TournamentParticipant> rows) => Column(
              children: <Widget>[
                for (final TournamentParticipant row in rows)
                  TournamentPlayerLine(
                    player: row,
                    trailing: Text(
                      '${row.placement}',
                      style: text.bodyMedium?.copyWith(color: colors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
