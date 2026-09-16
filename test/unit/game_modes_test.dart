import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/game_mode.dart';
import 'package:scribble_guess/models/room_settings.dart';

/// Game modes and teams, as the client parses them.
///
/// ## Why the wire strings are pinned
///
/// `GameMode.parse` falls back to [GameMode.classic] rather than throwing,
/// which is what lets the server ship a tenth mode before every installed app
/// knows about it — but it also means a name that drifts from the backend's
/// `GAME_MODE` fails *silently*. A Blind room would render as Classic, the
/// drawer would be shown a canvas the server says they cannot see, and nothing
/// would report it.
void main() {
  group('GameMode wire format', () {
    test('parses every value the backend sends', () {
      const Map<String, GameMode> wire = <String, GameMode>{
        'classic': GameMode.classic,
        'speed': GameMode.speed,
        'team': GameMode.team,
        'duo': GameMode.duo,
        'challenge': GameMode.challenge,
        'no_hint': GameMode.noHint,
        'one_color': GameMode.oneColor,
        'blind': GameMode.blind,
        'relay': GameMode.relay,
      };

      wire.forEach((String name, GameMode expected) {
        expect(GameMode.parse(name), expected, reason: name);
      });
    });

    test('round-trips through its wire name', () {
      for (final GameMode mode in GameMode.values) {
        expect(GameMode.parse(mode.wire), mode);
      }
    });

    test('falls back to Classic rather than throwing', () {
      expect(GameMode.parse(null), GameMode.classic);
      expect(GameMode.parse('from_the_future'), GameMode.classic);
      expect(GameMode.parse(42), GameMode.classic);
    });

    test('gives every mode a label and a description', () {
      for (final GameMode mode in GameMode.values) {
        expect(mode.label, isNotEmpty, reason: mode.name);
        expect(mode.description, isNotEmpty, reason: mode.name);
      }
    });
  });

  group('mode traits', () {
    /// Each trait belongs to exactly one mode, matching the server's table.
    test('assigns each behaviour to exactly one mode', () {
      expect(GameMode.values.where((GameMode m) => m.blindsDrawer), hasLength(1));
      expect(GameMode.values.where((GameMode m) => m.locksColor), hasLength(1));
      expect(GameMode.values.where((GameMode m) => m.hasTeams), hasLength(1));
      expect(GameMode.values.where((GameMode m) => m.keepsBoard), hasLength(1));
    });

    test('names the right mode for each behaviour', () {
      expect(GameMode.blind.blindsDrawer, isTrue);
      expect(GameMode.oneColor.locksColor, isTrue);
      expect(GameMode.team.hasTeams, isTrue);
      expect(GameMode.relay.keepsBoard, isTrue);
      expect(GameMode.classic.blindsDrawer, isFalse);
    });

    /// Team and Duo are unranked on the server; the client must agree, or it
    /// would promise a leaderboard place the match will never produce.
    test('keeps Team and Duo off the leaderboard', () {
      expect(GameMode.team.ranked, isFalse);
      expect(GameMode.duo.ranked, isFalse);
      expect(GameMode.classic.ranked, isTrue);
      expect(GameMode.blind.ranked, isTrue);
    });
  });

  group('Team wire format', () {
    test('parses the sides the backend sends', () {
      expect(Team.parse('none'), Team.none);
      expect(Team.parse('red'), Team.red);
      expect(Team.parse('blue'), Team.blue);
    });

    test('falls back to none', () {
      expect(Team.parse(null), Team.none);
      expect(Team.parse('green'), Team.none);
    });

    test('knows which sides are real', () {
      expect(Team.none.isAssigned, isFalse);
      expect(Team.red.isAssigned, isTrue);
      expect(Team.blue.isAssigned, isTrue);
    });
  });

  group('room settings', () {
    test('defaults to Classic with spectators allowed', () {
      const RoomSettings settings = RoomSettings();

      expect(settings.gameMode, GameMode.classic);
      expect(settings.allowSpectators, isTrue);
      expect(settings.friendsOnly, isFalse);
      expect(settings.wordDifficulty, isNull);
    });

    test('parses the new fields from the wire', () {
      final RoomSettings settings = RoomSettings.fromJson(const <String, dynamic>{
        'gameMode': 'blind',
        'allowSpectators': false,
        'friendsOnly': true,
        'wordDifficulty': 'hard',
      });

      expect(settings.gameMode, GameMode.blind);
      expect(settings.allowSpectators, isFalse);
      expect(settings.friendsOnly, isTrue);
      expect(settings.wordDifficulty, 'hard');
    });

    /// An older server that sends none of these must not read as a Classic
    /// room with spectating switched off.
    test('falls back sensibly when the server omits them', () {
      final RoomSettings settings =
          RoomSettings.fromJson(const <String, dynamic>{});

      expect(settings.gameMode, GameMode.classic);
      expect(settings.allowSpectators, isTrue);
    });

    test('round-trips through its own wire format', () {
      const RoomSettings settings = RoomSettings(
        gameMode: GameMode.relay,
        allowSpectators: false,
        friendsOnly: true,
        wordDifficulty: 'easy',
      );

      final RoomSettings parsed = RoomSettings.fromJson(settings.toJson());

      expect(parsed.gameMode, GameMode.relay);
      expect(parsed.allowSpectators, isFalse);
      expect(parsed.friendsOnly, isTrue);
      expect(parsed.wordDifficulty, 'easy');
    });

    test('copies the mode independently of everything else', () {
      const RoomSettings settings = RoomSettings();
      final RoomSettings duo = settings.copyWith(gameMode: GameMode.duo);

      expect(duo.gameMode, GameMode.duo);
      expect(duo.allowSpectators, settings.allowSpectators);
      expect(duo.maxPlayers, settings.maxPlayers);
    });
  });
}
