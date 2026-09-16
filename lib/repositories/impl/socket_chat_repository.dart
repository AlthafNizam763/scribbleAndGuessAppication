import 'dart:async';

import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/validators.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/repositories/chat_repository.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// The gateway's inbound record, aliased for readability.
typedef _Inbound = ({String event, Map<String, dynamic> data});

/// [ChatRepository] backed by a [RealtimeGateway].
///
/// Every `s:chat:message` push is decoded into a [ChatMessage] and kept in a
/// rolling history capped at `AppConstants.chatHistoryLimit`, which is
/// replayed to late listeners so a chat panel opened mid-round is not blank.
///
/// Guesses are never judged here: [send] transmits the raw text and the server
/// decides whether the echo comes back as chat, a guess, a close guess or a
/// correct guess. Nothing is appended locally, so a message the server
/// suppresses stays invisible on the sender's device too.
///
/// A malformed payload is logged and dropped; it never breaks the gateway
/// subscription and never reaches the UI.
class SocketChatRepository implements ChatRepository {
  /// Starts listening to [gateway] for chat traffic.
  SocketChatRepository(RealtimeGateway gateway) : _gateway = gateway {
    _inboundSubscription = _gateway.inbound.listen(
      _onInbound,
      onError: _onStreamError,
    );
  }

  final RealtimeGateway _gateway;

  final StreamController<ChatMessage> _messageController =
      StreamController<ChatMessage>.broadcast();

  final List<ChatMessage> _history = <ChatMessage>[];

  StreamSubscription<_Inbound>? _inboundSubscription;

  bool _disposed = false;

  @override
  Stream<ChatMessage> get messages async* {
    for (final ChatMessage message in List<ChatMessage>.of(_history)) {
      yield message;
    }
    yield* _messageController.stream;
  }

  /// The retained messages, oldest first, capped at
  /// `AppConstants.chatHistoryLimit`.
  List<ChatMessage> get history => List<ChatMessage>.unmodifiable(_history);

  @override
  Future<Result<void>> send(String text) async {
    final String trimmed = text.trim();
    final String? problem = Validators.chatMessage(trimmed);
    if (problem != null) {
      return Err<void>(Failure.validation(problem));
    }
    final Result<Map<String, dynamic>> ack = await _gateway.request(
      SocketEvents.clientChatSend,
      <String, dynamic>{'text': trimmed},
    );
    return ack.fold<Result<void>>(
      (Map<String, dynamic> _) => const Ok<void>(null),
      Err<void>.new,
    );
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_inboundSubscription?.cancel());
    _inboundSubscription = null;
    _history.clear();
    unawaited(_messageController.close());
  }

  // ---------------------------------------------------------------------------
  // Inbound
  // ---------------------------------------------------------------------------

  void _onInbound(_Inbound message) {
    if (message.event != SocketEvents.serverChatMessage) {
      return;
    }
    try {
      final Object? raw = message.data['message'];
      final ChatMessage parsed =
          ChatMessage.fromJson(raw is Map ? asMap(raw) : message.data);
      _remember(parsed);
    } catch (error, stackTrace) {
      AppLogger.w(
        'SocketChatRepository: dropped malformed chat message',
        error,
        stackTrace,
      );
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    AppLogger.w(
      'SocketChatRepository: gateway stream error',
      error,
      stackTrace,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _remember(ChatMessage message) {
    if (_disposed) {
      return;
    }
    _history.add(message);
    while (_history.length > AppConstants.chatHistoryLimit) {
      _history.removeAt(0);
    }
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }
  }
}
