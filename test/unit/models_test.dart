import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_settings.dart';

/// Model and wire-format tests (§65).
///
/// The enum group matters more than it looks. `GamePhase` and `RoomStatus`
/// travel as the backend's snake_case names while keeping idiomatic Dart
/// identifiers, so a mistake here does not fail loudly — it silently parses
/// every phase as "lobby" and the game appears to freeze in the menu. These
/// tests pin both directions.
void main() {
  group('GamePhase wire format', () {
    test('parses the values the backend actually writes', () {
      expect(GamePhase.fromName('waiting'), GamePhase.lobby);
      expect(GamePhase.fromName('starting'), GamePhase.starting);
      expect(GamePhase.fromName('word_selection'), GamePhase.wordSelection);
      expect(GamePhase.fromName('drawing'), GamePhase.drawing);
      expect(GamePhase.fromName('round_result'), GamePhase.roundEnd);
      expect(GamePhase.fromName('final_result'), GamePhase.gameEnd);
    });

    test('round-trips through its wire name', () {
      for (final GamePhase phase in GamePhase.values) {
        expect(GamePhase.fromName(phase.wire), phase, reason: phase.name);
      }
    });

    test('still accepts the Dart identifier, for older payloads', () {
      expect(GamePhase.fromName('wordSelection'), GamePhase.wordSelection);
    });

    test('falls back rather than throwing on nonsense', () {
      expect(GamePhase.fromName('nonsense'), GamePhase.lobby);
      expect(GamePhase.fromName(null), GamePhase.lobby);
    });
  });

  group('RoomStatus wire format', () {
    test('parses the backend vocabulary', () {
      expect(RoomStatus.fromName('waiting'), RoomStatus.waiting);
      expect(RoomStatus.fromName('playing'), RoomStatus.inGame);
      expect(RoomStatus.fromName('round_result'), RoomStatus.roundResult);
      expect(RoomStatus.fromName('closed'), RoomStatus.closed);
    });

    test('round-trips through its wire name', () {
      for (final RoomStatus status in RoomStatus.values) {
        expect(RoomStatus.fromName(status.wire), status, reason: status.name);
      }
    });

    test('knows which states mean a game is under way', () {
      expect(RoomStatus.inGame.isPlaying, isTrue);
      expect(RoomStatus.roundResult.isPlaying, isTrue);
      expect(RoomStatus.waiting.isPlaying, isFalse);
      expect(RoomStatus.finished.isPlaying, isFalse);
    });

    test('knows which states can still be joined', () {
      expect(RoomStatus.waiting.isJoinable, isTrue);
      expect(RoomStatus.closed.isJoinable, isFalse);
      expect(RoomStatus.finished.isJoinable, isFalse);
    });
  });

  group('Other enums', () {
    test('word modes match the spec vocabulary', () {
      expect(WordMode.fromName('normal'), WordMode.normal);
      expect(WordMode.fromName('hidden'), WordMode.hidden);
      expect(WordMode.fromName('combination'), WordMode.combination);
      expect(WordMode.fromName('garbage'), WordMode.normal);
    });

    test('every supported language parses', () {
      for (final AppLanguage language in AppLanguage.values) {
        expect(AppLanguage.fromName(language.name), language);
        expect(language.label, isNotEmpty);
      }
    });

    test('flags the non-Latin banks', () {
      expect(AppLanguage.ml.isNonLatinScript, isTrue);
      expect(AppLanguage.ja.isNonLatinScript, isTrue);
      expect(AppLanguage.en.isNonLatinScript, isFalse);
    });

    test('every word category has a label', () {
      for (final WordCategory category in WordCategory.values) {
        expect(category.label, isNotEmpty);
      }
    });
  });

  group('Room', () {
    const Room room = Room(
      id: 'room-1',
      code: 'A7K9P',
      hostId: 'alice',
      players: <Player>[
        Player(id: 'alice', name: 'Alice', isHost: true, score: 10),
        Player(id: 'bob', name: 'Bob', isReady: true),
      ],
      settings: RoomSettings(maxPlayers: 2),
    );

    test('finds a seated player by id', () {
      expect(room.playerById('bob')?.name, 'Bob');
      expect(room.playerById('nobody'), isNull);
    });

    test('knows its host', () {
      expect(room.isHost('alice'), isTrue);
      expect(room.isHost('bob'), isFalse);
      // An empty id must never be mistaken for the host.
      expect(room.isHost(''), isFalse);
    });

    test('knows when it is full', () {
      expect(room.isFull, isTrue);
    });

    test('counts ready players', () {
      expect(room.readyCount, 1);
    });

    test('round-trips through JSON, keeping the document id', () {
      final Room parsed = Room.fromJson(room.toJson());
      expect(parsed.id, 'room-1');
      expect(parsed.code, 'A7K9P');
      expect(parsed.status, room.status);
      expect(parsed.players.length, 2);
    });
  });

  group('json_utils', () {
    test('coerces without ever throwing', () {
      expect(asInt('12'), 12);
      expect(asInt(3.7), 3);
      expect(asInt(null), 0);
      expect(asInt(<String>['nope']), 0);
      expect(asDouble('1.5'), 1.5);
      expect(asBool('yes'), isTrue);
      expect(asString(42), '42');
      expect(asList(null), isEmpty);
      expect(asMap('not a map'), isEmpty);
    });

    test('resolves enums by wire name', () {
      expect(
        asWireEnum(GamePhase.values, 'round_result', (GamePhase e) => e.wire),
        GamePhase.roundEnd,
      );
      expect(
        asWireEnum(GamePhase.values, 'nope', (GamePhase e) => e.wire),
        isNull,
      );
    });
  });
}
