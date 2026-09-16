import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/progression.dart';

/// `GET /api/progression/*` and `/api/achievements`.
///
/// The transport for levels, XP and achievements.
///
/// Note what is missing: there is no method that writes. XP is awarded by the
/// server from facts it owns, and achievements unlock as a consequence, so
/// there is nothing here a client could send — which is the whole of "prevent
/// XP manipulation" and "prevent duplicate achievement rewards" at this layer.
///
/// Nothing throws.
class ProgressionApi {
  /// Creates the API over [client].
  const ProgressionApi(this._client);

  final ApiClient _client;

  /// The local player's level and full achievement catalogue, in one read.
  Future<Result<Progression>> me() async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/progression/me');

    return response.map(Progression.fromJson);
  }

  /// The catalogue for [userId], or the local player when it is omitted.
  ///
  /// Locked entries come back too — the screen is a list of things to aim at,
  /// not only a trophy case.
  Future<Result<AchievementsPage>> achievements({String? userId}) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/achievements',
      query: userId == null || userId.isEmpty
          ? null
          : <String, String>{'userId': userId},
    );

    return response.map(AchievementsPage.fromJson);
  }

  /// One page of the local player's XP history, newest first.
  ///
  /// The local player's only: it is an itemised record of when somebody played
  /// and for how long, which the server does not hand to anybody else.
  Future<Result<List<XpEvent>>> xpHistory({int page = 1, int limit = 25}) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/progression/xp',
      query: <String, String>{'page': '$page', 'limit': '$limit'},
    );

    return response.map(
      (Map<String, dynamic> data) => <XpEvent>[
        for (final dynamic raw in asList(data['items'])) XpEvent.fromJson(asMap(raw)),
      ].where((XpEvent row) => !row.isEmpty).toList(growable: false),
    );
  }
}
