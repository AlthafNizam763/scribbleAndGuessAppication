import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/drawing_replay.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// `GET /api/games/:gameId/replays`.
///
/// The transport for drawing replays.
///
/// ## Two calls, not one
///
/// The list carries no strokes. A twelve-turn match's drawings together are
/// megabytes, and the list is a menu — a player picks a turn, and only then is
/// that turn's drawing fetched. Folding the two together would make opening
/// the replay screen download every drawing of the match.
///
/// A turn that has not ended answers `NOT_FOUND`, the same as a turn that
/// never existed: a replay carries the word, so a live one is never served.
///
/// Nothing throws.
class ReplayApi {
  /// Creates the API over [client].
  const ReplayApi(this._client);

  final ApiClient _client;

  /// Every finished turn of [gameId], without strokes.
  Future<Result<List<ReplaySummary>>> list(String gameId) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/games/$gameId/replays');

    return response.map(
      (Map<String, dynamic> data) => <ReplaySummary>[
        for (final dynamic raw in asList(data['items']))
          ReplaySummary.fromJson(asMap(raw)),
      ]
          .where((ReplaySummary row) => !row.isEmpty)
          .toList(growable: false),
    );
  }

  /// One finished turn of [gameId], with its strokes.
  Future<Result<DrawingReplay>> get(String gameId, int turnNumber) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/games/$gameId/replays/$turnNumber');

    return response.map(
      (Map<String, dynamic> data) => DrawingReplay.fromJson(asMap(data['replay'])),
    );
  }
}
