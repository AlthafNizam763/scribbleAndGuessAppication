import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_settings.dart';

/// Lobby-side seam between the UI and whatever backend hosts the room.
///
/// Implementations may be socket backed (`SocketRoomRepository`) or fully
/// in-memory (`LocalRoomRepository` for practice mode); nothing above this
/// interface may depend on the transport.
///
/// The server is authoritative for every piece of state exposed here. The room
/// snapshot pushed on [roomStream] is the only truth about membership, host
/// identity, ready flags and mute flags: an implementation must never mutate a
/// local copy optimistically and present it as fact. Likewise every
/// host-restricted call below is a *request*; the server re-checks the caller's
/// role and may answer with [AppErrorCode.notHost] even when the local [Room]
/// says otherwise.
///
/// No method throws. Failures are returned as [Err] carrying a [Failure].
abstract interface class RoomRepository {
  /// Server-authoritative snapshots of the joined room.
  ///
  /// Emits a fresh [Room] whenever membership, settings, host or status
  /// change. Replays the latest snapshot to new listeners so a screen that
  /// subscribes late still renders immediately. Completes only on [dispose].
  Stream<Room> get roomStream;

  /// Out-of-band failures that belong to no particular call.
  ///
  /// Carries pushes such as the room being closed, this player being kicked or
  /// banned, and connection loss — i.e. [AppErrorCode.kicked],
  /// [AppErrorCode.banned], [AppErrorCode.connectionLost] and
  /// [AppErrorCode.serverError]. Errors that answer a specific request are
  /// returned by that request instead of being pushed here.
  Stream<Failure> get errorStream;

  /// The most recent room snapshot, or `null` when not in a room.
  ///
  /// A synchronous convenience mirroring the last value of [roomStream]; it is
  /// a cache of server state, never a local edit.
  Room? get currentRoom;

  /// Asks the server to create a room owned by [profile] with [settings].
  ///
  /// [settings] should already satisfy `RoomSettings.validate()`, but the
  /// server validates again and is the final word: the returned [Room] carries
  /// the settings it actually accepted, including the generated room code and
  /// the host id.
  ///
  /// Fails with [AppErrorCode.validation] for rejected settings,
  /// [AppErrorCode.network] or [AppErrorCode.timeout] when the request never
  /// lands, and [AppErrorCode.serverError] otherwise.
  Future<Result<Room>> createRoom(RoomSettings settings, PlayerProfile profile);

  /// Joins the room identified by [code] as [profile].
  ///
  /// [code] is matched case-insensitively against
  /// `AppConstants.roomCodeAlphabet`; the server decides whether the seat is
  /// granted.
  ///
  /// Fails with [AppErrorCode.invalidCode] for a malformed code,
  /// [AppErrorCode.roomNotFound], [AppErrorCode.roomFull],
  /// [AppErrorCode.gameInProgress], [AppErrorCode.nameTaken] or
  /// [AppErrorCode.banned], plus the usual transport codes.
  Future<Result<Room>> joinRoom(String code, PlayerProfile profile);

  /// Leaves the current room.
  ///
  /// Succeeds (as a no-op) when no room is joined, so screens can call it
  /// unconditionally while tearing down. When the leaver was the host the
  /// server, not the client, picks the replacement host or closes the room.
  Future<Result<void>> leaveRoom();

  /// Sets this player's lobby ready flag to [ready].
  ///
  /// Only meaningful while the room is waiting; the server ignores or rejects
  /// the change once the match is running with [AppErrorCode.invalidAction].
  /// The visible flag arrives back through [roomStream].
  Future<Result<void>> setReady(bool ready);

  /// Requests a settings change for the room. Host only.
  ///
  /// The server re-checks the host role and re-validates [settings]; expect
  /// [AppErrorCode.notHost], [AppErrorCode.validation] or
  /// [AppErrorCode.invalidAction] when a match is already in progress.
  Future<Result<void>> updateSettings(RoomSettings settings);

  /// Removes [playerId] from the room. Host only.
  ///
  /// The target may rejoin afterwards; use [banPlayer] to keep them out.
  /// Fails with [AppErrorCode.notHost] or [AppErrorCode.invalidAction] when
  /// the id is not a current member.
  Future<Result<void>> kickPlayer(String playerId);

  /// Removes [playerId] and blocks them from rejoining. Host only.
  ///
  /// The server records the id in `Room.bannedIds`; later join attempts by
  /// that player fail with [AppErrorCode.banned]. Fails with
  /// [AppErrorCode.notHost] for anyone else.
  Future<Result<void>> banPlayer(String playerId);

  /// Sets the chat mute flag of [playerId] to [muted]. Host only.
  ///
  /// Muting is enforced on the server: a muted player's messages are dropped
  /// there rather than merely hidden by the client, so `Player.isMuted` is a
  /// mirror of server state and never a local toggle. Fails with
  /// [AppErrorCode.notHost].
  Future<Result<void>> mutePlayer(String playerId, bool muted);

  /// Hands the host role to [playerId]. Host only.
  ///
  /// After the server accepts, the caller loses every host-only capability;
  /// the new `Room.hostId` arrives through [roomStream]. Fails with
  /// [AppErrorCode.notHost] or [AppErrorCode.invalidAction] when the target is
  /// not a connected member.
  Future<Result<void>> transferHost(String playerId);

  /// Casts this player's vote to kick [playerId].
  ///
  /// Available to any member while `RoomSettings.allowVoteKick` is on. The
  /// server tallies the votes and decides whether the threshold was met, so an
  /// [Ok] means the vote was recorded, not that the target was removed. Fails
  /// with [AppErrorCode.invalidAction] when vote-kick is disabled or the
  /// caller already voted.
  Future<Result<void>> voteKick(String playerId);

  /// Reports [playerId] to the server with a free-form [reason].
  ///
  /// Purely a moderation signal: it never changes room state, and the server
  /// decides what to do with it. Fails with [AppErrorCode.validation] for an
  /// empty or over-long reason.
  Future<Result<void>> reportPlayer(String playerId, String reason);

  /// Releases subscriptions and closes [roomStream] and [errorStream].
  ///
  /// Safe to call more than once; the instance is unusable afterwards.
  void dispose();
}
