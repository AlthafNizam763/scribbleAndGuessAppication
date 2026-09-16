import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/social_api.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/ranking_provider.dart';

/// Friends, requests and blocks.
///
/// ## Where the truth is
///
/// The server. Every list here is a cache of a REST read, and every action is
/// a REST call whose response decides what happened — nothing is applied
/// locally and then hoped for. After a successful action the affected lists
/// are re-read rather than edited in place: accepting a request changes three
/// lists at once (incoming shrinks, friends grows, the friends leaderboard
/// re-ranks), and patching all three by hand is how they drift apart.
///
/// The one thing that *is* optimistic is the in-flight button state in
/// [FriendActions], and only because it is undone by the refresh either way.
///
/// ## Realtime is a hint, never the transport
///
/// `s:friend:*` pushes only say "your lists are stale". They carry no
/// authority and are not parsed into list entries — [friendEventsProvider]
/// watches them and invalidates, and the REST read that follows is what the
/// screen actually renders. So a missed push costs a refresh and nothing else,
/// which matters because the realtime server may be deployed separately from
/// the REST API and may be restarting.

/// The friends, blocks and user endpoints.
final Provider<SocialApi> socialApiProvider = Provider<SocialApi>(
  (Ref ref) => SocialApi(ref.watch(apiClientProvider)),
);

/// Which friend list a notifier holds.
enum FriendListKind {
  /// Accepted friends.
  friends,

  /// Requests waiting on the local player.
  incoming,

  /// Requests the local player is waiting on.
  outgoing,

  /// Players the local player has blocked.
  blocked,
}

/// Everything the friends screens render, in one snapshot.
///
/// A single state object rather than four providers because the screens show
/// them together — the requests tab wears a badge counting [incoming], and the
/// friends tab has to know who is blocked to avoid offering to re-add them —
/// and because they are refreshed together after every action.
class FriendsState {
  /// Creates a friends snapshot.
  const FriendsState({
    this.friends = const <Friend>[],
    this.incoming = const <FriendRequest>[],
    this.outgoing = const <FriendRequest>[],
    this.blocked = const <BlockedPlayer>[],
    this.friendsHasMore = false,
    this.friendsPage = 1,
  });

  /// Accepted friends, most recently added first.
  final List<Friend> friends;

  /// Requests waiting on the local player.
  final List<FriendRequest> incoming;

  /// Requests the local player is waiting on.
  final List<FriendRequest> outgoing;

  /// Players the local player has blocked.
  final List<BlockedPlayer> blocked;

  /// Whether the friends list has another page.
  final bool friendsHasMore;

  /// The last friends page loaded.
  final int friendsPage;

  /// How many requests are waiting, for the badge on the Friends button.
  int get pendingCount => incoming.length;

  /// Returns a copy with the given fields replaced.
  FriendsState copyWith({
    List<Friend>? friends,
    List<FriendRequest>? incoming,
    List<FriendRequest>? outgoing,
    List<BlockedPlayer>? blocked,
    bool? friendsHasMore,
    int? friendsPage,
  }) =>
      FriendsState(
        friends: friends ?? this.friends,
        incoming: incoming ?? this.incoming,
        outgoing: outgoing ?? this.outgoing,
        blocked: blocked ?? this.blocked,
        friendsHasMore: friendsHasMore ?? this.friendsHasMore,
        friendsPage: friendsPage ?? this.friendsPage,
      );
}

/// The friends screens' data.
class FriendsNotifier extends AsyncNotifier<FriendsState> {
  static const int _pageSize = 25;

  bool _loadingMore = false;

  SocialApi get _api => ref.read(socialApiProvider);

  @override
  Future<FriendsState> build() async {
    // Keeps the lists live while any friends screen is open, without making
    // the first load wait on a socket that may not be connected: `listen`
    // subscribes and moves on, where `watch` would rebuild this provider on
    // every push and re-enter `_load` from the top.
    ref.listen<AsyncValue<String>>(
      friendEventsProvider,
      (AsyncValue<String>? previous, AsyncValue<String> next) {
        if (next.hasValue) unawaited(refresh());
      },
    );

    return _load();
  }

  Future<FriendsState> _load() async {
    // Four independent reads, so they go out together rather than one after
    // another: the requests tab should not wait on the block list.
    final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
      _api.friends(limit: _pageSize),
      _api.incoming(limit: _pageSize),
      _api.outgoing(limit: _pageSize),
      _api.blocks(limit: _pageSize),
    ]);

    final Result<SocialPage<Friend>> friends =
        results[0] as Result<SocialPage<Friend>>;
    final Result<SocialPage<FriendRequest>> incoming =
        results[1] as Result<SocialPage<FriendRequest>>;
    final Result<SocialPage<FriendRequest>> outgoing =
        results[2] as Result<SocialPage<FriendRequest>>;
    final Result<SocialPage<BlockedPlayer>> blocked =
        results[3] as Result<SocialPage<BlockedPlayer>>;

    // The friends list is the one the screen cannot do without, so only its
    // failure is fatal. A blocks read that failed leaves that tab empty rather
    // than taking down a screen the player opened to answer a request.
    if (friends case Err<SocialPage<Friend>>(:final Failure failure)) {
      throw failure;
    }

    final SocialPage<Friend> friendPage =
        friends.valueOrNull ?? const SocialPage<Friend>();

    return FriendsState(
      friends: friendPage.items,
      incoming: incoming.valueOrNull?.items ?? const <FriendRequest>[],
      outgoing: outgoing.valueOrNull?.items ?? const <FriendRequest>[],
      blocked: blocked.valueOrNull?.items ?? const <BlockedPlayer>[],
      friendsHasMore: friendPage.hasMore,
      friendsPage: friendPage.page,
    );
  }

  /// Re-reads every list. Used by pull-to-refresh and after every action.
  ///
  /// Keeps the rows on screen while it runs, so a refresh of an unchanged list
  /// does not flash empty.
  Future<void> refresh() async {
    try {
      state = AsyncValue<FriendsState>.data(await _load());
    } on Failure catch (failure, stack) {
      state = AsyncValue<FriendsState>.error(failure, stack);
    }
  }

  /// Appends the next page of friends.
  Future<void> loadMoreFriends() async {
    final FriendsState? current = state.valueOrNull;
    if (current == null || !current.friendsHasMore || _loadingMore) return;

    _loadingMore = true;
    try {
      final Result<SocialPage<Friend>> result =
          await _api.friends(page: current.friendsPage + 1, limit: _pageSize);

      if (result case Ok<SocialPage<Friend>>(:final SocialPage<Friend> value)) {
        state = AsyncValue<FriendsState>.data(
          current.copyWith(
            friends: <Friend>[...current.friends, ...value.items],
            friendsHasMore: value.hasMore,
            friendsPage: value.page,
          ),
        );
      }
    } finally {
      _loadingMore = false;
    }
  }
}

/// Friends, requests and blocks, as the screens read them.
final AsyncNotifierProvider<FriendsNotifier, FriendsState> friendsProvider =
    AsyncNotifierProvider<FriendsNotifier, FriendsState>(FriendsNotifier.new);

/// How many requests are waiting, for the badge on the home screen.
///
/// Zero while the lists are loading or failed, which is the right default: a
/// badge that guesses is worse than no badge.
final Provider<int> pendingRequestCountProvider = Provider<int>(
  (Ref ref) => ref.watch(friendsProvider).valueOrNull?.pendingCount ?? 0,
);

/// Every friend action, and the refresh that follows each one.
///
/// ## Why the actions are not on `FriendsNotifier`
///
/// They are called from screens that do not show a list — a profile, a search
/// result, a player row in the lobby — and those should not have to load and
/// hold the whole friends state to send one request. Keeping the actions here
/// means a caller reads this provider, calls one method and gets a [Result];
/// whether any list happens to be mounted is not their problem.
class FriendActions {
  /// Creates the action set.
  const FriendActions(this._ref);

  final Ref _ref;

  SocialApi get _api => _ref.read(socialApiProvider);

  /// Asks [userId] to be a friend.
  Future<Result<void>> sendRequest(String userId) =>
      _act(() async => (await _api.sendRequest(userId)).map((_) {}));

  /// Accepts an incoming request.
  Future<Result<void>> accept(String requestId) =>
      _act(() => _api.accept(requestId));

  /// Declines an incoming request.
  Future<Result<void>> reject(String requestId) =>
      _act(() => _api.reject(requestId));

  /// Withdraws an outgoing request.
  Future<Result<void>> cancel(String requestId) =>
      _act(() => _api.cancel(requestId));

  /// Ends a friendship.
  Future<Result<void>> removeFriend(String userId) =>
      _act(() => _api.removeFriend(userId));

  /// Blocks a player, ending any friendship and cancelling any open request.
  Future<Result<void>> block(String userId) => _act(() => _api.block(userId));

  /// Lifts a block. Does not restore the friendship it ended.
  Future<Result<void>> unblock(String userId) =>
      _act(() => _api.unblock(userId));

  /// Another player's profile, including the relation that drives its buttons.
  Future<Result<PublicProfile>> profile(String userId) => _api.profile(userId);

  /// Finds players by the start of their name.
  Future<Result<List<SearchResult>>> search(String term) =>
      _api.searchUsers(term);

  /// Runs an action and, if it succeeded, re-reads everything it could affect.
  ///
  /// The refresh is deliberately broad. Accepting one request changes the
  /// incoming list, the friends list and the friends leaderboard at once, and
  /// working out which of those a given action touched is exactly the
  /// bookkeeping that eventually gets one of them wrong. Four cheap reads are
  /// worth more than a clever invalidation that is right most of the time.
  Future<Result<void>> _act(Future<Result<void>> Function() action) async {
    final Result<void> result = await action();

    if (result.isOk) {
      await _ref.read(friendsProvider.notifier).refresh();
      // The friends board ranks exactly the people that just changed.
      _ref.invalidate(rankingProvider(LeaderboardScope.friends));
    }

    return result;
  }
}

/// The friend actions.
final Provider<FriendActions> friendActionsProvider = Provider<FriendActions>(
  FriendActions.new,
);

/// Friend pushes from the server, as a plain stream of event names.
///
/// ## Why it carries only the name
///
/// The payloads are a nudge, not data: they carry an id and a public card, and
/// the server treats them as fire-and-forget. Building list entries out of
/// them would mean two code paths producing the same rows — one authoritative,
/// one guessed — and the guessed one would be the one on screen.
///
/// So every event means the same thing: the lists are stale. The name is kept
/// only so a listener can log which one arrived.
///
/// ## Why it knows nothing about [friendsProvider]
///
/// [FriendsNotifier] listens to *this*, rather than this reaching back into
/// the notifier. Both arrangements would refresh the lists, but only one is a
/// tree: a provider that is watched by `friendsProvider` and also reads it
/// would be a dependency cycle, which Riverpod is right to refuse. Keeping the
/// edge one-way also means this stream works for any future listener — a badge
/// on another screen, say — without knowing who they are.
final StreamProvider<String> friendEventsProvider = StreamProvider<String>(
  (Ref ref) => ref
      .watch(gatewayProvider)
      .inbound
      .where(
        (({String event, Map<String, dynamic> data}) message) =>
            SocketEvents.friendEvents.contains(message.event),
      )
      .map((({String event, Map<String, dynamic> data}) message) {
    AppLogger.d('Friends: ${message.event}');
    return message.event;
  }),
);
