import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/platform_match.dart';
import 'package:scribble_guess/models/platform_room.dart';

/// The realtime seam for the four platform games.
///
/// The twin of [RoomRepository] and [GameRepository], which serve Scribble &
/// Guess. Kept separate rather than generalised because the two are genuinely
/// two systems: Scribble runs on the `Room`/`Game` services and a process-local
/// registry, these run on `GameRoom`/`GameMatch` with a per-viewer projection,
/// and a single interface covering both would be an interface describing
/// neither. See section 8a of `docs/CONTRACT.md`.
///
/// ## It owns no rules
///
/// Every method below either asks the server to do something and reports what
/// it said, or hands on what the server pushed. Nothing here decides whose
/// turn it is, what a legal move looks like, who won, or what a player may
/// see. A payload that arrives on [matchStream] outranks anything the client
/// believed a moment earlier, including a move it has just sent.
///
/// ## The subscription problem this exists to solve
///
/// Rooms are created and joined over REST, and a REST call has no socket, so
/// nothing in it can put this connection into the room's broadcast channel.
/// [subscribe] is what attaches it. Until it has been called and acked, this
/// repository will receive nothing at all — which is also why it is the
/// reconnect path.
abstract interface class PlatformGameRepository {
  /// The room, replaying the latest snapshot to a late listener.
  Stream<PlatformRoom> get roomStream;

  /// The latest [roomStream] value, read synchronously.
  PlatformRoom? get currentRoom;

  /// Turn-based match projections: Kazhutha, Bluff Bar and Ludo.
  ///
  /// Replays the current match, so a screen built after the match started is
  /// not left blank waiting for somebody to take a turn.
  Stream<PlatformMatch> get matchStream;

  /// The latest [matchStream] value, read synchronously.
  PlatformMatch? get currentMatch;

  /// Space Mystery's realtime frames, ten a second.
  ///
  /// Deliberately raw and deliberately not replayed through the same stream as
  /// [matchStream]: these do not come from an action, they come from the tick,
  /// and at ten a second a replaying controller would keep a frame alive long
  /// after it stopped describing anything.
  Stream<Map<String, dynamic>> get realtimeStream;

  /// The latest realtime frame, or `null` before the first one.
  Map<String, dynamic>? get currentFrame;

  /// Chat lines pushed to the platform room.
  Stream<ChatMessage> get chatStream;

  /// Server refusals, for the screens that want to say so out loud.
  ///
  /// An invalid action is not an exception here. The server refused a move; the
  /// game carries on and the player is told why.
  Stream<Failure> get errorStream;

  /// Attaches this connection to [roomId] and returns the room as it stands.
  ///
  /// Idempotent, and safe to call on every reconnect. The ack also carries the
  /// caller's own view of the running match, if there is one, which is pushed
  /// onto [matchStream] before this future completes — so a caller that awaits
  /// this can read [currentMatch] immediately afterwards.
  Future<Result<PlatformRoom>> subscribe(GameId gameId, String roomId);

  /// Sends a game action and waits for the server to accept or refuse it.
  ///
  /// [event] is one of the named aliases in `SocketEvents` — `kazhutha:draw_card`,
  /// `bluff:challenge` — rather than a raw type, because the call site should
  /// say what is happening.
  ///
  /// The returned [Result] reports only whether the action was *accepted*. The
  /// consequences arrive on [matchStream], because they are the same broadcast
  /// everybody else receives and the actor must not see a different game from
  /// the rest of the table.
  Future<Result<void>> action(
    GameId gameId,
    String matchId,
    String event, [
    Map<String, dynamic> body,
  ]);

  /// Sends a **room**-scoped call, which needs no match id.
  ///
  /// Rematch lives here rather than beside [action] because a rematch is
  /// offered when there is no match running — that is the entire point of it —
  /// so a method that required a match id could never be used for one.
  Future<Result<void>> roomAction(
    GameId gameId,
    String roomId,
    String event, [
    Map<String, dynamic> body,
  ]);

  /// Fires an action and waits for nothing.
  ///
  /// For Space Mystery's movement, which is sent continuously while a stick is
  /// held. Awaiting an ack per frame would put a round trip in the input path
  /// and queue up stale directions behind a slow network; the next frame's
  /// direction is always better than a retry of the last one.
  void send(
    GameId gameId,
    String matchId,
    String event, [
    Map<String, dynamic> body,
  ]);

  /// Sends a chat line to the room.
  Future<Result<void>> sendChat(GameId gameId, String roomId, String text);

  /// Leaves the room and detaches from its channel.
  Future<Result<void>> leave(GameId gameId, String roomId);

  /// Forgets the current room and match without telling the server.
  ///
  /// For the screen teardown path: leaving the *screen* is not leaving the
  /// *room*, and a player who backgrounds the app is still at the table.
  void reset();

  /// Releases the subscription. The repository is unusable afterwards.
  void dispose();
}
