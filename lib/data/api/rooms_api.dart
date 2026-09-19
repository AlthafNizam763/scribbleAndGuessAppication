import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/discovered_room.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/room_invite.dart';
import 'package:scribble_guess/models/social.dart';

/// `/api/rooms/*`: invitations, the public room browser and membership.
///
/// ## Why these are REST and the game is not
///
/// The room a player is *in* is a live thing, so it travels over the socket:
/// the state is pushed, and joining has to seat a connection, not just an
/// account. These endpoints are the opposite shape. An invitations inbox has
/// to be readable before the socket is up — it is how a player decides which
/// room to open a connection *to* — and the public browser is a list somebody
/// scrolls, not a stream.
///
/// So the division is not arbitrary: REST answers "what rooms are there", the
/// socket answers "what is happening in mine". Accepting an invitation is the
/// hinge, and it exists on both — see [acceptInvitation].
///
/// ## It owns no rules
///
/// Every refusal below is decided by the server and arrives as a [Failure]
/// with a message written for the player: the room is full, the game already
/// started, you are already in another room. Duplicating those checks here
/// would give two places for them to disagree, and this copy would be the one
/// that was wrong.
///
/// Nothing throws.
class RoomsApi {
  /// Creates the API over [client].
  const RoomsApi(this._client);

  final ApiClient _client;

  // ----------------------------------------------------------- invitations --

  /// The local player's unanswered invitations.
  Future<Result<List<RoomInvitation>>> invitations({
    int page = 1,
    int limit = 25,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/rooms/invitations',
      query: <String, String>{'page': '$page', 'limit': '$limit'},
    );

    return response.map(
      (Map<String, dynamic> data) => asList(data['items'])
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> row) => RoomInvitation.fromJson(asMap(row)))
          .toList(growable: false),
    );
  }

  /// Asks [friendId] to join [roomId].
  ///
  /// The inviter is the session token and the room is the path, so there is no
  /// field in this call that could aim an invitation at a room the local
  /// player is not in.
  Future<Result<RoomInvitation>> invite({
    required String roomId,
    required String friendId,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.post(
      '/api/rooms/$roomId/invite',
      body: <String, dynamic>{'friendId': friendId},
    );

    return response.map(
      (Map<String, dynamic> data) =>
          RoomInvitation.fromJson(asMap(data['invitation'])),
    );
  }

  /// The local player's friends, annotated for [roomId].
  ///
  /// Every flag on a row — seated, already invited, invitable — is the
  /// server's answer, which is what lets the sheet grey out a button instead
  /// of letting somebody tap into a refusal.
  Future<Result<List<InviteCandidate>>> inviteCandidates(
    String roomId, {
    int limit = 100,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/rooms/$roomId/invite',
      query: <String, String>{'limit': '$limit'},
    );

    return response.map(
      (Map<String, dynamic> data) => asList(data['items'])
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> row) => InviteCandidate.fromJson(asMap(row)))
          .toList(growable: false),
    );
  }

  /// Accepts an invitation and takes the seat, returning the room code.
  ///
  /// ## Why the code and not the room
  ///
  /// This seats the *account*. The connection still has to enter the room, and
  /// it does that with the code over the socket — which is the same path a
  /// player typing a code takes, so there is one way into a lobby rather than
  /// two. The room object the server also returns is deliberately ignored:
  /// what renders the lobby is the `s:room:state` push that follows the socket
  /// join, never a REST response that is already a moment old.
  Future<Result<String>> acceptInvitation(String invitationId) async {
    final Result<Map<String, dynamic>> response =
        await _client.post('/api/rooms/invitations/$invitationId/accept');

    return response.map((Map<String, dynamic> data) {
      final String code = asString(data['roomCode']);
      if (code.isNotEmpty) return code;
      return asString(asMap(data['room'])['code']);
    });
  }

  /// Declines an invitation. Invitee only, enforced by the server.
  Future<Result<void>> rejectInvitation(String invitationId) async {
    final Result<Map<String, dynamic>> response =
        await _client.post('/api/rooms/invitations/$invitationId/reject');
    return response.map((_) {});
  }

  // ---------------------------------------------------------- public rooms --

  /// The public rooms the local player could join right now.
  ///
  /// The server excludes private rooms, full rooms, started rooms, rooms the
  /// player is banned from and rooms shared with anybody they have blocked.
  /// There is no parameter that would include a private room, which is what
  /// makes "do not join private rooms from the browser" structural rather than
  /// a filter somebody has to remember.
  Future<Result<PublicRoomPage>> publicRooms({
    int page = 1,
    int limit = 25,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/rooms/public',
      query: <String, String>{'page': '$page', 'limit': '$limit'},
    );

    return response.map(PublicRoomPage.fromJson);
  }

  /// Quick Match: joinable public rooms across **every** game.
  ///
  /// Distinct from [publicRooms], which is the Scribble & Guess browser and
  /// stays that way. This reads both of the platform's room engines and
  /// returns one merged list, each row tagged with the route needed to join it
  /// — so the client never has to know which engine a given game runs on.
  ///
  /// [games] restricts to particular games; omitted means all of them. Unknown
  /// ids are dropped by the server rather than refused.
  Future<Result<RoomDiscoveryPage>> discoverRooms({
    int limit = 30,
    List<GameId> games = const <GameId>[],
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/rooms/discover',
      query: <String, String>{
        'limit': '$limit',
        if (games.isNotEmpty)
          'games': games.map((GameId game) => game.wire).join(','),
      },
    );

    return response.map(RoomDiscoveryPage.fromJson);
  }

  // --------------------------------------------------- joining and members --

  /// Takes a seat in [roomId], which may be a room id or a room code.
  ///
  /// Returns the room code, for the same reason [acceptInvitation] does: the
  /// socket join is what actually puts this connection in the lobby.
  Future<Result<String>> join(String roomId) async {
    final Result<Map<String, dynamic>> response =
        await _client.post('/api/rooms/$roomId/join');

    return response.map((Map<String, dynamic> data) {
      final String code = asString(data['roomCode']);
      if (code.isNotEmpty) return code;
      return asString(asMap(data['room'])['code']);
    });
  }

  /// Gives up a seat.
  Future<Result<void>> leave(String roomId) async {
    final Result<Map<String, dynamic>> response =
        await _client.post('/api/rooms/$roomId/leave');
    return response.map((_) {});
  }

  /// Who is seated in [roomId]. Members only.
  Future<Result<RoomMembers>> members(String roomId) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/rooms/$roomId/members');

    return response.map(RoomMembers.fromJson);
  }
}

/// One page of the public room browser.
///
/// Carries the local player's current room alongside the rows, so the screen
/// can say "leave that room first" before somebody taps Join and is refused.
/// The refusal is still the server's; this only saves a round trip to hear it.
class PublicRoomPage {
  /// Creates a page.
  const PublicRoomPage({
    this.items = const <PublicRoom>[],
    this.currentRoomId = '',
    this.currentRoomCode = '',
  });

  /// Builds a page from a decoded JSON map.
  factory PublicRoomPage.fromJson(Map<String, dynamic> json) => PublicRoomPage(
        items: asList(json['items'])
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> row) => PublicRoom.fromJson(asMap(row)))
            .toList(growable: false),
        currentRoomId: asString(json['currentRoomId']),
        currentRoomCode: asString(json['currentRoomCode']),
      );

  /// The rooms on this page.
  final List<PublicRoom> items;

  /// The room the local player already holds a seat in, if any.
  final String currentRoomId;

  /// That room's code, for the "leave it first" prompt.
  final String currentRoomCode;

  /// Whether the player is seated somewhere and must leave before joining.
  bool get isSeatedElsewhere => currentRoomId.isNotEmpty;
}

/// The public card of whoever sent an invitation, for a null-safe read.
///
/// Exists so the invitation card never has to decide what to draw for a
/// deleted account: an empty [UserCard] already renders as a placeholder.
UserCard inviterOrPlaceholder(RoomInvitation invitation) =>
    invitation.inviter.isEmpty ? const UserCard(name: '...') : invitation.inviter;
