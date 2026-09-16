import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/models/room_settings.dart';

/// The room's communication switches, and the chat-extras protocol.
///
/// ## Why these are worth pinning
///
/// `voiceEnabled` and `chatEnabled` are enforced on the server — turning voice
/// off hangs up calls that are already open. A client that parsed either field
/// wrongly would show a microphone button for a room that will refuse every
/// frame it sends, and the failure would look like a bug in voice rather than
/// a disagreement about a setting.
///
/// The event names are pinned for the same reason every other wire string in
/// this app is: a rename on one side does not fail to compile, it just stops
/// arriving.
void main() {
  group('room communication settings', () {
    test('defaults both switches on', () {
      const RoomSettings settings = RoomSettings();

      expect(settings.voiceEnabled, isTrue);
      expect(settings.chatEnabled, isTrue);
    });

    test('parses both from the wire', () {
      final RoomSettings settings = RoomSettings.fromJson(const <String, dynamic>{
        'voiceEnabled': false,
        'chatEnabled': false,
      });

      expect(settings.voiceEnabled, isFalse);
      expect(settings.chatEnabled, isFalse);
    });

    /// An older server that does not send these must not read as a room with
    /// voice and chat switched off — which would silently disable both.
    test('falls back to on when the server omits them', () {
      final RoomSettings settings =
          RoomSettings.fromJson(const <String, dynamic>{});

      expect(settings.voiceEnabled, isTrue);
      expect(settings.chatEnabled, isTrue);
    });

    test('round-trips through its own wire format', () {
      const RoomSettings settings =
          RoomSettings(voiceEnabled: false, chatEnabled: true);

      final RoomSettings parsed = RoomSettings.fromJson(settings.toJson());

      expect(parsed.voiceEnabled, isFalse);
      expect(parsed.chatEnabled, isTrue);
    });

    test('copies each switch independently', () {
      const RoomSettings settings = RoomSettings();

      expect(settings.copyWith(voiceEnabled: false).chatEnabled, isTrue);
      expect(settings.copyWith(chatEnabled: false).voiceEnabled, isTrue);
    });
  });

  group('chat extras protocol', () {
    test('names every event the server sends', () {
      expect(SocketEvents.clientChatTyping, 'c:chat:typing');
      expect(SocketEvents.clientChatReact, 'c:chat:react');
      expect(SocketEvents.clientChatDelete, 'c:chat:delete');
      expect(SocketEvents.clientChatReport, 'c:chat:report');
      expect(SocketEvents.serverChatTyping, 's:chat:typing');
      expect(SocketEvents.serverChatReaction, 's:chat:reaction');
      expect(SocketEvents.serverChatDeleted, 's:chat:deleted');
    });

    test('groups the server-sent extras for a refresh listener', () {
      expect(
        SocketEvents.chatExtraEvents,
        containsAll(<String>[
          SocketEvents.serverChatTyping,
          SocketEvents.serverChatReaction,
          SocketEvents.serverChatDeleted,
        ]),
      );
    });

    test('includes them in the full server event list', () {
      for (final String event in SocketEvents.chatExtraEvents) {
        expect(SocketEvents.serverEvents, contains(event));
      }
    });
  });

  group('quick messages and reactions', () {
    /// The set must match the server's `CHAT_REACTIONS` exactly: an emoji this
    /// app offers that the server rejects is a button that always fails.
    test('offers exactly the emoji the server accepts', () {
      expect(
        AppStrings.chatReactions,
        <String>['👍', '😂', '🔥', '😮', '❤️', '👏'],
      );
    });

    test('offers quick messages that are short and non-empty', () {
      expect(AppStrings.chatQuickMessages, isNotEmpty);

      for (final String message in AppStrings.chatQuickMessages) {
        expect(message.trim(), isNotEmpty);
        // Comfortably inside the server's 120-character chat limit, so a
        // one-tap message can never be the thing that trips validation.
        expect(message.length, lessThan(40));
      }
    });
  });
}
