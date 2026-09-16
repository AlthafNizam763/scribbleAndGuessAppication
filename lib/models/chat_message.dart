import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// One row of the chat panel: a guess, a chat line or a system announcement.
class ChatMessage extends Equatable {
  /// Creates a chat message.
  const ChatMessage({
    this.id = '',
    this.senderId = '',
    this.senderName = '',
    this.text = '',
    this.type = ChatMessageType.chat,
    this.timestampMs = 0,
  });

  /// Builds a message from a decoded JSON map, tolerating malformed values.
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: asString(json['id']),
        senderId: asString(json['senderId']),
        senderName: asString(json['senderName']),
        text: asString(json['text']),
        type: ChatMessageType.fromName(asString(json['type'])),
        timestampMs: asInt(json['timestampMs']),
      );

  /// Identifier of the message, unique inside a room.
  final String id;

  /// Identifier of the sender, empty for system messages.
  final String senderId;

  /// Display name of the sender, empty for system messages.
  final String senderName;

  /// Body of the message.
  final String text;

  /// How the row should be rendered.
  final ChatMessageType type;

  /// Send time in milliseconds since epoch, on the server clock.
  final int timestampMs;

  /// Serializes this message to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'type': type.name,
        'timestampMs': timestampMs,
      };

  /// Returns a copy with the given fields replaced.
  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? text,
    ChatMessageType? type,
    int? timestampMs,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        senderId: senderId ?? this.senderId,
        senderName: senderName ?? this.senderName,
        text: text ?? this.text,
        type: type ?? this.type,
        timestampMs: timestampMs ?? this.timestampMs,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        senderId,
        senderName,
        text,
        type,
        timestampMs,
      ];

  @override
  bool get stringify => true;
}
