import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/rooms_api.dart';
import 'package:scribble_guess/models/discovered_room.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_invite.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/providers/room_controller.dart';
import 'package:scribble_guess/repositories/repositories.dart';

/// Room invitations, the public room browser, and entering a room from either.
///
/// ## Where the truth is
///
/// The server, exactly as in [friendsProvider]. Every list here is a cache of
/// a REST read and every action is a call whose response decides what
/// happened. Nothing is applied locally and hoped for: a room that looked
/// joinable when the list was drawn can be full by the time somebody taps it,
/// and the only honest way to find out is to ask.
///
/// ## Realtime is a hint, with one deliberate exception
///
/// The `s:room:invitation*` pushes mean "your inbox is stale", and
/// [roomInvitationsProvider] responds by re-reading it — the same arrangement
/// the friend pushes use, for the same reason: a client that built list rows
/// out of pushes would have two code paths producing the same rows, and the
/// guessed one would be the one on screen.
///
/// The exception is [incomingInvitationProvider], which does parse the pushed
/// payload. A dialog has to be drawable the instant the invitation lands, and
/// one that waited for a REST round trip would appear a beat late or, on a
/// poor connection, not at all. It is a *notification*, not a list: the inbox
/// re-reads over REST regardless, and that read wins wherever the two differ.
///
/// ## Entering a room is always the same three steps
///
/// Accepting an invitation and joining a public room both end the same way:
/// the REST call seats the account, and then the socket enters the room by
/// code through [RoomController]. That second step is not a formality — REST
/// can seat an account but not a *connection*, so a player who skipped it
/// would sit in a lobby that never updates. Routing both through the room
/// controller is what keeps one definition of "in a room" in the app.

/// The room invitation, browser and membership endpoints.
final Provider<RoomsApi> roomsApiProvider = Provider<RoomsApi>(
  (Ref ref) => RoomsApi(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Realtime
// ---------------------------------------------------------------------------

/// Invitation pushes from the server, as a plain stream of event names.
///
/// Carries only the name, like [friendEventsProvider]: every one of these
/// means the same thing to a list, which is that it is stale. The one listener
/// that needs the payload reads it from [incomingInvitationProvider] instead.
final StreamProvider<String> roomInvitationEventsProvider =
    StreamProvider<String>(
  (Ref ref) => ref
      .watch(gatewayProvider)
      .inbound
      .where(
        (({String event, Map<String, dynamic> data}) message) =>
            SocketEvents.roomInvitationEvents.contains(message.event),
      )
      .map((({String event, Map<String, dynamic> data}) message) {
    AppLogger.d('Room invitations: ${message.event}');
    return message.event;
  }),
);

/// Invitations as they arrive, parsed, for the pop-up dialog.
///
/// Only [SocketEvents.serverRoomInvitationReceived] — the accepted and
/// rejected pushes are addressed to the *inviter* and say nothing a dialog
/// should interrupt somebody for.
///
/// Malformed payloads are dropped rather than surfaced: an invitation card
/// with no room code is a card whose only button cannot work.
final StreamProvider<RoomInvitation> incomingInvitationProvider =
    StreamProvider<RoomInvitation>(
  (Ref ref) => ref
      .watch(gatewayProvider)
      .inbound
      .where(
        (({String event, Map<String, dynamic> data}) message) =>
            message.event == SocketEvents.serverRoomInvitationReceived,
      )
      .map(
        (({String event, Map<String, dynamic> data}) message) =>
            RoomInvitation.fromJson(asMap(message.data['invitation'])),
      )
      .where((RoomInvitation invitation) => invitation.id.isNotEmpty),
);

// ---------------------------------------------------------------------------
// The inbox
// ---------------------------------------------------------------------------

/// The local player's unanswered room invitations.
class RoomInvitationsNotifier extends AsyncNotifier<List<RoomInvitation>> {
  RoomsApi get _api => ref.read(roomsApiProvider);

  @override
  Future<List<RoomInvitation>> build() async {
    // `listen` rather than `watch`: a push should refresh the list, not
    // rebuild this provider and re-enter `build` from the top.
    ref.listen<AsyncValue<String>>(
      roomInvitationEventsProvider,
      (AsyncValue<String>? previous, AsyncValue<String> next) {
        if (next.hasValue) unawaited(refresh());
      },
    );

    return _load();
  }

  Future<List<RoomInvitation>> _load() async {
    final Result<List<RoomInvitation>> result = await _api.invitations();

    return switch (result) {
      Ok<List<RoomInvitation>>(:final List<RoomInvitation> value) =>
        value.where((RoomInvitation row) => row.isOpen).toList(growable: false),
      // Thrown rather than returned so the screen's error branch renders,
      // which is where the retry button lives. The server's own message is
      // carried through, so the player reads the sentence it wrote.
      Err<List<RoomInvitation>>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the inbox. Used by pull-to-refresh and after every answer.
  Future<void> refresh() async {
    try {
      state = AsyncValue<List<RoomInvitation>>.data(await _load());
    } on Failure catch (failure, stack) {
      state = AsyncValue<List<RoomInvitation>>.error(failure, stack);
    }
  }

  /// Drops one row without a round trip, after the server confirmed an answer.
  ///
  /// The refresh that follows would remove it anyway; this only stops the card
  /// sitting there looking tappable for the length of that round trip.
  void forget(String invitationId) {
    final List<RoomInvitation>? current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue<List<RoomInvitation>>.data(
      current
          .where((RoomInvitation row) => row.id != invitationId)
          .toList(growable: false),
    );
  }
}

/// The invitations inbox, as the screens read it.
final AsyncNotifierProvider<RoomInvitationsNotifier, List<RoomInvitation>>
    roomInvitationsProvider =
    AsyncNotifierProvider<RoomInvitationsNotifier, List<RoomInvitation>>(
  RoomInvitationsNotifier.new,
);

/// How many invitations are waiting, for the badge on the home screen.
///
/// Zero while the list is loading or failed, which is the right default: a
/// badge that guesses is worse than no badge.
final Provider<int> pendingInvitationCountProvider = Provider<int>(
  (Ref ref) => ref.watch(roomInvitationsProvider).valueOrNull?.length ?? 0,
);

// ---------------------------------------------------------------------------
// The public browser
// ---------------------------------------------------------------------------

/// The public rooms the local player could join.
///
/// Autodisposes: this is a snapshot of who is waiting *right now*, and holding
/// it while the player is elsewhere would mean reopening the screen to a list
/// of rooms that have since filled or started.
class PublicRoomsNotifier extends AutoDisposeAsyncNotifier<PublicRoomPage> {
  @override
  Future<PublicRoomPage> build() async {
    final Result<PublicRoomPage> result =
        await ref.read(roomsApiProvider).publicRooms();

    return switch (result) {
      Ok<PublicRoomPage>(:final PublicRoomPage value) => value,
      Err<PublicRoomPage>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the list, keeping the current rows on screen while it runs.
  Future<void> refresh() async {
    state = await AsyncValue.guard<PublicRoomPage>(build);
  }
}

/// The public room browser.
final AutoDisposeAsyncNotifierProvider<PublicRoomsNotifier, PublicRoomPage>
    publicRoomsProvider =
    AsyncNotifierProvider.autoDispose<PublicRoomsNotifier, PublicRoomPage>(
  PublicRoomsNotifier.new,
);

// ---------------------------------------------------------------------------
// Quick Match
// ---------------------------------------------------------------------------

/// Every joinable public room, across every game.
///
/// Autodisposes for the same reason [PublicRoomsNotifier] does, and more so:
/// this list spans five games, so it goes stale faster than any one game's
/// browser would.
class RoomDiscoveryNotifier extends AutoDisposeAsyncNotifier<RoomDiscoveryPage> {
  @override
  Future<RoomDiscoveryPage> build() async {
    final Result<RoomDiscoveryPage> result =
        await ref.read(roomsApiProvider).discoverRooms();

    return switch (result) {
      Ok<RoomDiscoveryPage>(:final RoomDiscoveryPage value) => value,
      Err<RoomDiscoveryPage>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the list, keeping the current rows on screen while it runs.
  Future<void> refresh() async {
    state = await AsyncValue.guard<RoomDiscoveryPage>(build);
  }
}

/// Quick Match, as the home screen reads it.
final AutoDisposeAsyncNotifierProvider<RoomDiscoveryNotifier, RoomDiscoveryPage>
    roomDiscoveryProvider =
    AsyncNotifierProvider.autoDispose<RoomDiscoveryNotifier, RoomDiscoveryPage>(
  RoomDiscoveryNotifier.new,
);

/// Where a successful Quick Match join left the player.
///
/// The two room engines land somewhere different — the Scribble engine seats a
/// socket and the lobby screen renders from its push, while the platform
/// engine returns a room document and its own lobby renders from that — so the
/// caller has to be told which, rather than guessing from the game id.
@immutable
class JoinedRoomDestination {
  /// Creates a destination.
  const JoinedRoomDestination({required this.route, this.game});

  /// Which engine took the seat.
  final RoomJoinRoute route;

  /// The game, when this build knows it. Only meaningful for
  /// [RoomJoinRoute.gamePlatform], whose lobby is per-game.
  final GameDefinition? game;
}

// ---------------------------------------------------------------------------
// The invite sheet
// ---------------------------------------------------------------------------

/// The local player's friends, annotated for one room.
///
/// Keyed by room id, autodisposing, because every flag on a row is a fact
/// about that room at that moment: who is seated, who has already been asked,
/// whether there is space left. Caching it past the sheet closing would mean
/// reopening to stale buttons.
class InviteCandidatesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<InviteCandidate>, String> {
  @override
  Future<List<InviteCandidate>> build(String arg) async {
    final Result<List<InviteCandidate>> result =
        await ref.read(roomsApiProvider).inviteCandidates(arg);

    return switch (result) {
      Ok<List<InviteCandidate>>(:final List<InviteCandidate> value) => value,
      Err<List<InviteCandidate>>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the sheet.
  Future<void> refresh() async {
    state = await AsyncValue.guard<List<InviteCandidate>>(() => build(arg));
  }

  /// Marks one row invited, after the server said the invitation was created.
  ///
  /// The only optimistic update in this file, and it is not a guess: the
  /// server has already answered. It exists so the row settles immediately
  /// instead of after a reload that would also rebuild every other row and
  /// lose the player's scroll position.
  void markInvited(String userId) {
    final List<InviteCandidate>? current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue<List<InviteCandidate>>.data(
      current
          .map(
            (InviteCandidate row) =>
                row.card.id == userId ? row.asInvited() : row,
          )
          .toList(growable: false),
    );
  }
}

/// The invite sheet's rows, keyed by room id.
final AutoDisposeAsyncNotifierProviderFamily<InviteCandidatesNotifier,
        List<InviteCandidate>, String> inviteCandidatesProvider =
    AsyncNotifierProvider.autoDispose
        .family<InviteCandidatesNotifier, List<InviteCandidate>, String>(
  InviteCandidatesNotifier.new,
);

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// Sending invitations, answering them, and entering rooms.
///
/// ## Why the actions are not on the notifiers
///
/// They are called from places that hold none of these lists: the lobby's
/// Invite button, a pop-up dialog that may be over any screen, a public room
/// card. Those should not have to mount an inbox to answer one invitation. A
/// caller reads this provider, calls one method and gets a [Result]; which
/// lists happen to be alive is not their problem.
class RoomInviteActions {
  /// Creates the action set.
  const RoomInviteActions(this._ref);

  static const Failure _noProfile = Failure(
    AppErrorCode.invalidAction,
    'Set up your profile before joining a game.',
  );

  final Ref _ref;

  RoomsApi get _api => _ref.read(roomsApiProvider);

  /// Invites [friendId] to [roomId].
  ///
  /// Sent over the socket when one is open — the inviter is almost always
  /// sitting in the lobby, and the ack comes back without a second HTTP
  /// round trip — and over REST otherwise. Both call the same server service,
  /// so the rules cannot differ; only the transport does.
  Future<Result<RoomInvitation>> invite({
    required String roomId,
    required String friendId,
  }) async {
    final RealtimeGateway gateway = _ref.read(gatewayProvider);

    if (gateway.currentStatus == ConnectionStatus.connected) {
      final Result<Map<String, dynamic>> ack = await gateway.request(
        SocketEvents.clientRoomInvite,
        <String, dynamic>{'friendId': friendId},
      );

      final Result<RoomInvitation> outcome = ack.map(
        (Map<String, dynamic> data) =>
            RoomInvitation.fromJson(asMap(data['invitation'])),
      );

      if (outcome.isOk) {
        _refreshSheet(roomId, friendId);
        return outcome;
      }

      // A socket refusal is a real refusal — the server decided — so it is
      // returned rather than retried over REST, which would only ask the same
      // service the same question and get the same answer.
      return outcome;
    }

    final Result<RoomInvitation> outcome =
        await _api.invite(roomId: roomId, friendId: friendId);

    if (outcome.isOk) _refreshSheet(roomId, friendId);
    return outcome;
  }

  /// Accepts an invitation and enters the room's lobby.
  ///
  /// Returns the room the player ended up in, so the caller can navigate on
  /// success and show the server's own message on failure — `Room is full`,
  /// `Game already started`, `Invitation expired`.
  ///
  /// ## Why the connection comes first, and why there is only one server call
  ///
  /// This used to be two calls: `POST /rooms/invitations/:id/accept` to seat
  /// the account, then a socket join to seat the connection. That ordering is
  /// what made accepting fail on the first attempt, in two separate ways.
  ///
  /// The first is that the REST call spends the invitation before the socket
  /// has been proved to work. An invitation row is single-use and guarded, so
  /// once it is accepted there is nothing left to retry with: a socket that
  /// then failed to open — a cold realtime host, a handover, a dead spot —
  /// left the player seated in a room they had never been shown, with the card
  /// already gone from their inbox. The only way back in was a room code they
  /// had no way to read.
  ///
  /// The second is that the two transports disagreed about what "you are
  /// already in a room" meant. A seat outlives the connection that took it by
  /// the reconnect grace, so an app that was backgrounded or killed rather
  /// than left through the Leave button holds one for another forty-five
  /// seconds; the socket path vacates such a seat, and the REST path refused
  /// the accept outright with a message naming a room the player had already
  /// left. Waiting it out was the "try again" in the report. That half is
  /// fixed on the server as well — both paths now agree — but this path no
  /// longer depends on it.
  ///
  /// So: establish the session and the socket first, and then make exactly one
  /// call that accepts, vacates any abandoned seat, takes the seat and enters
  /// the room. Either the player is in the room, or the invitation is still
  /// theirs to tap again. There is no state in between, and no delay anywhere.
  Future<Result<Room>> accept(RoomInvitation invitation) async {
    final PlayerProfile? profile = _ref.read(profileProvider);
    if (profile == null) return const Err<Room>(_noProfile);

    // Before anything is spent. A connection that cannot be established is
    // reported as the connection failure it is, and the invitation stays in
    // the inbox for the player to try again — which is what makes the retry
    // the card offers actually mean something.
    final Result<void> ready =
        await _ref.read(roomControllerProvider).prepare(profile);

    if (ready case Err<void>(:final Failure failure)) {
      return Err<Room>(failure);
    }

    final Result<Room> entered = await _ref
        .read(roomRepositoryProvider)
        .acceptInvitation(invitation.id, profile);

    switch (entered) {
      case Ok<Room>():
        _ref.read(roomInvitationsProvider.notifier).forget(invitation.id);
      case Err<Room>():
        // The server refused. Whether the invitation survived that refusal is
        // its decision, not a guess this can make — an expired row is gone
        // while a full room leaves the invitation standing — so the inbox is
        // re-read rather than edited.
        unawaited(_ref.read(roomInvitationsProvider.notifier).refresh());
    }

    return entered;
  }

  /// Declines an invitation. The player stays where they are.
  Future<Result<void>> reject(RoomInvitation invitation) async {
    final Result<void> outcome = await _api.rejectInvitation(invitation.id);

    _ref.read(roomInvitationsProvider.notifier).forget(invitation.id);
    unawaited(_ref.read(roomInvitationsProvider.notifier).refresh());

    return outcome;
  }

  /// Joins a public room and enters its lobby.
  ///
  /// The socket first, for the same reason as [accept]: the room call that
  /// matters is the socket one — REST can seat an account but not a
  /// connection — so opening the connection before anything is written means a
  /// failure to connect leaves the player exactly where they were rather than
  /// seated in a room they were never shown.
  ///
  /// The join itself then goes over the socket, which is the single call that
  /// re-validates the room, vacates any seat left behind by a killed app and
  /// enters the lobby. The browser row it came from is only a snapshot: a room
  /// that had space when the list was drawn may not now, and the server's
  /// refusal carries the message the player should read.
  Future<Result<Room>> joinPublic(PublicRoom room) async {
    final PlayerProfile? profile = _ref.read(profileProvider);
    if (profile == null) return const Err<Room>(_noProfile);

    return _ref.read(roomControllerProvider).joinRoom(room.code);
  }

  /// Takes a seat in a room found through Quick Match, whatever game it is.
  ///
  /// ## Why this is not just [joinPublic]
  ///
  /// [joinPublic] speaks to one engine. Quick Match spans both, so the route
  /// has to be chosen per row — and it is chosen from what the *server* said in
  /// [DiscoveredRoom.joinVia], never from the game id. The moment a client
  /// starts inferring "Ludo means the platform engine" it is holding a copy of
  /// a server decision, and it will be the thing that breaks when a game moves.
  ///
  /// Neither branch re-checks joinability. Capacity, bans, whether the match
  /// already started and whether the player is seated somewhere else are all
  /// the server's to decide, and both engines re-check them at the moment of
  /// the join — which is the only moment the answer is true. A row that looked
  /// open when the list was drawn can be full by the time somebody taps it, and
  /// that refusal is the correct outcome, not a bug to route around.
  Future<Result<JoinedRoomDestination>> joinDiscovered(DiscoveredRoom room) async {
    final PlayerProfile? profile = _ref.read(profileProvider);
    if (profile == null) return const Err<JoinedRoomDestination>(_noProfile);

    switch (room.joinVia) {
      case RoomJoinRoute.room:
        // The Scribble engine: REST seats the account, and the room controller
        // enters the room over the socket — which is the step that actually
        // puts *this connection* in the lobby. Skipping it would leave the
        // player looking at a lobby that never updates.
        final Result<Room> joined =
            await _ref.read(roomControllerProvider).joinRoom(room.code);

        return joined.map(
          (_) => const JoinedRoomDestination(route: RoomJoinRoute.room),
        );

      case RoomJoinRoute.gamePlatform:
        final Result<PlatformRoom> joined = await _ref
            .read(gamesApiProvider)
            .joinRoom(gameWireId: room.gameId?.wire ?? '', roomId: room.roomId);

        return joined.map(
          (_) => JoinedRoomDestination(
            route: RoomJoinRoute.gamePlatform,
            game: room.game,
          ),
        );
    }
  }

  /// Re-reads the invite sheet for [roomId], marking [friendId] invited first.
  void _refreshSheet(String roomId, String friendId) {
    if (roomId.isEmpty) return;

    final InviteCandidatesNotifier sheet =
        _ref.read(inviteCandidatesProvider(roomId).notifier);

    sheet.markInvited(friendId);
  }
}

/// The invitation and room-browser actions.
final Provider<RoomInviteActions> roomInviteActionsProvider =
    Provider<RoomInviteActions>(RoomInviteActions.new);
