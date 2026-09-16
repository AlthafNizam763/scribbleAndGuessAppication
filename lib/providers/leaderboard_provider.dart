import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/leaderboard_entry.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/repositories/leaderboard_repository.dart';

/// The device-local hall of fame.
class LeaderboardNotifier extends AsyncNotifier<List<LeaderboardEntry>> {
  LeaderboardRepository get _repository =>
      ref.read(leaderboardRepositoryProvider);

  @override
  Future<List<LeaderboardEntry>> build() => _repository.load();

  /// Folds a finished game into the local player's running totals.
  Future<void> record(GameResult result) async {
    final String selfId = ref.read(selfIdProvider);
    if (selfId.isEmpty) {
      return;
    }
    await _repository.record(result, selfId);
    state = AsyncValue<List<LeaderboardEntry>>.data(await _repository.load());
  }

  /// Wipes the board.
  Future<Result<void>> clear() async {
    final Result<void> outcome = await _repository.clear();
    if (outcome.isOk) {
      state = const AsyncValue<List<LeaderboardEntry>>.data(
        <LeaderboardEntry>[],
      );
    }
    return outcome;
  }

  /// Re-reads from disk.
  Future<void> refresh() async {
    state = const AsyncValue<List<LeaderboardEntry>>.loading();
    state = AsyncValue<List<LeaderboardEntry>>.data(await _repository.load());
  }
}

final AsyncNotifierProvider<LeaderboardNotifier, List<LeaderboardEntry>>
    leaderboardProvider =
    AsyncNotifierProvider<LeaderboardNotifier, List<LeaderboardEntry>>(
  LeaderboardNotifier.new,
);
