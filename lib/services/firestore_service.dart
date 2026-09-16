import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scribble_guess/core/constants/firebase_constants.dart';
import 'package:scribble_guess/core/errors/app_exception.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/models/round_result.dart';

/// Reads from Firestore, and only reads.
///
/// Every *write* in the game goes through a callable Cloud Function, because
/// the rules deliberately make the interesting documents unwritable by clients
/// (§49). What is left for this class is the live half of the loop: turning
/// document snapshots into the app's own models.
///
/// The mapping lives here rather than on the models so the models stay
/// transport-agnostic — they are plain value types, and nothing in `models/`
/// imports Firebase.
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // -------------------------------------------------------------------------
  // References
  // -------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _room(String roomId) =>
      _db.collection(FirebaseCollections.rooms).doc(roomId);

  CollectionReference<Map<String, dynamic>> _players(String roomId) =>
      _room(roomId).collection(FirebaseCollections.players);

  CollectionReference<Map<String, dynamic>> _messages(String roomId) =>
      _room(roomId).collection(FirebaseCollections.messages);

  // -------------------------------------------------------------------------
  // Rooms
  // -------------------------------------------------------------------------

  /// The room document, and the roster, as one combined [Room].
  ///
  /// The room and its players are two separate documents in Firestore but one
  /// object to the UI, so the two snapshot streams are joined here. Both are
  /// re-emitted whenever either side changes, which is what lets the lobby
  /// show a player list that updates in real time (§12).
  Stream<Room?> watchRoom(String roomId) {
    final Stream<DocumentSnapshot<Map<String, dynamic>>> roomStream =
        _room(roomId).snapshots();
    final Stream<QuerySnapshot<Map<String, dynamic>>> playerStream =
        _players(roomId).orderBy(FirebaseFields.joinedAt).snapshots();

    return _combineLatest2(roomStream, playerStream, (
      DocumentSnapshot<Map<String, dynamic>> roomSnap,
      QuerySnapshot<Map<String, dynamic>> playerSnap,
    ) {
      if (!roomSnap.exists) return null;
      final Map<String, dynamic> data = roomSnap.data() ?? <String, dynamic>{};
      final List<Player> players = <Player>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in playerSnap.docs)
          _playerFrom(doc.data(), data),
      ];
      return _roomFrom(roomSnap.id, data, players);
    }).handleError(_rethrowAsAppException);
  }

  /// The game state of a room, on its own.
  ///
  /// Separate from [watchRoom] so the game screen can watch the phase and the
  /// timer without rebuilding on every roster change (§47).
  Stream<GameState> watchGameState(String roomId) {
    return _room(roomId)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) {
          final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
          return _gameStateFrom(asMap(data[FirebaseFields.game]));
        })
        .distinct()
        .handleError(_rethrowAsAppException);
  }

  /// A one-off read of a room.
  Future<Room?> getRoom(String roomId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _room(roomId).get();
      if (!snap.exists) return null;
      final QuerySnapshot<Map<String, dynamic>> players =
          await _players(roomId).orderBy(FirebaseFields.joinedAt).get();
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      return _roomFrom(
        snap.id,
        data,
        <Player>[
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
              in players.docs)
            _playerFrom(doc.data(), data),
        ],
      );
    } on Object catch (error, stack) {
      throw toAppException(error, stack);
    }
  }

  // -------------------------------------------------------------------------
  // Messages
  // -------------------------------------------------------------------------

  /// The chat feed, oldest first.
  ///
  /// Capped at [limit] because a long game accumulates hundreds of lines and
  /// the panel only ever shows the tail.
  Stream<List<ChatMessage>> watchMessages(String roomId, {int limit = 200}) {
    return _messages(roomId)
        .orderBy(FirebaseFields.createdAt, descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
          final List<ChatMessage> messages = <ChatMessage>[
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in snap.docs)
              _messageFrom(doc.data()),
          ];
          // Firestore can only limit from one end, so the newest are fetched
          // and then reversed for display.
          return messages.reversed.toList(growable: false);
        })
        .handleError(_rethrowAsAppException);
  }

  // -------------------------------------------------------------------------
  // Rounds
  // -------------------------------------------------------------------------

  /// The result of the most recently completed round (§38).
  Stream<RoundResult?> watchLatestRound(String roomId) {
    return _room(roomId)
        .collection(FirebaseCollections.rounds)
        .orderBy('turnIndex', descending: true)
        .limit(1)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
          if (snap.docs.isEmpty) return null;
          return _roundResultFrom(snap.docs.first.data());
        })
        .handleError(_rethrowAsAppException);
  }

  // -------------------------------------------------------------------------
  // Profiles
  // -------------------------------------------------------------------------

  /// A player's stored profile, or null when they have never saved one.
  Future<PlayerProfile?> getProfile(String userId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _db.collection(FirebaseCollections.users).doc(userId).get();
      if (!snap.exists) return null;
      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      return PlayerProfile(
        name: asString(data[FirebaseFields.displayName]),
        avatarId: asInt(data[FirebaseFields.avatarId]),
        avatarColorIndex: asInt(data[FirebaseFields.avatarColorIndex]),
      );
    } on Object catch (error, stack) {
      throw toAppException(error, stack);
    }
  }

  /// Creates or updates the caller's own profile document.
  ///
  /// One of the very few direct client writes in the app, and the rules narrow
  /// it hard: a player may only write their own document, and only the
  /// presentation fields — never `gamesPlayed`, `gamesWon` or `totalScore`.
  Future<void> saveProfile(String userId, PlayerProfile profile) async {
    try {
      final DocumentReference<Map<String, dynamic>> ref =
          _db.collection(FirebaseCollections.users).doc(userId);
      final DocumentSnapshot<Map<String, dynamic>> existing = await ref.get();

      final Map<String, dynamic> presentation = <String, dynamic>{
        FirebaseFields.displayName: profile.name,
        FirebaseFields.avatarId: profile.avatarId,
        FirebaseFields.avatarColorIndex: profile.avatarColorIndex,
        FirebaseFields.updatedAt: FieldValue.serverTimestamp(),
        FirebaseFields.lastSeenAt: FieldValue.serverTimestamp(),
      };

      if (existing.exists) {
        await ref.update(presentation);
        return;
      }

      // The create rule requires the aggregates to start at zero, so a new
      // document is written whole rather than merged.
      await ref.set(<String, dynamic>{
        FirebaseFields.userId: userId,
        ...presentation,
        FirebaseFields.photoUrl: null,
        FirebaseFields.createdAt: FieldValue.serverTimestamp(),
        FirebaseFields.gamesPlayed: 0,
        FirebaseFields.gamesWon: 0,
        FirebaseFields.totalScore: 0,
      });
    } on Object catch (error, stack) {
      throw toAppException(error, stack);
    }
  }

  // -------------------------------------------------------------------------
  // Mappers
  // -------------------------------------------------------------------------

  Room _roomFrom(
    String id,
    Map<String, dynamic> data,
    List<Player> players,
  ) {
    return Room(
      id: id,
      code: asString(data[FirebaseFields.roomCode]),
      hostId: asString(data[FirebaseFields.ownerId]),
      players: players,
      settings: _settingsFrom(asMap(data[FirebaseFields.settings])),
      status: RoomStatus.fromName(asString(data[FirebaseFields.status])),
      createdAtMs: _millis(data[FirebaseFields.createdAt]),
      bannedIds: asStringList(data[FirebaseFields.bannedUserIds]),
    );
  }

  /// Builds a [Player], deriving the flags the UI needs from the room's game
  /// state so widgets never have to cross-reference two documents themselves.
  Player _playerFrom(Map<String, dynamic> data, Map<String, dynamic> roomData) {
    final Map<String, dynamic> game = asMap(roomData[FirebaseFields.game]);
    final String userId = asString(data[FirebaseFields.userId]);
    final List<String> correctOrder = asStringList(game['correctOrder']);
    final int order = correctOrder.indexOf(userId);

    return Player(
      id: userId,
      name: asString(data[FirebaseFields.displayName]),
      avatarId: asInt(data[FirebaseFields.avatarId]),
      avatarColorIndex: asInt(data[FirebaseFields.avatarColorIndex]),
      score: asInt(data[FirebaseFields.score]),
      roundScore: asInt(data['roundScore']),
      isHost: asBool(data['isHost']),
      isReady: asBool(data[FirebaseFields.isReady]),
      isDrawing: asString(game[FirebaseFields.currentDrawerId]) == userId,
      hasGuessed: asBool(data[FirebaseFields.hasGuessedCorrectly]),
      guessOrder: order >= 0 ? order + 1 : null,
      isMuted: asBool(data[FirebaseFields.isMuted]),
      connection: _connectionFrom(data),
    );
  }

  /// Turns the connection flag and the last heartbeat into a tri-state.
  ///
  /// The middle state matters: a player whose heartbeat is merely late is
  /// shown as reconnecting rather than gone, because the server will still
  /// hold their seat for a while yet (§36).
  PlayerConnection _connectionFrom(Map<String, dynamic> data) {
    if (!asBool(data[FirebaseFields.isConnected], true)) {
      return PlayerConnection.disconnected;
    }
    final int lastSeen = _millis(data[FirebaseFields.lastSeenAt]);
    if (lastSeen == 0) return PlayerConnection.connected;
    final int silentFor = DateTime.now().millisecondsSinceEpoch - lastSeen;
    return silentFor > 30000
        ? PlayerConnection.reconnecting
        : PlayerConnection.connected;
  }

  /// Maps the room's `game` map onto [GameState].
  ///
  /// `word` is deliberately never populated from Firestore: the answer is not
  /// in this document, and cannot be (§18). It reaches the drawer alone, as
  /// the return value of the `selectWord` callable.
  GameState _gameStateFrom(Map<String, dynamic> game) {
    return GameState(
      phase: GamePhase.fromName(asString(game[FirebaseFields.roundStatus])),
      currentRound: asInt(game[FirebaseFields.currentRound]),
      totalRounds: asInt(game[FirebaseFields.totalRounds]),
      turnIndex: asInt(game['turnIndex']),
      drawerId: asString(game[FirebaseFields.currentDrawerId]),
      maskedWord: asString(game[FirebaseFields.maskedWord]),
      wordLength: asInt(game['wordLength']),
      turnStartMs: _millis(game[FirebaseFields.roundStartedAt]),
      turnEndMs: _millis(game[FirebaseFields.roundEndsAt]),
      correctGuesserIds: asStringList(game['correctOrder']),
    );
  }

  RoomSettings _settingsFrom(Map<String, dynamic> data) {
    return RoomSettings(
      maxPlayers: asInt(data['maxPlayers'], 8),
      rounds: asInt(data['rounds'], 3),
      drawTimeSeconds: asInt(data['drawTimeSeconds'], 80),
      wordChoiceCount: asInt(data['wordsToChoose'], 3),
      hintCount: asInt(data['hintCount'], 2),
      wordSelectSeconds: asInt(data['wordSelectSeconds'], 15),
      wordMode: WordMode.fromName(asString(data['wordMode'])),
      language: AppLanguage.fromName(asString(data['language'])),
      categories: <WordCategory>{
        for (final String name in asStringList(data['categories']))
          WordCategory.fromName(name),
      },
      allowVoteKick: asBool(data['allowVoteKick'], true),
      isPrivate: asBool(data['isPrivate']),
    );
  }

  ChatMessage _messageFrom(Map<String, dynamic> data) {
    return ChatMessage(
      id: asString(data['messageId']),
      senderId: asString(data[FirebaseFields.userId]),
      senderName: asString(data[FirebaseFields.displayName]),
      text: asString(data[FirebaseFields.message]),
      type: ChatMessageType.fromName(asString(data[FirebaseFields.type])),
      timestampMs: _millis(data[FirebaseFields.createdAt]),
    );
  }

  /// Maps a stored round document onto [RoundResult].
  ///
  /// The awards list carries per-round deltas; the running totals come from
  /// the player documents, so only the deltas are read here.
  RoundResult _roundResultFrom(Map<String, dynamic> data) {
    final List<dynamic> awards = asList(data['awards']);
    final Map<String, int> deltas = <String, int>{};
    final List<String> order = <String>[];

    for (final dynamic raw in awards) {
      final Map<String, dynamic> award = asMap(raw);
      final String userId = asString(award['userId']);
      if (userId.isEmpty) continue;
      deltas[userId] = asInt(award['points']);
      if (asString(award['role']) == 'guesser') order.add(userId);
    }

    return RoundResult(
      round: asInt(data['roundNumber']),
      drawerId: asString(data['drawerId']),
      word: asString(data['word']),
      scoreDeltas: deltas,
      correctOrder: order,
    );
  }

  /// Milliseconds since epoch from a Firestore [Timestamp], or 0.
  ///
  /// A field written with `FieldValue.serverTimestamp()` reads back as null in
  /// the brief window before the server resolves it, so this never assumes a
  /// timestamp is present.
  static int _millis(Object? value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    return 0;
  }

  static Never _rethrowAsAppException(Object error, StackTrace stack) {
    throw toAppException(error, stack);
  }

  /// Joins two streams, emitting whenever either produces a value.
  ///
  /// Written by hand rather than pulling in rxdart: it is twenty lines, and
  /// the contract adds no dependency to a project that deliberately keeps them
  /// few. Nothing is emitted until both sources have produced at least once,
  /// so the UI never sees a room without its roster.
  static Stream<R> _combineLatest2<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A, B) combine,
  ) {
    late StreamController<R> controller;
    StreamSubscription<A>? subA;
    StreamSubscription<B>? subB;
    A? latestA;
    B? latestB;
    bool hasA = false;
    bool hasB = false;

    void emit() {
      if (hasA && hasB) {
        controller.add(combine(latestA as A, latestB as B));
      }
    }

    controller = StreamController<R>(
      onListen: () {
        subA = a.listen(
          (A value) {
            latestA = value;
            hasA = true;
            emit();
          },
          onError: controller.addError,
        );
        subB = b.listen(
          (B value) {
            latestB = value;
            hasB = true;
            emit();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
        subA = null;
        subB = null;
        if (!controller.isClosed) await controller.close();
      },
    );
    return controller.stream;
  }
}
