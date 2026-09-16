import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/social.dart';

/// `GET /api/leaderboard/*` — the server-ranked boards.
///
/// ## How this relates to the local hall of fame
///
/// `LeaderboardRepository` and its `LocalLeaderboardRepository` are a private,
/// on-device history: what *this* player has scored, kept in preferences, for
/// a board that works offline and with no account. This class is the other
/// thing entirely — the shared ranking every player is on, computed by the
/// server from match results it produced itself.
///
/// They are not merged, and the local one is not replaced, because they answer
/// different questions and fail differently: the local board is always
/// available and never comparable, the server board is comparable and needs a
/// network. The leaderboard screen shows the server boards and keeps the local
/// history reachable beneath them.
///
/// Nothing here throws. Failures come back as [Err] like every other transport
/// in this app.
class LeaderboardApi {
  /// Creates the API over [client].
  const LeaderboardApi(this._client);

  final ApiClient _client;

  /// One page of the board for [scope].
  ///
  /// The world board is readable signed out; friends and locality are not, and
  /// answer `AppErrorCode.invalidAction` without a session. The caller's own
  /// rank rides along on the page rather than needing [myRank], so a screen
  /// that is showing a board never makes two requests for it.
  Future<Result<LeaderboardPage>> page(
    LeaderboardScope scope, {
    int page = 1,
    int limit = 25,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/leaderboard/${scope.wire}',
      query: <String, String>{'page': '$page', 'limit': '$limit'},
    );

    return response.map(LeaderboardPage.fromJson);
  }

  /// The local player's standing in [scope], without a page of rows.
  ///
  /// For showing "you are 4,212nd" without paging to find them. The board
  /// endpoints already carry this, so it is only needed where no board is
  /// loaded — the home screen, say.
  Future<Result<({int? rank, int total, RankedPlayer? entry})>> myRank(
    LeaderboardScope scope,
  ) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/leaderboard/me/rank',
      query: <String, String>{'scope': scope.wire},
    );

    return response.map((Map<String, dynamic> data) {
      final Object? entry = data['entry'];
      return (
        rank: data['rank'] is num ? (data['rank'] as num).toInt() : null,
        total: data['total'] is num ? (data['total'] as num).toInt() : 0,
        entry: entry is Map
            ? RankedPlayer.fromJson(Map<String, dynamic>.from(entry))
            : null,
      );
    });
  }
}
