import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/features/friends/friend_requests_screen.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/social_widgets.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Friends, requests and blocked players.
///
/// Three tabs over one [friendsProvider] snapshot, because the screens are
/// read together: the Requests tab wears the count the Friends tab needs, and
/// every action refreshes all of them at once.
///
/// Search lives in a sheet rather than a fourth tab. It is a thing you do
/// occasionally and then leave, not a place you sit, and giving it a tab would
/// leave an empty search field taking up a quarter of the screen for everybody
/// who came here to answer a request.
class FriendsScreen extends ConsumerStatefulWidget {
  /// Creates the friends screen.
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final int pending = ref.watch(pendingRequestCountProvider);

    return SketchScaffold(
      title: context.l10n.friendsTitle,
      padded: false,
      constrained: false,
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.person_search_outlined),
          tooltip: context.l10n.friendsSearchHint,
          onPressed: () => _openSearch(context),
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
              Tab(text: context.l10n.friendsTabFriends),
              Tab(
                child: CountBadge(
                  count: pending,
                  child: Text(context.l10n.friendsTabRequests),
                ),
              ),
              Tab(text: context.l10n.friendsTabBlocked),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const <Widget>[
                _FriendsTab(),
                FriendRequestsView(),
                _BlockedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.sketch.paper,
      builder: (BuildContext sheetContext) => const _SearchSheet(),
    );
  }
}

/// The accepted friends list.
class _FriendsTab extends ConsumerStatefulWidget {
  const _FriendsTab();

  @override
  ConsumerState<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends ConsumerState<_FriendsTab> {
  final ScrollController _scroll = ScrollController();

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

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent - _scroll.position.pixels < 400) {
      ref.read(friendsProvider.notifier).loadMoreFriends();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<FriendsState> friends = ref.watch(friendsProvider);

    return friends.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => SketchEmptyState(
        message: error is Failure ? error.message : context.l10n.errorUnknown,
        icon: Icons.cloud_off_outlined,
        action: SketchButton(
          label: context.l10n.retry,
          onPressed: () => ref.read(friendsProvider.notifier).refresh(),
        ),
      ),
      data: (FriendsState state) {
        if (state.friends.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                SketchEmptyState(
                  message: context.l10n.friendsEmpty,
                  icon: Icons.group_outlined,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: state.friends.length,
            itemBuilder: (BuildContext context, int index) {
              final Friend friend = state.friends[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: PlayerTile(
                  card: friend.card,
                  subtitle:
                      '${friend.stats.totalScore} pts · ${friend.stats.winRateLabel} wins',
                  onTap: () => context.pushNamed(
                    AppRoutes.playerProfile,
                    pathParameters: <String, String>{'userId': friend.card.id},
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: context.sketch.inkSoft,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The blocked list, with a way back out of each block.
class _BlockedTab extends ConsumerWidget {
  const _BlockedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FriendsState> friends = ref.watch(friendsProvider);
    final List<BlockedPlayer> blocked =
        friends.valueOrNull?.blocked ?? const <BlockedPlayer>[];

    if (friends.isLoading && blocked.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (blocked.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            SketchEmptyState(
              message: context.l10n.friendsBlockedEmpty,
              icon: Icons.block_outlined,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: blocked.length,
        itemBuilder: (BuildContext context, int index) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _BlockedRow(entry: blocked[index]),
        ),
      ),
    );
  }
}

class _BlockedRow extends ConsumerStatefulWidget {
  const _BlockedRow({required this.entry});

  final BlockedPlayer entry;

  @override
  ConsumerState<_BlockedRow> createState() => _BlockedRowState();
}

class _BlockedRowState extends ConsumerState<_BlockedRow> {
  bool _busy = false;

  Future<void> _unblock() async {
    if (_busy) return;

    // Confirmed because unblocking is not symmetric with blocking: it opens
    // the door again without restoring anything, and somebody who tapped it by
    // accident cannot simply undo it.
    final bool yes = await confirm(
      context,
      title: context.l10n.friendUnblockTitle,
      message: context.l10n.friendUnblockBody,
      confirmLabel: context.l10n.friendUnblock,
    );
    if (!yes || !mounted) return;

    setState(() => _busy = true);

    final Result<void> result =
        await ref.read(friendActionsProvider).unblock(widget.entry.card.id);

    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err<void>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlayerTile(
      card: widget.entry.card,
      subtitle: context.l10n.friendBlocked,
      trailing: SketchButton(
        label: context.l10n.friendUnblock,
        busy: _busy,
        onPressed: _busy ? null : _unblock,
      ),
    );
  }
}

/// The user-search sheet.
///
/// Debounced rather than searching on every keystroke: the endpoint is rate
/// limited and the query is the expensive one in the feature, so a burst of
/// typing should produce one request rather than one per letter.
class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  static const Duration _debounce = Duration(milliseconds: 350);

  final TextEditingController _field = TextEditingController();

  Timer? _timer;
  List<SearchResult> _results = const <SearchResult>[];
  bool _searching = false;
  Failure? _failure;
  String _lastTerm = '';

  @override
  void dispose() {
    _timer?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String term) {
    _timer?.cancel();
    final String trimmed = term.trim();

    if (trimmed.length < 2) {
      setState(() {
        _results = const <SearchResult>[];
        _failure = null;
        _lastTerm = trimmed;
      });
      return;
    }

    _timer = Timer(_debounce, () => _search(trimmed));
  }

  Future<void> _search(String term) async {
    setState(() {
      _searching = true;
      _failure = null;
      _lastTerm = term;
    });

    final Result<List<SearchResult>> result =
        await ref.read(friendActionsProvider).search(term);

    if (!mounted) return;

    // A response for a term the player has already typed past is discarded:
    // two requests can land out of order, and showing the older one would
    // silently contradict what is in the field.
    if (term != _lastTerm) return;

    setState(() {
      _searching = false;
      _results = result.valueOr(const <SearchResult>[]);
      _failure = result.failureOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Padding(
      // Lifts the sheet clear of the keyboard, so the field stays visible.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (BuildContext context, ScrollController scroll) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TextField(
                controller: _field,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (String term) => _search(term.trim()),
                decoration: InputDecoration(
                  hintText: context.l10n.friendsSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide(
                      color: colors.ink,
                      width: AppSpacing.border,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: _body(scroll)),
          ],
        ),
      ),
    );
  }

  Widget _body(ScrollController scroll) {
    if (_failure != null) {
      return SketchEmptyState(
        message: _failure!.message,
        icon: Icons.cloud_off_outlined,
        action: SketchButton(
          label: context.l10n.retry,
          onPressed: () => _search(_lastTerm),
        ),
      );
    }

    if (_lastTerm.length < 2) {
      return SketchEmptyState(
        message: context.l10n.friendsSearchPrompt,
        icon: Icons.search,
      );
    }

    if (_results.isEmpty) {
      return SketchEmptyState(
        message:
            _searching ? context.l10n.loading : context.l10n.friendsSearchEmpty,
        icon: Icons.person_off_outlined,
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
      itemCount: _results.length,
      itemBuilder: (BuildContext context, int index) {
        final SearchResult result = _results[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: PlayerTile(
            card: result.card,
            subtitle: '${result.stats.totalScore} pts',
            onTap: () => context.pushNamed(
              AppRoutes.playerProfile,
              pathParameters: <String, String>{'userId': result.card.id},
            ),
            trailing: _SearchAction(result: result),
          ),
        );
      },
    );
  }
}

/// The one button a search row offers, chosen by the server's relation.
class _SearchAction extends ConsumerStatefulWidget {
  const _SearchAction({required this.result});

  final SearchResult result;

  @override
  ConsumerState<_SearchAction> createState() => _SearchActionState();
}

class _SearchActionState extends ConsumerState<_SearchAction> {
  bool _busy = false;
  bool _sent = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);

    final Result<void> result = await ref
        .read(friendActionsProvider)
        .sendRequest(widget.result.card.id);

    if (!mounted) return;

    setState(() {
      _busy = false;
      // Only on success. The row is not re-fetched — the sheet holds a local
      // result list — so this is the one place the screen remembers something
      // the server told it, and it remembers it only after being told.
      _sent = result.isOk;
    });

    if (result case Err<void>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SocialRelation relation =
        _sent ? SocialRelation.requestSent : widget.result.relation;

    return switch (relation) {
      SocialRelation.friends => _Tag(label: context.l10n.friendsAlready),
      SocialRelation.requestSent =>
        _Tag(label: context.l10n.friendRequested),
      SocialRelation.requestReceived =>
        _Tag(label: context.l10n.friendRequestsIncoming),
      SocialRelation.blocked => _Tag(label: context.l10n.friendBlocked),
      SocialRelation.self => const SizedBox.shrink(),
      SocialRelation.none => SketchButton(
          label: context.l10n.friendAdd,
          icon: Icons.person_add_alt,
          busy: _busy,
          onPressed: _busy ? null : _add,
        ),
    };
  }
}

/// A read-only state label where a button would otherwise be.
class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: context.sketch.inkSoft),
    );
  }
}
