import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/leaderboard_entry.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/social_widgets.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The leaderboard: World, Friends and Locality.
///
/// ## Three tabs, three independent loads
///
/// Each tab owns its own `rankingProvider` family entry, so switching between
/// them does not reload a board that is already loaded and a failure on one
/// does not blank the others. The tab controller is kept rather than rebuilt
/// so the scroll position of each list survives a switch.
///
/// ## The pinned footer
///
/// The player's own row sits below the list whatever page they are on. That is
/// the whole reason the server computes `currentUserRank` separately from the
/// page: somebody in four-thousandth place should not have to scroll there to
/// find out where they stand.
class LeaderboardScreen extends ConsumerStatefulWidget {
  /// Creates the leaderboard screen.
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: LeaderboardScope.values.length,
    vsync: this,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return SketchScaffold(
      title: context.l10n.leaderboardTitle,
      padded: false,
      constrained: false,
      actions: <Widget>[
        // The on-device history predates the server boards and still records
        // every finished match. It is kept reachable here rather than deleted:
        // it is the only board that works offline and without an account.
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: context.l10n.leaderboardLocalHistory,
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: colors.paper,
            builder: (BuildContext sheetContext) => const _LocalHistorySheet(),
          ),
        ),
      ],
      child: Column(
        children: <Widget>[
          TabBar(
            controller: _tabs,
            labelColor: colors.ink,
            unselectedLabelColor: colors.inkSoft,
            indicatorColor: colors.ink,
            tabs: <Widget>[
              for (final LeaderboardScope scope in LeaderboardScope.values)
                Tab(text: scope.label),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: <Widget>[
                for (final LeaderboardScope scope in LeaderboardScope.values)
                  _Board(scope: scope),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab: a paged list, a pinned self row, and the states in between.
class _Board extends ConsumerStatefulWidget {
  const _Board({required this.scope});

  final LeaderboardScope scope;

  @override
  ConsumerState<_Board> createState() => _BoardState();
}

class _BoardState extends ConsumerState<_Board>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();

  // Keeps each tab alive so its scroll position and loaded pages survive a
  // switch to another tab and back.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Asks for the next page a screenful before the end of this one.
  ///
  /// `loadMore` is a no-op while a page is in flight or the board is
  /// exhausted, so firing this on every scroll frame is safe.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final double remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 600) {
      ref.read(rankingProvider(widget.scope).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final AsyncValue<LeaderboardPage> board =
        ref.watch(rankingProvider(widget.scope));

    return board.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => SketchEmptyState(
        // The server writes messages for players, so its own wording is used
        // rather than a generic one whenever there is one.
        message: error is Failure ? error.message : context.l10n.errorUnknown,
        icon: Icons.cloud_off_outlined,
        action: SketchButton(
          label: context.l10n.retry,
          onPressed: () =>
              ref.read(rankingProvider(widget.scope).notifier).refresh(),
        ),
      ),
      data: _buildBoard,
    );
  }

  Widget _buildBoard(LeaderboardPage page) {
    if (page.needsLocality) return const _LocalityPrompt();

    if (page.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () =>
            ref.read(rankingProvider(widget.scope).notifier).refresh(),
        // A refresh indicator needs something scrollable behind it, and an
        // empty state is not one — hence the single-child scroll view.
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            SketchEmptyState(
              message: switch (widget.scope) {
                LeaderboardScope.friends => context.l10n.leaderboardFriendsEmpty,
                LeaderboardScope.locality =>
                  context.l10n.leaderboardLocalityEmpty,
                LeaderboardScope.world => context.l10n.leaderboardEmpty,
              },
              icon: Icons.emoji_events_outlined,
              action: widget.scope == LeaderboardScope.friends
                  ? SketchButton(
                      label: context.l10n.friendsTitle,
                      icon: Icons.group_outlined,
                      onPressed: () =>
                          context.pushNamed(AppRoutes.friends),
                    )
                  : null,
            ),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(rankingProvider(widget.scope).notifier).refresh(),
            child: ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              // One extra row at the end is the "loading more" spinner.
              itemCount: page.items.length + (page.hasMore ? 1 : 0),
              itemBuilder: (BuildContext context, int index) {
                if (index >= page.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _Row(row: page.items[index], scope: widget.scope);
              },
            ),
          ),
        ),
        _SelfFooter(page: page),
      ],
    );
  }
}

/// One leaderboard row.
class _Row extends StatelessWidget {
  const _Row({required this.row, required this.scope});

  final RankedPlayer row;
  final LeaderboardScope scope;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    // The locality board is the only one where a row's town is worth showing:
    // everywhere else every row would read the same or read nothing.
    final String? subtitle = scope == LeaderboardScope.locality
        ? row.locality?.display
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        children: <Widget>[
          PlayerTile(
            card: row.card,
            subtitle: subtitle == null || subtitle.isEmpty ? null : subtitle,
            highlight: row.isSelf,
            leading: RankBadge(rank: row.rank),
            // The local player's own profile is reached from the profile
            // screen, so tapping their own row here would be a loop.
            onTap: row.isSelf
                ? null
                : () => context.pushNamed(
                      AppRoutes.playerProfile,
                      pathParameters: <String, String>{'userId': row.card.id},
                    ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${row.stats.totalScore}',
                  style: text.titleMedium?.copyWith(color: colors.ink),
                ),
                RankChange(change: row.rankChange),
              ],
            ),
          ),
          // The podium gets its record spelled out; the long tail stays
          // compact so the list is scannable.
          if (row.isSelf || row.isPodium)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: StatsStrip(stats: row.stats),
            ),
        ],
      ),
    );
  }
}

/// The pinned row showing where the local player stands.
class _SelfFooter extends StatelessWidget {
  const _SelfFooter({required this.page});

  final LeaderboardPage page;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    final RankedPlayer? self = page.currentUserEntry;

    // Signed out, or never finished a game. Either way there is no rank to
    // pin, and an invented one would be worse than none.
    if (self == null) {
      if (page.currentUserRank != null) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.paperDim,
          border: Border(top: BorderSide(color: colors.inkFaint)),
        ),
        child: Text(
          context.l10n.leaderboardUnranked,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: colors.inkSoft),
        ),
      );
    }

    // Already visible in the list, so pinning it again would be a duplicate.
    final bool onPage =
        page.items.any((RankedPlayer row) => row.card.id == self.card.id);
    if (onPage) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.paper,
        border: Border(top: BorderSide(color: colors.inkFaint)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              context.l10n.leaderboardYourRank.toUpperCase(),
              style: text.labelSmall?.copyWith(color: colors.inkSoft),
            ),
          ),
          PlayerTile(
            card: self.card,
            highlight: true,
            leading: RankBadge(rank: self.rank),
            trailing: Text(
              '${self.stats.totalScore}',
              style: text.titleMedium?.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown on the locality tab when the player has not said where they play.
class _LocalityPrompt extends StatelessWidget {
  const _LocalityPrompt();

  @override
  Widget build(BuildContext context) {
    return SketchEmptyState(
      message: context.l10n.leaderboardNeedsLocality,
      icon: Icons.location_city_outlined,
      action: SketchButton(
        label: context.l10n.leaderboardSetLocality,
        icon: Icons.edit_location_alt_outlined,
        onPressed: () => context.pushNamed(AppRoutes.profile),
      ),
    );
  }
}

/// The on-device hall of fame, kept from before the server boards existed.
///
/// Its own sheet rather than a fourth tab, because it is a different kind of
/// thing: a private record of what this device has scored, not a ranking
/// anybody else is on. It is also the only board that works with no network
/// and no account, which is why it is kept rather than folded into the world
/// board — and why clearing it lives here, beside the data it clears.
class _LocalHistorySheet extends ConsumerWidget {
  const _LocalHistorySheet();

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final bool yes = await confirm(
      context,
      title: context.l10n.leaderboardClearTitle,
      message: context.l10n.leaderboardClearBody,
      confirmLabel: context.l10n.leaderboardClear,
      destructive: true,
    );
    if (yes) {
      await ref.read(leaderboardProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<LeaderboardEntry>> entries =
        ref.watch(leaderboardProvider);
    final String selfId = ref.watch(selfIdProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (BuildContext context, ScrollController scroll) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    context.l10n.leaderboardLocalHistory,
                    style: text.titleMedium?.copyWith(color: colors.ink),
                  ),
                ),
                if (entries.valueOrNull?.isNotEmpty ?? false)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: context.l10n.leaderboardClear,
                    onPressed: () => _clear(context, ref),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stack) => SketchEmptyState(
                message: context.l10n.errorStorage,
                icon: Icons.error_outline,
                action: SketchButton(
                  label: context.l10n.retry,
                  onPressed: () =>
                      ref.read(leaderboardProvider.notifier).refresh(),
                ),
              ),
              data: (List<LeaderboardEntry> rows) {
                if (rows.isEmpty) {
                  return SketchEmptyState(
                    message: context.l10n.leaderboardEmpty,
                    icon: Icons.emoji_events_outlined,
                  );
                }
                return ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int index) {
                    final LeaderboardEntry entry = rows[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: PlayerTile(
                        card: UserCard(
                          id: entry.playerId,
                          name: entry.name,
                          avatarId: entry.avatarId,
                          avatarColorIndex: entry.avatarColorIndex,
                        ),
                        highlight: entry.playerId == selfId,
                        leading: RankBadge(rank: index + 1),
                        subtitle: '${entry.gamesPlayed} games · '
                            '${entry.wins} wins',
                        trailing: Text(
                          '${entry.totalScore}',
                          style: text.titleMedium?.copyWith(color: colors.ink),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
