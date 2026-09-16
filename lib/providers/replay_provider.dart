import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/replay_api.dart';
import 'package:scribble_guess/models/drawing_replay.dart';
import 'package:scribble_guess/providers/auth_provider.dart';

/// Drawing replays.
///
/// ## Everything here autodisposes
///
/// A replay is the largest payload this app fetches, and it is looked at once.
/// Holding one after the screen closes would keep a whole turn's strokes alive
/// for a player who has moved on — so both providers are family-keyed and
/// autodisposing, and reopening a replay re-reads it.

/// The replay endpoints.
final Provider<ReplayApi> replayApiProvider = Provider<ReplayApi>(
  (Ref ref) => ReplayApi(ref.watch(apiClientProvider)),
);

/// Every finished turn of one match, without strokes.
///
/// Keyed by game id. This is the menu the replay screen opens on.
final AutoDisposeFutureProviderFamily<List<ReplaySummary>, String>
    replayListProvider =
    FutureProvider.autoDispose.family<List<ReplaySummary>, String>(
  (Ref ref, String gameId) async {
    final Result<List<ReplaySummary>> result =
        await ref.read(replayApiProvider).list(gameId);

    return switch (result) {
      Ok<List<ReplaySummary>>(:final List<ReplaySummary> value) => value,
      // Thrown rather than returned so the screen's error branch renders,
      // which is where the retry lives.
      Err<List<ReplaySummary>>(:final Failure failure) => throw failure,
    };
  },
);

/// Which turn of a match to fetch.
///
/// A record rather than two separate families, because a replay is identified
/// by the pair and a provider keyed on only one of them would collide across
/// matches.
typedef ReplayKey = ({String gameId, int turnNumber});

/// One turn's drawing, with its strokes.
final AutoDisposeFutureProviderFamily<DrawingReplay, ReplayKey> replayProvider =
    FutureProvider.autoDispose.family<DrawingReplay, ReplayKey>(
  (Ref ref, ReplayKey key) async {
    final Result<DrawingReplay> result =
        await ref.read(replayApiProvider).get(key.gameId, key.turnNumber);

    return switch (result) {
      Ok<DrawingReplay>(:final DrawingReplay value) => value,
      Err<DrawingReplay>(:final Failure failure) => throw failure,
    };
  },
);
