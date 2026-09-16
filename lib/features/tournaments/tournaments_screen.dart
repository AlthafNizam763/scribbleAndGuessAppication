import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/features/tournaments/tournament_widgets.dart';
import 'package:scribble_guess/models/auto_tournament.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The tournament slots.
///
/// ## What this screen does not have
///
/// A create button. There is no admin panel behind it either, and no settings
/// to change — a tournament is created, filled, bracketed, run and replaced by
/// the server, and the only verbs a player has are join, check in, and enter
/// the match they were called to. That is the whole feature, and the absence
/// of everything else is the design rather than a gap in it.
///
/// ## Why every slot is a card, including the empty ones
///
/// Because "three tournaments, always" is the promise, and a slot that is
/// briefly between tournaments should read as *between* rather than as gone.
/// A list that shrank to two rows would look like something had broken; a card
/// that says a new one is on its way looks like what is actually happening.
class TournamentsScreen extends ConsumerWidget {
  /// Creates the screen.
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TournamentSlot>> slots =
        ref.watch(tournamentsProvider);
    final TournamentsNotifier notifier =
        ref.read(tournamentsProvider.notifier);

    return SketchScaffold(
      title: context.l10n.tournamentsTitle,
      padded: false,
      child: slots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => SketchEmptyState(
          message: error is Failure ? error.message : context.l10n.errorUnknown,
          icon: Icons.cloud_off_outlined,
          action: SketchButton(
            label: context.l10n.retry,
            onPressed: notifier.refresh,
          ),
        ),
        data: (List<TournamentSlot> rows) => RefreshIndicator(
          onRefresh: notifier.refresh,
          child: _SlotList(slots: rows),
        ),
      ),
    );
  }
}

/// The slots, with the header and the two secondary actions under them.
class _SlotList extends StatelessWidget {
  const _SlotList({required this.slots});

  final List<TournamentSlot> slots;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    final bool allEmpty =
        slots.isEmpty || slots.every((TournamentSlot slot) => slot.tournament == null);

    return ListView(
      // Always scrollable, so pull-to-refresh works even on a screen with
      // three empty slots on it — which is the state somebody is most likely
      // to want to refresh.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pagePadding(context),
      children: <Widget>[
        Text(
          context.l10n.tournamentAutoSubtitle,
          style: text.bodyMedium?.copyWith(color: colors.inkSoft),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (allEmpty) ...<Widget>[
          // The one case where a per-slot card would be three copies of the
          // same apology. One message reads better than three.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Column(
              children: <Widget>[
                const TrophyMark(size: 56),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.l10n.tournamentNoneRunning,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: colors.ink),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.tournamentNoneRunningHint,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: colors.inkSoft),
                ),
              ],
            ),
          ),
        ] else
          for (final TournamentSlot slot in slots) ...<Widget>[
            _SlotCard(slot: slot),
            const SizedBox(height: AppSpacing.md),
          ],

        const SizedBox(height: AppSpacing.sm),
        // Quick Play, because somebody who finds every slot mid-tournament
        // still came here wanting to draw something.
        SketchButton(
          label: context.l10n.quickPlay,
          icon: Icons.bolt_outlined,
          expand: true,
          onPressed: () => context.goNamed(AppRoutes.home),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// One slot: the tournament in it, or the fact that there is not one.
class _SlotCard extends ConsumerStatefulWidget {
  const _SlotCard({required this.slot});

  final TournamentSlot slot;

  @override
  ConsumerState<_SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends ConsumerState<_SlotCard> {
  bool _busy = false;

  AutoTournament? get _tournament => widget.slot.tournament;

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
        // The server's own sentence, not a generic one. "You are already in
        // Daily Scribble Cup #4" is the refusal a player would otherwise find
        // completely baffling.
        notify(context, failure.message, isError: true);
    }
  }

  void _open() {
    final AutoTournament? tournament = _tournament;
    if (tournament == null) return;

    context.pushNamed(
      AppRoutes.tournamentDetail,
      pathParameters: <String, String>{'tournamentId': tournament.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final AutoTournament? tournament = _tournament;

    if (tournament == null) return _EmptySlotCard(slotNumber: widget.slot.slotNumber);

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
                      '${context.l10n.tournamentSlot} ${tournament.slotNumber}'
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

          if (tournament.activeDeadlineMs != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            TournamentCountdown(
              label: tournament.status == AutoTournamentStatus.registration
                  ? context.l10n.tournamentClosesIn
                  : context.l10n.tournamentCheckInClosesIn,
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

          const SizedBox(height: AppSpacing.md),
          _SlotActions(
            tournament: tournament,
            busy: _busy,
            onJoin: () => _act(
              () => ref
                  .read(tournamentsProvider.notifier)
                  .register(tournament.id),
              context.l10n.tournamentRegistered,
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
}

/// The buttons on a slot card, which depend entirely on the server's `viewer`.
///
/// Nothing here works out whether an action is allowed — `canRegister` and
/// `canCheckIn` arrive decided, because the rules behind them are server
/// rules. A client deriving them would be a second implementation that could
/// disagree, and the disagreement would look like a button that does nothing.
class _SlotActions extends StatelessWidget {
  const _SlotActions({
    required this.tournament,
    required this.busy,
    required this.onJoin,
    required this.onCheckIn,
    required this.onOpen,
  });

  final AutoTournament tournament;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onCheckIn;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final ViewerTournamentState viewer = tournament.viewer;

    // A match waiting for this player beats everything else on the card: they
    // are on a clock, and missing it costs them the tournament.
    if (viewer.activeMatch != null) {
      return SketchButton(
        label: context.l10n.tournamentEnterMatch,
        variant: SketchButtonVariant.primary,
        icon: Icons.play_arrow_rounded,
        expand: true,
        onPressed: onOpen,
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
        else if (viewer.isCheckedIn)
          // A state, not a button: there is nothing to press again.
          Expanded(
            child: Row(
              children: <Widget>[
                Icon(Icons.check, size: 18, color: colors.success),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    context.l10n.tournamentCheckedInShort,
                    style: text.bodyMedium?.copyWith(color: colors.inkSoft),
                  ),
                ),
              ],
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
                    context.l10n.tournamentRegisteredShort,
                    style: text.bodyMedium?.copyWith(color: colors.inkSoft),
                  ),
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

/// A slot between tournaments.
class _EmptySlotCard extends StatelessWidget {
  const _EmptySlotCard({required this.slotNumber});

  final int slotNumber;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return SketchCard(
      child: Row(
        children: <Widget>[
          TrophyMark(size: 36, color: colors.inkFaint),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${context.l10n.tournamentSlot} $slotNumber  ·  '
                  '${context.l10n.tournamentSlotEmpty}',
                  style: text.bodyMedium?.copyWith(color: colors.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.tournamentSlotEmptyHint,
                  style: text.bodySmall?.copyWith(color: colors.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
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
