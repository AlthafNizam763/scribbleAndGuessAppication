import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/rooms_api.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
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
  Future<Result<Room>> accept(RoomInvitation invitation) async {
    final PlayerProfile? profile = _ref.read(profileProvider);
    if (profile == null) return const Err<Room>(_noProfile);

    final Result<String> seated = await _api.acceptInvitation(invitation.id);

    if (seated case Err<String>(:final Failure failure)) {
      // The invitation is spent either way — expired, already answered, or
      // pointing at a room that has gone — so it comes off the inbox rather
      // than sitting there offering a button that will fail again.
      unawaited(_ref.read(roomInvitationsProvider.notifier).refresh());
      return Err<Room>(failure);
    }

    _ref.read(roomInvitationsProvider.notifier).forget(invitation.id);

    final String code = seated.valueOrNull ?? invitation.roomCode;

    // The account holds the seat; this is what puts the *connection* in the
    // room. The server recognises a returning member, so this is a rejoin
    // rather than a second seat.
    return _ref.read(roomControllerProvider).joinRoom(code);
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
  /// The REST call is what re-validates the room: the browser row it came from
  /// is a snapshot, and a room that had space when the list was drawn may not
  /// now. Its refusal carries the message the player should read.
  Future<Result<Room>> joinPublic(PublicRoom room) async {
    final PlayerProfile? profile = _ref.read(profileProvider);
    if (profile == null) return const Err<Room>(_noProfile);

    final Result<String> seated = await _api.join(room.id);

    if (seated case Err<String>(:final Failure failure)) {
      return Err<Room>(failure);
    }

    return _ref
        .read(roomControllerProvider)
        .joinRoom(seated.valueOrNull ?? room.code);
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
