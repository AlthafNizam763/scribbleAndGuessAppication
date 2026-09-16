import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player_stats.dart';
import 'package:scribble_guess/models/social.dart';

/// `GET/POST/DELETE /api/friends`, `/api/blocks` and `/api/users/*`.
///
/// The transport for the whole friends feature. It owns no rules: every
/// refusal below — you cannot add yourself, that request is not yours to
/// accept, you are already friends — is decided by the server and arrives as a
/// [Failure] with a message written for the player. Duplicating those checks
/// here would give two places for them to disagree, and the client's copy
/// would be the one that was wrong.
///
/// The only identifier this app ever sends about another player is their id.
/// There is no method here that takes a score, a rank, a relation or a
/// friendship status, because all of those are server-owned.
///
/// Nothing throws.
class SocialApi {
  /// Creates the API over [client].
  const SocialApi(this._client);

  final ApiClient _client;

  // --------------------------------------------------------------- people --

  /// Finds players whose name starts with [term].
  ///
  /// The server excludes the local player and anyone a block stands between,
  /// and caps the result count regardless of [limit]. Each result carries its
  /// relation, so a list can draw the right button per row without a request
  /// per row.
  Future<Result<List<SearchResult>>> searchUsers(
    String term, {
    int limit = 25,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/users/search',
      query: <String, String>{'q': term.trim(), 'limit': '$limit'},
    );

    return response.map(
      (Map<String, dynamic> data) => SocialPage<SearchResult>.fromJson(
        data,
        SearchResult.fromJson,
      ).items,
    );
  }

  /// Another player's profile, including the local player's relation to them.
  Future<Result<PublicProfile>> profile(String userId) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/users/$userId/profile');

    return response.map(
      (Map<String, dynamic> data) => PublicProfile.fromJson(
        data['profile'] is Map
            ? Map<String, dynamic>.from(data['profile'] as Map)
            : data,
      ),
    );
  }

  /// Sets the town the local player plays from.
  ///
  /// Passing every field as null clears the locality, which is what drops the
  /// player off that leaderboard.
  Future<Result<void>> updateLocality({
    String? city,
    String? region,
    String? country,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.patch(
      '/api/users/me/locality',
      body: <String, dynamic>{
        'city': city,
        'region': region,
        'country': country,
      },
    );

    return response.map((_) {});
  }

  // -------------------------------------------------------------- requests --

  /// Asks [userId] to be a friend.
  ///
  /// The sender is the session token, never a field in this body.
  Future<Result<FriendRequest>> sendRequest(String userId) async {
    final Result<Map<String, dynamic>> response = await _client.post(
      '/api/friends/requests',
      body: <String, dynamic>{'receiverId': userId},
    );

    return response.map(
      (Map<String, dynamic> data) => FriendRequest.fromJson(
        data['request'] is Map
            ? Map<String, dynamic>.from(data['request'] as Map)
            : data,
      ),
    );
  }

  /// Requests waiting on the local player.
  Future<Result<SocialPage<FriendRequest>>> incoming({
    int page = 1,
    int limit = 25,
  }) =>
      _requests('incoming', page: page, limit: limit);

  /// Requests the local player is waiting on.
  Future<Result<SocialPage<FriendRequest>>> outgoing({
    int page = 1,
    int limit = 25,
  }) =>
      _requests('outgoing', page: page, limit: limit);

  /// Accepts an incoming request. Receiver only, enforced by the server.
  Future<Result<void>> accept(String requestId) =>
      _requestAction(requestId, 'accept');

  /// Declines an incoming request. Receiver only.
  Future<Result<void>> reject(String requestId) =>
      _requestAction(requestId, 'reject');

  /// Withdraws an outgoing request. Sender only.
  Future<Result<void>> cancel(String requestId) =>
      _requestAction(requestId, 'cancel');

  // --------------------------------------------------------------- friends --

  /// The local player's accepted friends.
  Future<Result<SocialPage<Friend>>> friends({
    int page = 1,
    int limit = 25,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/friends',
      query: <String, String>{'page': '$page', 'limit': '$limit'},
    );

    return response.map(
      (Map<String, dynamic> data) =>
          SocialPage<Friend>.fromJson(data, Friend.fromJson),
    );
  }

  /// Ends a friendship. Symmetric — it ends for both people at once.
  Future<Result<void>> removeFriend(String userId) async {
    final Result<Map<String, dynamic>> response =
        await _client.delete('/api/friends/$userId');
    return response.map((_) {});
  }

  // ---------------------------------------------------------------- blocks --

  /// Blocks [userId], ending any friendship and cancelling any open request.
  Future<Result<void>> block(String userId) async {
    final Result<Map<String, dynamic>> response =
        await _client.post('/api/blocks/$userId');
    return response.map((_) {});
  }

  /// Lifts a block. Does not restore the friendship it ended.
  Future<Result<void>> unblock(String userId) async {
    final Result<Map<String, dynamic>> response =
        await _client.delete('/api/blocks/$userId');
    return response.map((_) {});
  }

  /// Who the local player has blocked. Their own list only.
  Future<Result<SocialPage<BlockedPlayer>>> blocks({
    int page = 1,
    int limit = 25,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/blocks',
      query: <String, String>{'page': '$page', 'limit': '$limit'},
    );

    return response.map(
      (Map<String, dynamic> data) =>
          SocialPage<BlockedPlayer>.fromJson(data, BlockedPlayer.fromJson),
    );
  }

  /// One player's full career record.
  ///
  /// Public, like the leaderboard numbers it expands on. `me` is accepted in
  /// place of an id so a client need not know its own.
  Future<Result<PlayerCareerStats>> stats(String userId) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/users/$userId/stats');

    return response.map(
      (Map<String, dynamic> data) =>
          PlayerCareerStats.fromJson(asMap(data['stats'])),
    );
  }

  // -------------------------------------------------------------- internals --

  Future<Result<SocialPage<FriendRequest>>> _requests(
    String direction, {
    required int page,
    required int limit,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/friends/requests/$direction',
      query: <String, String>{'page': '$page', 'limit': '$limit'},
    );

    return response.map(
      (Map<String, dynamic> data) =>
          SocialPage<FriendRequest>.fromJson(data, FriendRequest.fromJson),
    );
  }

  Future<Result<void>> _requestAction(String requestId, String action) async {
    final Result<Map<String, dynamic>> response =
        await _client.post('/api/friends/requests/$requestId/$action');
    return response.map((_) {});
  }
}
