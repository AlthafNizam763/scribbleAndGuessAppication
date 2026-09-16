import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/leaderboard_entry.dart';

/// Persistence seam for the local hall of fame.
///
/// Aggregates finished matches into [LeaderboardEntry] rows kept on this
/// device: totals, games played, wins and best round score. It is a personal
/// history, not a ranking anyone else can see, and it is never a source of
/// truth for a live match — in-match scores come from the server through
/// `GameRepository`.
///
/// Because the numbers only ever get *derived* from a server-produced
/// [GameResult], an implementation must not accept scores from any other
/// input.
abstract interface class LeaderboardRepository {
  /// Reads every stored entry, best first.
  ///
  /// Sorted by `LeaderboardEntry.totalScore` descending. Never returns a
  /// [Result] and never throws: unreadable or corrupt storage yields an empty
  /// list so the screen can show its empty state.
  Future<List<LeaderboardEntry>> load();

  /// Folds the finished match [result] into the stored history.
  ///
  /// [selfPlayerId] identifies this device's player inside
  /// `GameResult.standings`; a win is recorded when that player's `rank` is 1.
  /// The deltas come exclusively from the server-authoritative standings, so
  /// the same [GameResult] must be recorded at most once per match.
  ///
  /// Fails with [AppErrorCode.validation] when [selfPlayerId] is absent from
  /// the standings, and [AppErrorCode.storage] when the write fails.
  Future<Result<void>> record(GameResult result, String selfPlayerId);

  /// Deletes the whole local history.
  ///
  /// Succeeds when there was nothing to delete. Fails with
  /// [AppErrorCode.storage] only if the removal itself fails.
  Future<Result<void>> clear();
}
