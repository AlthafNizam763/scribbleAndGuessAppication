import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/tournaments_api.dart';
import 'package:scribble_guess/models/auto_tournament.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/tournament.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// The automatic tournaments, their brackets and the two things a player can
/// do with one.
///
/// ## Where the truth is
///
/// The server, without exception. There is no optimistic registration here, no
/// locally computed bracket and no client-side idea of whether a player may
/// join — `viewer.canRegister` and `viewer.canCheckIn` arrive already decided,
/// because the rules behind them are server rules and a second implementation
/// here could only disagree. A disagreement would show up as a button that
/// does nothing, which is the worst of both.
///
/// ## Why everything autodisposes
///
/// A tournament listing goes stale by the clock: a registration window closes
/// on its own, a bracket advances without anybody pressing anything. Throwing
/// the state away when the screen closes means the next visit asks again,
/// which is both simpler and more correct than any invalidation rule keyed on
/// time. While the screen *is* open, the socket events do the refreshing — see
/// `TournamentsNotifier.refresh`.

/// The tournament endpoints.
final Provider<TournamentsApi> tournamentsApiProvider = Provider<TournamentsApi>(
  (Ref ref) => TournamentsApi(ref.watch(apiClientProvider)),
);

/// Every tournament announcement, as a bare "something changed".
///
/// ## Why the payloads are thrown away
///
/// Each of these events carries enough to patch the screen in place, and doing
/// that would mean a second model of the tournament lifecycle living in the
/// app — which is exactly what this feature exists to have only one of. Three
/// slots is a small response, and re-reading it is both simpler and impossible
/// to get subtly wrong.
///
/// ## Why the subscription is re-sent on every connection
///
/// Channel membership on the server is per *connection* and does not survive a
/// reconnect. A client that subscribed once at startup would go quiet after
/// the first dropped connection and never notice — the events would simply
/// stop, which looks identical to a quiet hour. Watching the gateway's status
/// and re-sending is what makes a reconnect self-healing.
final StreamProvider<String> tournamentEventsProvider = StreamProvider<String>(
  (Ref ref) {
    final RealtimeGateway gateway = ref.watch(gatewayProvider);

    // Ask now, in case the socket is already up, and again on every
    // (re)connection.
    gateway.emit(SocketEvents.clientTournamentWatch, const <String, dynamic>{});

    final StreamSubscription<ConnectionStatus> reconnects =
        gateway.status.listen((ConnectionStatus status) {
      if (status == ConnectionStatus.connected) {
        gateway.emit(
          SocketEvents.clientTournamentWatch,
          const <String, dynamic>{},
        );
      }
    });

    ref.onDispose(() {
      unawaited(reconnects.cancel());
      gateway.emit(
        SocketEvents.clientTournamentUnwatch,
        const <String, dynamic>{},
      );
    });

    return gateway.inbound
        .where(
          (({String event, Map<String, dynamic> data}) message) =>
              SocketEvents.tournamentEvents.contains(message.event),
        )
        .map((({String event, Map<String, dynamic> data}) message) {
      AppLogger.d('Tournaments: ${message.event}');
      return message.event;
    });
  },
);

/// Today's tournaments, in the order they happen.
class TournamentsNotifier extends AutoDisposeAsyncNotifier<TournamentDay> {
  @override
  Future<TournamentDay> build() {
    // `listen` rather than `watch`: a push should refresh the listing, not
    // rebuild this provider and re-enter `build` from the top.
    //
    // The subscription lives as long as this notifier, which autodisposes with
    // the screen — so the server is told to stop sending when nobody is
    // looking, rather than fanning tournament traffic at every open app.
    ref.listen<AsyncValue<String>>(
      tournamentEventsProvider,
      (AsyncValue<String>? previous, AsyncValue<String> next) {
        if (next.hasValue) unawaited(refresh());
      },
    );

    return _load();
  }

  Future<TournamentDay> _load() async {
    final Result<TournamentDay> result =
        await ref.read(tournamentsApiProvider).today();

    return switch (result) {
      Ok<TournamentDay>(:final TournamentDay value) => value,
      // Thrown rather than returned so the screen's error branch renders,
      // which is where the retry lives.
      Err<TournamentDay>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the day.
  ///
  /// Used by pull-to-refresh and by the socket listener. A whole-day re-read
  /// rather than a patch keyed on the event: there are at most three rows, the
  /// response is small, and an event-shaped patch would be a second model of
  /// the tournament lifecycle living in the client — which is the thing this
  /// feature most wants to avoid having two of.
  Future<void> refresh() async {
    state = await AsyncValue.guard<TournamentDay>(_load);
  }

  /// Replaces one tournament in place, from a server response.
  ///
  /// Only the row it names. The other two are left exactly as they were, which
  /// is the whole of "one tournament's result does not touch another" on this
  /// side: there is no shared field to write.
  void _replace(AutoTournament updated) {
    final TournamentDay current = state.valueOrNull ?? TournamentDay.empty;

    state = AsyncValue<TournamentDay>.data(
      TournamentDay(
        tournamentDate: current.tournamentDate,
        timeZone: current.timeZone,
        tournaments: <AutoTournament>[
          for (final AutoTournament row in current.tournaments)
            row.id == updated.id ? updated : row,
        ],
      ),
    );
  }

  /// Takes a place in [tournamentId].
  ///
  /// Nothing is written locally first: a registration that failed but looked
  /// like it succeeded would leave a player waiting for a match that is never
  /// coming. The tournament the server sends back replaces the row, so the
  /// counts and the button state come from the same authoritative answer.
  Future<Result<AutoTournament>> register(String tournamentId) async {
    final Result<AutoTournament> result =
        await ref.read(tournamentsApiProvider).register(tournamentId);

    if (result case Ok<AutoTournament>(value: final AutoTournament updated)) {
      // This row only.
      //
      // ## Why this no longer re-reads the whole day
      //
      // Because joining one tournament used to change whether the player could
      // join the other two, and that answer lived in each row's own `viewer`
      // block — so the listing had to be re-read to keep them honest. There is
      // no such rule now: a player may hold a place in all three, and the
      // other two cards are unaffected by this one. Patching the row is both
      // cheaper and more truthful, because it cannot accidentally show a
      // change to a tournament nothing happened to.
      _replace(updated);
      return Ok<AutoTournament>(updated);
    }

    return result;
  }

  /// Gives a place back.
  Future<Result<AutoTournament>> withdraw(String tournamentId) async {
    final Result<AutoTournament> result =
        await ref.read(tournamentsApiProvider).withdraw(tournamentId);

    if (result case Ok<AutoTournament>(value: final AutoTournament updated)) {
      // Same reason as registering: leaving one changes nothing about the
      // others.
      _replace(updated);
    }

    return result;
  }

  /// Confirms the local player is here, before the draw.
  Future<Result<AutoTournament>> checkIn(String tournamentId) async {
    final Result<AutoTournament> result =
        await ref.read(tournamentsApiProvider).checkIn(tournamentId);

    if (result case Ok<AutoTournament>(value: final AutoTournament updated)) {
      // Checking in changes only this tournament, so the row is patched rather
      // than the listing re-read.
      _replace(updated);
    }

    return result;
  }
}

/// Today's tournaments.
final AutoDisposeAsyncNotifierProvider<TournamentsNotifier, TournamentDay>
    tournamentsProvider =
    AsyncNotifierProvider.autoDispose<TournamentsNotifier, TournamentDay>(
  TournamentsNotifier.new,
);

/// One tournament, kept fresh on its own.
///
/// Separate from the listing because the detail screen shows things the
/// listing does not fetch — the roster and the bracket — and a player sitting
/// on it during check-in needs it to move.
final AutoDisposeFutureProviderFamily<AutoTournament, String>
    tournamentDetailProvider =
    FutureProvider.autoDispose.family<AutoTournament, String>(
  (Ref ref, String tournamentId) async {
    final Result<AutoTournament> result =
        await ref.read(tournamentsApiProvider).get(tournamentId);

    return switch (result) {
      Ok<AutoTournament>(:final AutoTournament value) => value,
      Err<AutoTournament>(:final Failure failure) => throw failure,
    };
  },
);

/// One tournament's entrants, AI players included.
final AutoDisposeFutureProviderFamily<List<TournamentParticipant>, String>
    tournamentParticipantsProvider =
    FutureProvider.autoDispose.family<List<TournamentParticipant>, String>(
  (Ref ref, String tournamentId) async {
    final Result<List<TournamentParticipant>> result =
        await ref.read(tournamentsApiProvider).participants(tournamentId);

    return switch (result) {
      Ok<List<TournamentParticipant>>(
        :final List<TournamentParticipant> value
      ) =>
        value,
      Err<List<TournamentParticipant>>(:final Failure failure) => throw failure,
    };
  },
);

/// One tournament's draw.
final AutoDisposeFutureProviderFamily<TournamentBracket, String>
    tournamentBracketProvider =
    FutureProvider.autoDispose.family<TournamentBracket, String>(
  (Ref ref, String tournamentId) async {
    final Result<TournamentBracket> result =
        await ref.read(tournamentsApiProvider).bracket(tournamentId);

    return switch (result) {
      Ok<TournamentBracket>(:final TournamentBracket value) => value,
      Err<TournamentBracket>(:final Failure failure) => throw failure,
    };
  },
);

/// One tournament's placement table.
final AutoDisposeFutureProviderFamily<List<TournamentParticipant>, String>
    tournamentResultsProvider =
    FutureProvider.autoDispose.family<List<TournamentParticipant>, String>(
  (Ref ref, String tournamentId) async {
    final Result<List<TournamentParticipant>> result =
        await ref.read(tournamentsApiProvider).leaderboard(tournamentId);

    return switch (result) {
      Ok<List<TournamentParticipant>>(
        :final List<TournamentParticipant> value
      ) =>
        value,
      Err<List<TournamentParticipant>>(:final Failure failure) => throw failure,
    };
  },
);

// ---------------------------------------------------------------------------
// The older points events
// ---------------------------------------------------------------------------

/// The scheduled points events.
///
/// A different feature from the knockout cups, on its own endpoint. Kept
/// because its board is still live; it simply no longer owns the tournament
/// screen.
class PointsEventsNotifier extends AutoDisposeAsyncNotifier<List<Tournament>> {
  @override
  Future<List<Tournament>> build() => _load();

  Future<List<Tournament>> _load() async {
    final Result<List<Tournament>> result =
        await ref.read(tournamentsApiProvider).events();

    return switch (result) {
      Ok<List<Tournament>>(:final List<Tournament> value) => value,
      Err<List<Tournament>>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the list.
  Future<void> refresh() async {
    state = await AsyncValue.guard<List<Tournament>>(_load);
  }
}

/// The points events list.
final AutoDisposeAsyncNotifierProvider<PointsEventsNotifier, List<Tournament>>
    pointsEventsProvider = AsyncNotifierProvider.autoDispose<
        PointsEventsNotifier, List<Tournament>>(PointsEventsNotifier.new);

/// One points event's board. First page only.
final AutoDisposeFutureProviderFamily<TournamentBoard, String>
    tournamentBoardProvider =
    FutureProvider.autoDispose.family<TournamentBoard, String>(
  (Ref ref, String tournamentId) async {
    final Result<TournamentBoard> result =
        await ref.read(tournamentsApiProvider).board(tournamentId);

    return switch (result) {
      Ok<TournamentBoard>(:final TournamentBoard value) => value,
      Err<TournamentBoard>(:final Failure failure) => throw failure,
    };
  },
);
