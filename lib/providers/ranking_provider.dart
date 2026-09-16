import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/leaderboard_api.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/auth_provider.dart';

/// The server-ranked leaderboards.
///
/// ## Why this sits beside `leaderboardProvider` rather than replacing it
///
/// `leaderboardProvider` is the on-device hall of fame: this player's own
/// history, kept in preferences, available offline and with no account. This
/// is the shared ranking computed by the server from match results it produced
/// itself. They answer different questions and fail differently, so both stay
/// and the screen shows the server boards with the local history still
/// reachable underneath.
///
/// ## One notifier per scope
///
/// `rankingProvider` is a family keyed by [LeaderboardScope], so the three tabs
/// hold their own pages, their own scroll position and their own error state.
/// Switching tabs does not reload a board that is already loaded, and a
/// failure on the friends tab does not blank the world tab.

/// The leaderboard endpoints.
final Provider<LeaderboardApi> leaderboardApiProvider = Provider<LeaderboardApi>(
  (Ref ref) => LeaderboardApi(ref.watch(apiClientProvider)),
);

/// One leaderboard tab: its rows, its paging, and the caller's own standing.
class RankingNotifier extends FamilyAsyncNotifier<LeaderboardPage, LeaderboardScope> {
  /// How many rows are fetched per page.
  ///
  /// Matches the server's default. Large enough that the first screen is full
  /// without a second request on any phone, small enough that a slow
  /// connection shows something quickly.
  static const int _pageSize = 25;

  bool _loadingMore = false;

  LeaderboardApi get _api => ref.read(leaderboardApiProvider);

  @override
  Future<LeaderboardPage> build(LeaderboardScope arg) async {
    final Result<LeaderboardPage> result =
        await _api.page(arg, limit: _pageSize);

    return switch (result) {
      Ok<LeaderboardPage>(:final LeaderboardPage value) => value,
      // Thrown rather than returned so the screen's `AsyncValue.error` branch
      // renders, which is where the retry button lives. The failure object
      // itself is carried through, so the message the server wrote is the
      // message the player reads.
      Err<LeaderboardPage>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the first page, for pull-to-refresh.
  ///
  /// Deliberately does not clear the current rows first: a refresh that blanks
  /// the list and then repopulates it makes a board that had not changed look
  /// like it reloaded from nothing.
  Future<void> refresh() async {
    final Result<LeaderboardPage> result =
        await _api.page(arg, limit: _pageSize);

    state = switch (result) {
      Ok<LeaderboardPage>(:final LeaderboardPage value) =>
        AsyncValue<LeaderboardPage>.data(value),
      Err<LeaderboardPage>(:final Failure failure) =>
        AsyncValue<LeaderboardPage>.error(failure, StackTrace.current),
    };
  }

  /// Appends the next page, for infinite scroll.
  ///
  /// A no-op when a page is already in flight, when the board is exhausted, or
  /// before the first page has arrived. Scroll listeners fire often and a
  /// request per frame would be a page of duplicates and a rate limit.
  Future<void> loadMore() async {
    final LeaderboardPage? current = state.valueOrNull;
    if (current == null || !current.hasMore || _loadingMore) return;

    _loadingMore = true;
    try {
      final Result<LeaderboardPage> result = await _api.page(
        arg,
        page: current.page + 1,
        limit: _pageSize,
      );

      // A failed *extra* page leaves the rows already on screen alone. Turning
      // a list the player is reading into a full-screen error because page
      // four timed out would lose their place for nothing.
      if (result case Ok<LeaderboardPage>(:final LeaderboardPage value)) {
        state = AsyncValue<LeaderboardPage>.data(current.appending(value));
      }
    } finally {
      _loadingMore = false;
    }
  }
}

/// The three leaderboard tabs, each holding its own page.
final AsyncNotifierProviderFamily<RankingNotifier, LeaderboardPage, LeaderboardScope>
    rankingProvider =
    AsyncNotifierProviderFamily<RankingNotifier, LeaderboardPage, LeaderboardScope>(
  RankingNotifier.new,
);

/// The local player's world standing, for the home screen.
///
/// Its own provider rather than a read of [rankingProvider] so the home screen
/// does not pull a whole board it will not show. Autodisposes, because it is a
/// snapshot that should be re-read on the next visit rather than cached for
/// the life of the app.
final AutoDisposeFutureProvider<({int? rank, int total, RankedPlayer? entry})>
    myWorldRankProvider =
    FutureProvider.autoDispose<({int? rank, int total, RankedPlayer? entry})>(
  (Ref ref) async {
    final Result<({int? rank, int total, RankedPlayer? entry})> result =
        await ref.watch(leaderboardApiProvider).myRank(LeaderboardScope.world);

    return switch (result) {
      Ok<({int? rank, int total, RankedPlayer? entry})>(:final value) => value,
      Err<({int? rank, int total, RankedPlayer? entry})>(:final Failure failure) =>
        throw failure,
    };
  },
);
