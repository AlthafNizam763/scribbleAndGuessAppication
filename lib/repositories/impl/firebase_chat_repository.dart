import 'dart:async';

import 'package:scribble_guess/core/errors/app_exception.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/repositories/chat_repository.dart';
import 'package:scribble_guess/repositories/game_repository.dart';
import 'package:scribble_guess/repositories/room_repository.dart';
import 'package:scribble_guess/services/chat_service.dart';
import 'package:scribble_guess/services/game_service.dart';

/// [ChatRepository] backed by Firestore and callable Cloud Functions.
///
/// The one piece of judgement in this class is *where a typed line goes*.
/// While a round is live and the sender is still eligible to guess, the text is
/// a guess and must go to `submitGuess`, which scores it. Otherwise — before
/// the round, after guessing correctly, or when the sender is the drawer — it
/// is chat.
///
/// Getting that wrong is not cosmetic: a guess routed to chat would be
/// published verbatim to the whole room, handing everyone the answer. So the
/// decision is made from server-pushed state only, and the server independently
/// refuses to publish a chat line that matches the live word (§32).
class FirebaseChatRepository implements ChatRepository {
  FirebaseChatRepository({
    required ChatService chat,
    required GameService game,
    required RoomRepository rooms,
    required GameRepository games,
    required String userId,
  })  : _chat = chat,
        _game = game,
        _userId = userId {
    _roomSubscription = rooms.roomStream.listen(_onRoom);
    _gameSubscription = games.gameStream.listen((GameState state) {
      _phase = state;
    });
  }

  final ChatService _chat;
  final GameService _game;
  final String _userId;

  final StreamController<ChatMessage> _messages =
      StreamController<ChatMessage>.broadcast();

  StreamSubscription<Room>? _roomSubscription;
  StreamSubscription<GameState>? _gameSubscription;
  StreamSubscription<List<ChatMessage>>? _feedSubscription;

  String? _roomId;
  GameState _phase = GameState.initial;
  final Set<String> _seen = <String>{};

  @override
  Stream<ChatMessage> get messages => _messages.stream;

  @override
  Future<Result<void>> send(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const Err<void>(
        Failure(AppErrorCode.validation, 'Type something first.'),
      );
    }
    final String? roomId = _roomId;
    if (roomId == null) {
      return const Err<void>(
        Failure(AppErrorCode.invalidAction, 'You are not in a room.'),
      );
    }

    try {
      if (_isGuessing) {
        await _game.submitGuess(roomId, trimmed);
      } else {
        await _chat.sendMessage(roomId, trimmed);
      }
      return const Ok<void>(null);
    } on AppException catch (error) {
      return Err<void>(error.failure);
    } on Object catch (error, stack) {
      return Err<void>(toAppException(error, stack).failure);
    }
  }

  /// Whether this player's next line should be scored as a guess.
  bool get _isGuessing {
    if (_phase.phase != GamePhase.drawing) return false;
    if (_phase.drawerId == _userId) return false;
    // Somebody who already got it chats normally; letting them guess again
    // would be pointless, and the server refuses it anyway.
    return !_phase.correctGuesserIds.contains(_userId);
  }

  /// Re-targets the message feed when the joined room changes.
  ///
  /// Firestore hands back the whole recent window on every change, so the
  /// already-delivered ids are tracked and only genuinely new messages are
  /// pushed — otherwise the chat panel would replay itself on every keystroke
  /// anyone in the room made.
  void _onRoom(Room room) {
    if (room.id == _roomId) return;
    _roomId = room.id;
    _seen.clear();

    unawaited(_feedSubscription?.cancel());
    _feedSubscription = _chat.watchMessages(room.id).listen(
      (List<ChatMessage> batch) {
        for (final ChatMessage message in batch) {
          final String key = message.id.isNotEmpty
              ? message.id
              : '${message.senderId}:${message.timestampMs}:${message.text}';
          if (!_seen.add(key)) continue;
          if (!_messages.isClosed) _messages.add(message);
        }

        // The window is capped, so old ids can be forgotten once they can no
        // longer reappear in it.
        if (_seen.length > 600) {
          _seen.clear();
          for (final ChatMessage message in batch) {
            _seen.add(message.id);
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        AppLogger.w('chat stream failed', error, stack);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_roomSubscription?.cancel());
    unawaited(_gameSubscription?.cancel());
    unawaited(_feedSubscription?.cancel());
    unawaited(_messages.close());
  }
}
