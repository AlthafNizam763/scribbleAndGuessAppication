import 'package:scribble_guess/core/constants/firebase_constants.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/services/firestore_service.dart';
import 'package:scribble_guess/services/functions_client.dart';

/// Chat (§31-32).
///
/// Reads come straight from Firestore, which is what makes the feed live;
/// writes go through a callable, which is what makes them rate-limited,
/// mute-aware, and unable to leak the answer.
class ChatService {
  ChatService(this._client, this._firestore);

  final FunctionsClient _client;
  final FirestoreService _firestore;

  /// The room's message feed, oldest first.
  Stream<List<ChatMessage>> watchMessages(String roomId) {
    return _firestore.watchMessages(roomId);
  }

  /// Posts a chat line.
  ///
  /// Use `GameService.submitGuess` instead while a round is live and the
  /// player is eligible to guess: the server will refuse a chat message that
  /// happens to be the answer, but a guess routed here would score nothing.
  Future<void> sendMessage(String roomId, String message) {
    return _client.call(
      FirebaseCallables.sendMessage,
      <String, dynamic>{'roomId': roomId, 'message': message},
    );
  }
}
