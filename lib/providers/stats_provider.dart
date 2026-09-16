import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/player_stats.dart';
import 'package:scribble_guess/providers/friends_provider.dart';

/// A player's full career record.
///
/// Autodisposing and family-keyed: a career record is read once when somebody
/// opens a stats screen and is stale the moment they finish another match, so
/// holding it after the screen closes would cache a number that is wrong by
/// definition.
///
/// `me` is accepted in place of an id — the server resolves it — so a caller
/// showing the local player's stats does not need their id to hand.
final AutoDisposeFutureProviderFamily<PlayerCareerStats, String>
    playerStatsProvider =
    FutureProvider.autoDispose.family<PlayerCareerStats, String>(
  (Ref ref, String userId) async {
    final Result<PlayerCareerStats> result =
        await ref.read(socialApiProvider).stats(userId);

    return switch (result) {
      Ok<PlayerCareerStats>(:final PlayerCareerStats value) => value,
      // Thrown rather than returned so the screen's error branch renders,
      // which is where the retry lives.
      Err<PlayerCareerStats>(:final Failure failure) => throw failure,
    };
  },
);
