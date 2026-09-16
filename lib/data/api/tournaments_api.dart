import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/auto_tournament.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/tournament.dart';

/// `GET/POST /api/tournaments/*` — scheduled events and their boards.
///
/// ## What is missing, and why
///
/// There is no method that reports a score. A tournament score is folded in by
/// the game engine when a ranked match ends, from the total the server itself
/// computed; the app never sees a number it could inflate, and there is no
/// endpoint that would accept one. That is the whole of "validate tournament
/// scores on the backend" at this layer — not a check, but an absence.
///
/// Nothing here throws. Failures come back as [Err] like every other transport
/// in this app.
class TournamentsApi {
  /// Creates the API over [client].
  const TournamentsApi(this._client);

  final ApiClient _client;

  // --- automatic knockout tournaments --------------------------------------

  /// The tournament slots, in order.
  ///
  /// A slot with nothing in it comes back as a row with a null tournament
  /// rather than being left out, because the screen shows one card per slot
  /// and "a new one will be created automatically" is a card.
  Future<Result<List<TournamentSlot>>> slots() async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/tournaments');

    return response.map(
      (Map<String, dynamic> data) => <TournamentSlot>[
        for (final dynamic raw in asList(data['slots']))
          TournamentSlot.fromJson(asMap(raw)),
      ],
    );
  }

  /// One tournament, with the local player's own state folded in.
  Future<Result<AutoTournament>> get(String tournamentId) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/tournaments/$tournamentId');

    return response.map(
      (Map<String, dynamic> data) =>
          AutoTournament.fromJson(asMap(data['tournament'])),
    );
  }

  /// Takes a place, and returns the tournament as it now stands.
  ///
  /// Registering twice is a no-op on the server rather than an error, so a
  /// double tap resolves to the same tournament a single one would. The
  /// refusals worth showing the player are "you are already in another
  /// tournament" and "that tournament is full", both of which arrive as a
  /// [Failure] carrying the server's own sentence.
  Future<Result<AutoTournament>> register(String tournamentId) async {
    final Result<Map<String, dynamic>> response =
        await _client.post('/api/tournaments/$tournamentId/register');

    return response.map(
      (Map<String, dynamic> data) =>
          AutoTournament.fromJson(asMap(data['tournament'])),
    );
  }

  /// Gives a place back. Only possible while registration is open.
  Future<Result<AutoTournament>> withdraw(String tournamentId) async {
    final Result<Map<String, dynamic>> response =
        await _client.delete('/api/tournaments/$tournamentId/register');

    return response.map(
      (Map<String, dynamic> data) =>
          AutoTournament.fromJson(asMap(data['tournament'])),
    );
  }

  /// Confirms the local player is here, in the window before the draw.
  ///
  /// This is what the bracket is actually built from — a registration alone is
  /// not enough — so a player who skips it is replaced by an AI or leaves the
  /// tournament one short.
  Future<Result<AutoTournament>> checkIn(String tournamentId) async {
    final Result<Map<String, dynamic>> response =
        await _client.post('/api/tournaments/$tournamentId/check-in');

    return response.map(
      (Map<String, dynamic> data) =>
          AutoTournament.fromJson(asMap(data['tournament'])),
    );
  }

  /// Everybody in a tournament, AI players included and flagged.
  Future<Result<List<TournamentParticipant>>> participants(
    String tournamentId,
  ) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/tournaments/$tournamentId/participants');

    return response.map(
      (Map<String, dynamic> data) => <TournamentParticipant>[
        for (final dynamic raw in asList(data['items']))
          TournamentParticipant.fromJson(asMap(raw)),
      ],
    );
  }

  /// The draw.
  ///
  /// Room codes arrive only on the matches the local player is in; every other
  /// pairing's is null. That is the server's decision, not a filter applied
  /// here.
  Future<Result<TournamentBracket>> bracket(String tournamentId) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/tournaments/$tournamentId/bracket');

    return response.map(TournamentBracket.fromJson);
  }

  /// How everybody placed.
  Future<Result<List<TournamentParticipant>>> leaderboard(
    String tournamentId,
  ) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/tournaments/$tournamentId/leaderboard');

    return response.map(
      (Map<String, dynamic> data) => <TournamentParticipant>[
        for (final dynamic raw in asList(data['items']))
          TournamentParticipant.fromJson(asMap(raw)),
      ],
    );
  }

  /// Asks for the code of the room this player's match is being held in.
  ///
  /// The app then joins that room exactly as it joins any other, which is what
  /// keeps the tournament path free of a second way into a game.
  Future<Result<TournamentMatchEntry>> enterMatch({
    required String tournamentId,
    required String matchId,
  }) async {
    final Result<Map<String, dynamic>> response = await _client
        .post('/api/tournaments/$tournamentId/matches/$matchId/enter');

    return response.map(TournamentMatchEntry.fromJson);
  }

  // --- points events (the older feature) -----------------------------------

  /// The scheduled points events, soonest first.
  ///
  /// A different feature from the knockout cups above and served from its own
  /// path, `GET /api/tournaments/events`. Kept because the points board is
  /// still a live feature; the automatic cups took over the bare
  /// `/api/tournaments` path because that is what a player means when they
  /// open the tournament screen.
  Future<Result<List<Tournament>>> events() async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/tournaments/events');

    return response.map(
      (Map<String, dynamic> data) => <Tournament>[
        for (final dynamic raw in asList(data['items']))
          Tournament.fromJson(asMap(raw)),
      ].where((Tournament row) => !row.isEmpty).toList(growable: false),
    );
  }

  /// One page of an event's own leaderboard.
  Future<Result<TournamentBoard>> board(
    String tournamentId, {
    int page = 1,
    int limit = 25,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/tournaments/$tournamentId/board',
      query: <String, String>{'page': '$page', 'limit': '$limit'},
    );

    return response.map(TournamentBoard.fromJson);
  }
}
