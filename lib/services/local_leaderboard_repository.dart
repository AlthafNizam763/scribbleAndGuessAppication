import 'package:scribble_guess/core/constants/storage_keys.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/leaderboard_entry.dart';
import 'package:scribble_guess/models/player_score.dart';
import 'package:scribble_guess/repositories/leaderboard_repository.dart';
import 'package:scribble_guess/services/preferences_store.dart';

/// A device-local hall of fame, accumulated across finished games.
///
/// Only the local player is tracked. Recording an opponent's score would be
/// misleading, since two different people can share a display name and the
/// same person reappears with a fresh id from another device.
class LocalLeaderboardRepository implements LeaderboardRepository {
  const LocalLeaderboardRepository(this._store);

  /// How many entries survive a write. The board is a local curiosity, not an
  /// archive, and an unbounded list would grow forever.
  static const int maxEntries = 50;

  final PreferencesStore _store;

  @override
  Future<List<LeaderboardEntry>> load() async {
    final List<LeaderboardEntry> entries = <LeaderboardEntry>[
      for (final Map<String, dynamic> json
          in _store.readObjectList(StorageKeys.leaderboard))
        LeaderboardEntry.fromJson(json),
    ];
    entries.sort(_byScoreThenRecency);
    return entries;
  }

  @override
  Future<Result<void>> record(GameResult result, String selfPlayerId) async {
    final PlayerScore? mine = _scoreFor(result, selfPlayerId);
    if (mine == null) {
      // The local player did not appear in the standings; nothing to record.
      return const Ok<void>(null);
    }

    final List<LeaderboardEntry> entries = await load();
    final int index =
        entries.indexWhere((LeaderboardEntry e) => e.playerId == selfPlayerId);
    final LeaderboardEntry previous =
        index < 0 ? const LeaderboardEntry() : entries[index];
    final bool won = mine.rank == 1;

    final LeaderboardEntry updated = LeaderboardEntry(
      playerId: selfPlayerId,
      name: mine.name,
      avatarId: mine.avatarId,
      avatarColorIndex: mine.avatarColorIndex,
      totalScore: previous.totalScore + mine.score,
      gamesPlayed: previous.gamesPlayed + 1,
      wins: previous.wins + (won ? 1 : 0),
      bestRoundScore: mine.score > previous.bestRoundScore
          ? mine.score
          : previous.bestRoundScore,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    if (index < 0) {
      entries.add(updated);
    } else {
      entries[index] = updated;
    }
    entries.sort(_byScoreThenRecency);

    final List<LeaderboardEntry> capped = entries.length > maxEntries
        ? entries.sublist(0, maxEntries)
        : entries;

    return _store.writeJson(
      StorageKeys.leaderboard,
      <Map<String, dynamic>>[
        for (final LeaderboardEntry entry in capped) entry.toJson(),
      ],
    );
  }

  @override
  Future<Result<void>> clear() => _store.remove(StorageKeys.leaderboard);

  static PlayerScore? _scoreFor(GameResult result, String playerId) {
    if (playerId.isEmpty) {
      return null;
    }
    for (final PlayerScore score in result.standings) {
      if (score.playerId == playerId) {
        return score;
      }
    }
    return null;
  }

  static int _byScoreThenRecency(LeaderboardEntry a, LeaderboardEntry b) {
    final int byScore = b.totalScore.compareTo(a.totalScore);
    return byScore != 0 ? byScore : b.updatedAtMs.compareTo(a.updatedAtMs);
  }
}
