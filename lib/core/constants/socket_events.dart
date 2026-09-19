/// Wire names of every Socket.IO event exchanged with the game server.
///
/// These strings are part of the protocol and are mirrored one-for-one in the
/// backend's `src/constants/socket.constants.ts`, which is the authority. The
/// two lists must stay identical: an event renamed on one side and not the
/// other does not fail to compile, it just silently stops arriving.
///
/// (The older `server/src/protocol.js` in this repository belongs to the
/// retired drawing-only relay and is no longer what the app talks to.)
///
/// Never inline an event name anywhere else.
abstract final class SocketEvents {
  // ---------------------------------------------------------------------------
  // Client -> server
  // ---------------------------------------------------------------------------

  /// Handshake carrying the local profile. Acks with the server clock.
  static const String clientHello = 'c:hello';

  /// Clock-offset probe. Acks with the send and server timestamps.
  static const String clientTimePing = 'c:time:ping';

  /// Creates a room from the given settings and profile.
  static const String clientRoomCreate = 'c:room:create';

  /// Joins an existing room by code.
  static const String clientRoomJoin = 'c:room:join';

  /// Finds a joinable public room and seats the caller, creating one if none.
  ///
  /// The Quick Play button. A socket call rather than a REST one because the
  /// server's live room registry is process-local: whether a seat is free
  /// *right now* is only answerable in the process holding the rooms, and the
  /// seat it produces has to belong to this connection.
  static const String clientRoomQuickPlay = 'c:room:quickPlay';

  /// Leaves the current room.
  static const String clientRoomLeave = 'c:room:leave';

  /// Sets the ready flag of the local player.
  static const String clientRoomReady = 'c:room:ready';

  /// Replaces the room settings. Host only.
  static const String clientRoomSettings = 'c:room:settings';

  /// Seats bot players — Stupids — in the room. Host only, lobby only.
  ///
  /// Payload is `{'count': n}` and nothing else: which Stupids are seated, and
  /// at what difficulty, is the server's decision. The new seats arrive in the
  /// ordinary `s:room:state` push that follows, exactly as a person joining
  /// would, so nothing on the client has to merge a second roster.
  static const String clientRoomAddStupids = 'c:room:addStupids';

  /// Removes every Stupid from the room. Host only, lobby only.
  static const String clientRoomClearStupids = 'c:room:clearStupids';

  /// Removes a player from the room. Host only.
  static const String clientRoomKick = 'c:room:kick';

  /// Removes a player and blocks them from rejoining. Host only.
  static const String clientRoomBan = 'c:room:ban';

  /// Mutes or unmutes a player in chat. Host only.
  static const String clientRoomMute = 'c:room:mute';

  /// Hands the host role to another player. Host only.
  static const String clientRoomTransferHost = 'c:room:transferHost';

  /// Casts a vote to kick a player.
  static const String clientRoomVoteKick = 'c:room:voteKick';

  /// Reports a player with a free-form reason.
  static const String clientRoomReport = 'c:room:report';

  /// Invites a friend to the room this connection is sitting in.
  ///
  /// The room is implicit: the server takes it from the connection rather than
  /// from the payload, so there is no field here that could aim an invitation
  /// at a room the local player is not in.
  static const String clientRoomInvite = 'c:room:invite';

  /// Accepts an invitation and enters the room, in one round trip.
  ///
  /// Distinct from accepting over REST, which seats the *account* but leaves
  /// this connection outside the room until its next join. This does both.
  static const String clientRoomInviteAccept = 'c:room:inviteAccept';

  /// Declines an invitation. Needs no room: the invitee is not in one.
  static const String clientRoomInviteReject = 'c:room:inviteReject';

  /// Starts the match. Host only.
  static const String clientGameStart = 'c:game:start';

  /// Picks one of the offered words by index. Drawer only.
  static const String clientGameSelectWord = 'c:game:selectWord';

  /// Restarts the match with the same players. Host only.
  static const String clientGamePlayAgain = 'c:game:playAgain';

  /// Announces the first points of a new stroke. No ack.
  static const String clientDrawBegin = 'c:draw:begin';

  /// Appends a batch of points to a live stroke. No ack.
  static const String clientDrawAppend = 'c:draw:append';

  /// Ends a live stroke. No ack.
  static const String clientDrawEnd = 'c:draw:end';

  /// Undoes the last stroke of the drawer. No ack.
  static const String clientDrawUndo = 'c:draw:undo';

  /// Redoes the last undone stroke of the drawer. No ack.
  static const String clientDrawRedo = 'c:draw:redo';

  /// Clears the board. No ack.
  static const String clientDrawClear = 'c:draw:clear';

  /// Sends a chat message, which doubles as a guess while drawing.
  static const String clientChatSend = 'c:chat:send';

  // --- voice ---------------------------------------------------------------
  //
  // Signalling only. Audio never travels over this socket: these events carry
  // SDP and ICE candidates, and the voices themselves go peer to peer.

  /// Asks to join the room's voice group. Refused for the current drawer.
  static const String clientVoiceJoin = 'c:voice:join';

  /// Leaves the voice group. Always allowed, drawer included.
  static const String clientVoiceLeave = 'c:voice:leave';

  /// Relays an SDP offer to one peer.
  static const String clientVoiceOffer = 'c:voice:offer';

  /// Relays an SDP answer to one peer.
  static const String clientVoiceAnswer = 'c:voice:answer';

  /// Relays one ICE candidate to one peer. No ack.
  static const String clientVoiceIce = 'c:voice:ice';

  /// Publishes the local microphone state to the voice group.
  static const String clientVoiceMute = 'c:voice:mute';

  // ---------------------------------------------------------------------------
  // Server -> client
  // ---------------------------------------------------------------------------

  /// Full room snapshot after any membership or settings change.
  static const String serverRoomState = 's:room:state';

  /// The room was closed, with a reason.
  static const String serverRoomClosed = 's:room:closed';

  /// The local player was kicked or banned, with a reason.
  static const String serverYouKicked = 's:you:kicked';

  /// Full game snapshot. The word is omitted for non-drawers.
  static const String serverGameState = 's:game:state';

  /// The words the drawer may choose from. Drawer only.
  static const String serverGameWordChoices = 's:game:wordChoices';

  /// A new turn started.
  static const String serverGameRoundStart = 's:game:roundStart';

  /// Extra letters were revealed in the masked word.
  static const String serverGameHint = 's:game:hint';

  /// The turn ended, carrying the round result and the new game state.
  static const String serverGameRoundEnd = 's:game:roundEnd';

  /// The match ended, carrying the final standings.
  static const String serverGameEnd = 's:game:end';

  /// A remote stroke started.
  static const String serverDrawBegin = 's:draw:begin';

  /// Points were appended to a remote stroke.
  static const String serverDrawAppend = 's:draw:append';

  /// A remote stroke ended.
  static const String serverDrawEnd = 's:draw:end';

  /// A remote stroke was undone.
  static const String serverDrawUndo = 's:draw:undo';

  /// A previously undone remote stroke was restored.
  static const String serverDrawRedo = 's:draw:redo';

  /// The board was cleared.
  static const String serverDrawClear = 's:draw:clear';

  /// The full stroke list, sent to late joiners and after a reconnect.
  static const String serverDrawSnapshot = 's:draw:snapshot';

  /// A chat, guess or system message.
  static const String serverChatMessage = 's:chat:message';

  /// Periodic broadcast of the authoritative server clock.
  static const String serverTimeSync = 's:time:sync';

  /// An out-of-band failure that is not tied to a single ack.
  static const String serverError = 's:error';

  // --- voice ---------------------------------------------------------------

  /// This client's own voice status: whether voice is on for it, the ICE
  /// servers to use, and the peers it should be connected to.
  ///
  /// Pushed whenever the server takes voice away — above all when this player
  /// becomes the drawer — so the microphone goes off even if the client never
  /// noticed the pen changed hands.
  static const String serverVoiceState = 's:voice:state';

  /// Somebody joined the voice group.
  static const String serverVoicePeerJoined = 's:voice:peerJoined';

  /// Somebody left the voice group, or was removed from it.
  static const String serverVoicePeerLeft = 's:voice:peerLeft';

  /// An SDP offer from one peer.
  static const String serverVoiceOffer = 's:voice:offer';

  /// An SDP answer from one peer.
  static const String serverVoiceAnswer = 's:voice:answer';

  /// One ICE candidate from one peer.
  static const String serverVoiceIce = 's:voice:ice';

  /// A peer muted or unmuted their microphone.
  static const String serverVoiceMute = 's:voice:mute';

  /// A refused voice operation, carrying the server's `ErrorCode`.
  static const String serverVoiceError = 's:voice:error';

  // --- room invitations and membership ---------------------------------------

  /// Somebody invited this player to their room.
  ///
  /// Addressed to a *player*, not to a room, so it arrives whether or not this
  /// device is in a game and on every device the player is signed in on. That
  /// is what makes an invitation appear without a refresh.
  ///
  /// Unlike the friend pushes, this one carries the whole invitation rather
  /// than only a nudge — the dialog has to be drawable the instant it lands,
  /// and a card that waited for a REST read would appear a beat late or not at
  /// all if the player was on a poor connection. The inbox re-reads over REST
  /// anyway, and that read is what wins if the two ever disagree.
  static const String serverRoomInvitationReceived =
      's:room:invitationReceived';

  /// An invitation this player sent was accepted.
  static const String serverRoomInvitationAccepted =
      's:room:invitationAccepted';

  /// An invitation this player sent was declined.
  static const String serverRoomInvitationRejected =
      's:room:invitationRejected';

  /// An invitation addressed to this player is no longer answerable.
  static const String serverRoomInvitationExpired = 's:room:invitationExpired';

  /// A player took a seat in the room this device is in.
  ///
  /// Strictly additional to [serverRoomState], which still carries the
  /// authoritative player list. This says *what changed*; the snapshot says
  /// what is, and the snapshot wins wherever they disagree.
  static const String serverRoomPlayerJoined = 's:room:playerJoined';

  /// A player gave up their seat.
  static const String serverRoomPlayerLeft = 's:room:playerLeft';

  /// The room changed, carrying the same snapshot as [serverRoomState].
  static const String serverRoomUpdated = 's:room:updated';

  /// A refused room operation that was not tied to an ack.
  static const String serverRoomError = 's:room:error';

  // --- friends ---------------------------------------------------------------

  /// Somebody asked to be your friend.
  ///
  /// These are addressed to a *player*, not to a room, so they arrive whether
  /// or not this device is in a game and on every device the player is signed
  /// in on.
  ///
  /// They carry a public card and an id, never anything sensitive, and they
  /// are only ever a nudge to refresh: the authoritative lists come from REST.
  /// A client that misses one — it was backgrounded, or the realtime server
  /// restarted — is never wrong for long, because every list reloads on open
  /// and on pull-to-refresh.
  ///
  /// The server sends each of these under two names: this `s:friend:*`
  /// spelling and a flatter `friend:*` one. Only these are listened for, so
  /// nothing arrives twice.
  static const String serverFriendRequestReceived = 's:friend:requestReceived';

  /// A request this player sent was accepted.
  static const String serverFriendRequestAccepted = 's:friend:requestAccepted';

  /// A request this player sent was declined.
  static const String serverFriendRequestRejected = 's:friend:requestRejected';

  /// A request pointing at this player was withdrawn.
  static const String serverFriendRequestCancelled =
      's:friend:requestCancelled';

  /// A friendship ended.
  static const String serverFriendRemoved = 's:friend:removed';

  /// This player blocked somebody. Only ever sent to the blocker.
  static const String serverFriendBlocked = 's:friend:blocked';

  /// This player lifted a block. Only ever sent to the blocker.
  static const String serverFriendUnblocked = 's:friend:unblocked';

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  /// A notification was written for this player.
  ///
  /// Carries the whole row plus the new unread count, so a toast can be drawn
  /// and the badge updated without a round trip. Addressed to the *person*,
  /// so it arrives on every device they are signed in on.
  ///
  /// This is additional to the friend and invitation pushes rather than a
  /// replacement for them: those tell a *screen* its list is stale, this tells
  /// the *badge* its count changed, and a client is rarely showing both.
  static const String serverNotificationNew = 's:notification:new';

  /// The unread count changed without a new notification arriving.
  ///
  /// Emitted on read, read-all and delete. It is what keeps a second device in
  /// step: clearing the badge on a phone has to clear it on the tablet, and
  /// neither device learns that from [serverNotificationNew].
  static const String serverNotificationUnread = 's:notification:unread';

  // ---------------------------------------------------------------------------
  // Progression
  // ---------------------------------------------------------------------------

  /// This player crossed a level boundary.
  ///
  /// Carries the new level and its tier title. Addressed to the *person*, so
  /// it arrives on every device they are signed in on.
  ///
  /// This exists alongside the level-up notification rather than instead of
  /// it, and the difference is timing: the animation has to play on the result
  /// screen the player is looking at now, while the notification is the
  /// durable record a backgrounded player finds later.
  static const String serverProgressionLevelUp = 's:progression:levelUp';

  // ---------------------------------------------------------------------------
  // Chat extras
  // ---------------------------------------------------------------------------

  /// Tells the room this player is typing. No ack.
  ///
  /// The one message in this protocol worth nothing a second after it is sent,
  /// so it is never acked, persisted or reconciled. The client stops showing a
  /// stale indicator on its own timer, which means a dropped packet costs a
  /// lingering dot rather than somebody who appears to type forever.
  static const String clientChatTyping = 'c:chat:typing';

  /// Adds or removes one emoji reaction on one message.
  static const String clientChatReact = 'c:chat:react';

  /// Withdraws one of this player's own messages.
  static const String clientChatDelete = 'c:chat:delete';

  /// Reports one message to the operators.
  static const String clientChatReport = 'c:chat:report';

  /// Somebody started or stopped typing.
  static const String serverChatTyping = 's:chat:typing';

  /// A message's reaction tally changed.
  static const String serverChatReaction = 's:chat:reaction';

  /// A message was withdrawn; take it out of the transcript.
  static const String serverChatDeleted = 's:chat:deleted';

  // ---------------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------------

  /// Every friend event, for a listener that just needs to know "refresh".
  static const List<String> friendEvents = <String>[
    serverFriendRequestReceived,
    serverFriendRequestAccepted,
    serverFriendRequestRejected,
    serverFriendRequestCancelled,
    serverFriendRemoved,
    serverFriendBlocked,
    serverFriendUnblocked,
  ];

  /// Every invitation push, for a listener that just needs to know "refresh".
  static const List<String> roomInvitationEvents = <String>[
    serverRoomInvitationReceived,
    serverRoomInvitationAccepted,
    serverRoomInvitationRejected,
    serverRoomInvitationExpired,
  ];

  /// The chat extras, for a listener that only needs to refresh.
  static const List<String> chatExtraEvents = <String>[
    serverChatTyping,
    serverChatReaction,
    serverChatDeleted,
  ];

  /// The progression pushes, for a listener that only needs to know.
  static const List<String> progressionEvents = <String>[
    serverProgressionLevelUp,
  ];

  /// Both notification pushes, for a listener that only needs the count.
  static const List<String> notificationEvents = <String>[
    serverNotificationNew,
    serverNotificationUnread,
  ];

  /// Every membership push, for a listener watching one room fill up.
  static const List<String> roomMembershipEvents = <String>[
    serverRoomPlayerJoined,
    serverRoomPlayerLeft,
    serverRoomUpdated,
  ];

  // --- automatic tournaments -----------------------------------------------

  /// Subscribes this connection to tournament announcements.
  ///
  /// Sent when the tournament screen opens and again after every reconnect:
  /// channel membership is per connection and does not survive one, so a
  /// client that only subscribed at startup would go quiet after the first
  /// dropped connection and never notice.
  static const String clientTournamentWatch = 'c:tournament:watch';

  /// Unsubscribes. Sent when the screen closes.
  static const String clientTournamentUnwatch = 'c:tournament:unwatch';

  /// A tournament was created in a slot.
  static const String serverTournamentCreated = 's:tournament:created';

  /// Registration opened.
  static const String serverTournamentRegistrationOpened =
      's:tournament:registrationOpened';

  /// Somebody registered or withdrew; the counts changed.
  static const String serverTournamentRegistrationUpdated =
      's:tournament:registrationUpdated';

  /// Registration closed; registered players must confirm.
  static const String serverTournamentCheckInOpened =
      's:tournament:checkInOpened';

  /// Check-in closed. The roster is final.
  static const String serverTournamentCheckInClosed =
      's:tournament:checkInClosed';

  /// The bracket is drawn and play has begun.
  static const String serverTournamentStarted = 's:tournament:started';

  /// A pairing filled in, or a result landed.
  static const String serverTournamentBracketUpdated =
      's:tournament:bracketUpdated';

  /// This player's match room is open. Sent only to its two players.
  static const String serverTournamentMatchReady = 's:tournament:matchReady';

  /// A match began.
  static const String serverTournamentMatchStarted =
      's:tournament:matchStarted';

  /// A match was decided.
  static const String serverTournamentMatchCompleted =
      's:tournament:matchCompleted';

  /// Every match in a round finished.
  static const String serverTournamentRoundCompleted =
      's:tournament:roundCompleted';

  /// The final was decided.
  static const String serverTournamentCompleted = 's:tournament:completed';

  /// A tournament was abandoned.
  static const String serverTournamentCancelled = 's:tournament:cancelled';

  /// A released slot was refilled.
  static const String serverTournamentNextScheduled =
      's:tournament:nextScheduled';

  /// An AI player joined a roster.
  static const String serverTournamentBotAdded = 's:tournament:botAdded';

  /// An AI player's state changed.
  static const String serverTournamentBotStatusUpdated =
      's:tournament:botStatusUpdated';

  /// Every tournament push, for a listener that only needs to know "refresh".
  ///
  /// ## Why the listener refreshes rather than patching
  ///
  /// Each of these could carry enough to patch the screen in place, and doing
  /// so would mean a second model of the tournament lifecycle living in the
  /// app — which is precisely the thing this feature exists to have only one
  /// of. Three slots is a small response; re-reading it is both simpler and
  /// impossible to get subtly wrong.
  static const List<String> tournamentEvents = <String>[
    serverTournamentCreated,
    serverTournamentRegistrationOpened,
    serverTournamentRegistrationUpdated,
    serverTournamentCheckInOpened,
    serverTournamentCheckInClosed,
    serverTournamentStarted,
    serverTournamentBracketUpdated,
    serverTournamentMatchReady,
    serverTournamentMatchStarted,
    serverTournamentMatchCompleted,
    serverTournamentRoundCompleted,
    serverTournamentCompleted,
    serverTournamentCancelled,
    serverTournamentNextScheduled,
    serverTournamentBotAdded,
    serverTournamentBotStatusUpdated,
  ];

// ---------------------------------------------------------------------------
  // Platform games — Kazhutha, Bluff Bar, Space Mystery, Ludo
  // ---------------------------------------------------------------------------

  /// The `game:*` namespace, mirrored in the backend's
  /// `src/socket/game_platform.socket.ts` and documented in section 8a of
  /// `docs/CONTRACT.md`.
  ///
  /// ## Why this is a second namespace and not more `c:`/`s:` events
  ///
  /// Scribble & Guess runs on the `Room`/`Game` services and its own in-process
  /// room registry. The other four games run on the platform `GameRoom` /
  /// `GameMatch` layer, which has its own lifecycle, its own bot driver and its
  /// own per-viewer projection. They are genuinely two systems, and the wire
  /// says so: `SCRIBBLE_GUESS` is refused by every event below, on purpose.
  ///
  /// ## The one rule that matters
  ///
  /// Every payload carrying game state is **that viewer's projection**, not the
  /// match. Two players in one match receive different objects from the same
  /// broadcast. Nothing the client is not entitled to — another hand, a role, a
  /// position behind a wall — is ever in the payload, so there is nothing for a
  /// modified client to reveal. Never reconstruct "the real state" by merging
  /// what several payloads implied.

  /// Creates a platform room. Acks `{room}`.
  static const String clientGameRoomCreate = 'game:room_created';

  /// Takes a seat in a platform room, by id or by code. Acks `{room}`.
  static const String clientGameRoomJoin = 'game:player_joined';

  /// Leaves the current platform room. Acks `{room}`.
  static const String clientGameRoomLeave = 'game:player_left';

  /// Sets the ready flag. Acks `{room, started}`.
  static const String clientGameRoomReady = 'game:player_ready';

  /// Attaches this socket to a room the player is **already** seated in.
  ///
  /// The bridge between the REST lobby and the realtime game, and the reason
  /// it exists is worth keeping: rooms are created and joined over REST, and a
  /// REST call has no socket attached to it, so nothing in it can put this
  /// connection into the room's broadcast channel. Without this call the lobby
  /// works and the match never arrives.
  ///
  /// It is also the reconnect seam — it acks `{room, match}` with the caller's
  /// own view, so a client that dropped is handed the present rather than
  /// waiting for the next thing to happen.
  static const String clientGameSubscribe = 'game:subscribe';

  /// A generic game action: `{gameId, matchId, type, ...}`. Acks `{state}`.
  ///
  /// Every game also has aliases below. They are the same code path — the
  /// alias only supplies `type` — so prefer the named one at a call site,
  /// because `bluff:challenge` says what is happening and `game:action` does
  /// not.
  static const String clientGameAction = 'game:action';

  /// Sends a message to the platform room. Acks `{message}`.
  static const String clientGameChatSend = 'game:chat_message';

  /// Offers another round at the same table. Acks `{rematch}`.
  ///
  /// An offer rather than a command: everybody answers, the ones who said yes
  /// play, and the ones who said no leave the room before the next deal.
  /// Tapping it twice is an acceptance of whoever asked first, not a second
  /// offer — the server treats a duplicate as agreement.
  static const String clientGameRematchRequest = 'game:rematch_request';

  /// Answers a standing offer: `{accept}`. Acks `{rematch}`.
  ///
  /// Declining also leaves the room. That is deliberate — a player who said no
  /// and stayed seated would be carried into the next deal by everybody else's
  /// acceptances.
  static const String clientGameRematchRespond = 'game:rematch_respond';

  // -- Kazhutha --------------------------------------------------------------

  /// Draws one card from another player's fan.
  ///
  /// `{targetPlayerId, cardIndex?}`. The index is a position, not a card: the
  /// server reshuffles that hand immediately before the pick, so choosing
  /// where to reach is tactile and carries no information. Omitting it draws
  /// at random.
  static const String clientKazhuthaDraw = 'kazhutha:draw_card';

  // -- Bluff Bar -------------------------------------------------------------

  /// Puts one to three cards face down, claiming they are all the table rank.
  /// `{cardIds, reaction?}`.
  static const String clientBluffDeclare = 'bluff:declare';

  /// Calls the previous claim a lie. Legal only on your turn, never your own.
  static const String clientBluffChallenge = 'bluff:challenge';

  /// Table talk. Flavour only; it can never affect a rule.
  static const String clientBluffReact = 'bluff:react';

  // -- Space Mystery ---------------------------------------------------------

  /// A movement **direction**, never a position: `{dx, dy}`.
  ///
  /// Clamped to a unit vector on arrival and integrated against the floor plan
  /// server-side, so a thousand of these in a second move a player exactly as
  /// far as twenty do. Sent continuously while a stick is held, which is why
  /// it has its own rate-limit bucket on the server.
  static const String clientSpaceMove = 'space:move';

  /// Starts work at a console: `{stationId}`. The server times it and decides
  /// when — and whether — it completed.
  static const String clientSpaceTask = 'space:task';

  /// Traitor only: `{targetId}`. Refused unless the server agrees they are
  /// standing on them and off cooldown.
  static const String clientSpaceEliminate = 'space:eliminate';

  /// Reports a body you are standing next to. Opens a meeting.
  static const String clientSpaceReport = 'space:report';

  /// Calls an emergency meeting from the table. One per player per match.
  static const String clientSpaceMeeting = 'space:meeting';

  /// Votes in a meeting: `{targetId}`. An empty id is a deliberate skip.
  static const String clientSpaceVote = 'space:vote';

  /// Traitor only: `{kind}` — `breach`, `lights` or `comms`.
  static const String clientSpaceSabotage = 'space:sabotage';

  /// Traitor only. `{ventId}` moves to another mouth on the same network;
  /// omitting it climbs out where you are.
  static const String clientSpaceVent = 'space:vent';

  // -- Ludo --------------------------------------------------------------

  /// Asks the server for a dice roll.
  ///
  /// The number comes back in the broadcast, not from here. There is no local
  /// random in this game — a client that rolled its own dice would be a client
  /// that rolled sixes all afternoon.
  ///
  /// Refused when a roll is already on the table: one must be spent on a move
  /// before another is asked for.
  static const String clientLudoRoll = 'ludo:dice_rolled';

  /// Moves one counter with the roll on the table: `{tokenIndex}`.
  ///
  /// Whether that counter can legally move is the server's decision. The board
  /// lights the ones it believes are movable so a player is not offered four
  /// taps and refused three, but the server checks again and its answer wins.
  static const String clientLudoMove = 'ludo:token_moved';

  // -- Platform voice --------------------------------------------------------

  /// Joins the platform room's voice mesh. Acks `{iceServers, peers}`.
  static const String clientGameVoiceJoin = 'game:voice_joined';

  /// Leaves the voice mesh.
  static const String clientGameVoiceLeave = 'game:voice_left';

  /// WebRTC signalling, relayed to one peer in the room. Audio never travels
  /// over the socket — only the SDP and ICE that set up the peer connection.
  static const String clientGameVoiceOffer = 'game:voice_offer';
  static const String clientGameVoiceAnswer = 'game:voice_answer';
  static const String clientGameVoiceIce = 'game:voice_ice_candidate';

  /// Announces the local microphone state to the room.
  static const String clientGameVoiceMute = 'game:player_muted';

  // -- Server -> client ------------------------------------------------------

  /// The room roster changed: `{room, event}`. Carries the reason in `event`,
  /// which is the name of whichever call caused it.
  static const String serverGameRoomUpdated = 'game:room_updated';

  /// Echo of a room this socket created: `{room}`.
  static const String serverGameRoomCreated = 'game:room_created';

  /// A match has begun. Carries this viewer's first projection.
  static const String serverGameMatchStarted = 'game:match_started';

  /// A new projection for this viewer, after anybody's action.
  static const String serverGameMatchState = 'game:match_state';

  /// The match is over. `result` is populated and roles, if any, are revealed.
  static const String serverGameMatchCompleted = 'game:match_completed';

  /// A chat line in the platform room: `{message}`.
  static const String serverGameChatMessage = 'game:chat_message';

  /// Space Mystery's realtime frame, ten times a second, one per viewer.
  ///
  /// Distinct from [serverGameMatchState] because it does not come from an
  /// action — it comes from the tick — and because it arrives far too often to
  /// route through the same path a turn-based update does.
  static const String serverSpaceState = 'space:state';

  /// Platform voice signalling, relayed from another player. Each carries
  /// `fromUserId`.
  static const String serverGameVoiceJoined = 'game:voice_joined';
  static const String serverGameVoiceLeft = 'game:voice_left';
  static const String serverGameVoiceOffer = 'game:voice_offer';
  static const String serverGameVoiceAnswer = 'game:voice_answer';
  static const String serverGameVoiceIce = 'game:voice_ice_candidate';
  static const String serverGameVoiceMuted = 'game:player_muted';

  /// The server withdrawing voice from this player.
  ///
  /// Pushed rather than acked, because the reason is never something the
  /// player did: a meeting ended, they were ejected, the match finished. It
  /// carries the same shape as the join ack with `enabled: false`, so one
  /// handler covers both.
  static const String serverGameVoiceState = 'game:voice_state';

  /// A refused signalling frame. The out-of-band twin of `s:voice:error`.
  static const String serverGameVoiceError = 'game:voice_error';

  /// Every platform-game push, for attaching and detaching in one pass.
  static const List<String> platformGameEvents = <String>[
    serverGameRoomUpdated,
    serverGameRoomCreated,
    serverGameMatchStarted,
    serverGameMatchState,
    serverGameMatchCompleted,
    serverGameChatMessage,
    serverSpaceState,
  ];

  /// Platform voice pushes, kept apart because the voice service subscribes to
  /// these and nothing else.
  static const List<String> platformVoiceEvents = <String>[
    serverGameVoiceJoined,
    serverGameVoiceLeft,
    serverGameVoiceOffer,
    serverGameVoiceAnswer,
    serverGameVoiceIce,
    serverGameVoiceMuted,
    serverGameVoiceState,
    serverGameVoiceError,
  ];

  /// Every server-originated event, in protocol order.
  ///
  /// Useful for attaching and detaching listeners in one pass.
  static const List<String> serverEvents = <String>[
    serverRoomState,
    serverRoomClosed,
    serverYouKicked,
    serverGameState,
    serverGameWordChoices,
    serverGameRoundStart,
    serverGameHint,
    serverGameRoundEnd,
    serverGameEnd,
    serverDrawBegin,
    serverDrawAppend,
    serverDrawEnd,
    serverDrawUndo,
    serverDrawRedo,
    serverDrawClear,
    serverDrawSnapshot,
    serverChatMessage,
    serverTimeSync,
    serverError,
    serverVoiceState,
    serverVoicePeerJoined,
    serverVoicePeerLeft,
    serverVoiceOffer,
    serverVoiceAnswer,
    serverVoiceIce,
    serverVoiceMute,
    serverVoiceError,
    ...friendEvents,
    ...roomInvitationEvents,
    ...roomMembershipEvents,
    ...notificationEvents,
    ...progressionEvents,
    ...chatExtraEvents,
    ...tournamentEvents,
    ...platformGameEvents,
    ...platformVoiceEvents,
    serverRoomError,
  ];
}
