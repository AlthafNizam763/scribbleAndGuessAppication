import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/auto_tournament.dart';
import 'package:scribble_guess/models/player.dart';

/// Parsing the automatic tournaments.
///
/// ## What is worth pinning here
///
/// Not the field-by-field copying — that is the same `asString`/`asInt`
/// plumbing as every other model, and a test of it tests the plumbing. What
/// matters is the handful of places where a parsing mistake would be *silently
/// wrong on screen*:
///
/// - A bot that parses as a person. The badge is drawn from `isBot`, so a
///   missing or mistyped flag puts an AI in the roster as a player.
/// - `isSelf` on a bot row. Both sides of that comparison are nullable on the
///   wire, and a null-to-null match would bold every robot.
/// - A status the server introduces later. It has to fall back to the *closed*
///   end of the lifecycle, not the open one.
void main() {
  group('a participant', () {
    test('parses an AI entrant as a bot, with its difficulty', () {
      final TournamentParticipant bot =
          TournamentParticipant.fromJson(const <String, dynamic>{
        'registrationId': 'r1',
        'playerId': 'p1',
        'displayName': 'Doodler',
        'playerType': 'AI_BOT',
        'isBot': true,
        'botDifficulty': 'HARD',
        'status': 'ACTIVE',
        'isSelf': false,
      });

      expect(bot.isBot, isTrue);
      expect(bot.playerType, TournamentPlayerType.aiBot);
      expect(bot.botDifficulty, BotDifficulty.hard);
      expect(bot.botDifficulty!.label, 'Hard');
    });

    test('parses a person as a person, with no difficulty', () {
      final TournamentParticipant human =
          TournamentParticipant.fromJson(const <String, dynamic>{
        'registrationId': 'r2',
        'playerId': 'u2',
        'displayName': 'Ana',
        'playerType': 'HUMAN',
        'isBot': false,
        'botDifficulty': null,
        'isSelf': true,
      });

      expect(human.isBot, isFalse);
      expect(human.botDifficulty, isNull);
      expect(human.isSelf, isTrue);
    });

    /// The failure this guards against is cosmetic and embarrassing: every AI
    /// row bolded as "you" for a signed-out reader.
    test('never marks a bot as the reader', () {
      final TournamentParticipant bot =
          TournamentParticipant.fromJson(const <String, dynamic>{
        'registrationId': 'r3',
        'displayName': 'Pixeler',
        'playerType': 'AI_BOT',
        'isBot': true,
        'isSelf': false,
      });

      expect(bot.isSelf, isFalse);
    });

    test('treats an unknown player type as a person', () {
      final TournamentParticipant row =
          TournamentParticipant.fromJson(const <String, dynamic>{
        'displayName': 'Someone',
        'playerType': 'SOMETHING_NEW',
        'isBot': false,
      });

      // A person shown as a robot is an insult; a robot shown as a person is
      // a cosmetic mistake the `isBot` flag still catches. The fallback goes
      // the way that cannot offend anybody.
      expect(row.playerType, TournamentPlayerType.human);
    });
  });

  group('a tournament', () {
    Map<String, dynamic> payload({String status = 'REGISTRATION'}) =>
        <String, dynamic>{
          'id': 't1',
          'slotNumber': 2,
          'tournamentNumber': 7,
          'name': 'Daily Scribble Cup #7',
          'status': status,
          'minPlayers': 4,
          'maxPlayers': 16,
          'humanPlayerCount': 1,
          'botPlayerCount': 3,
          'totalPlayers': 4,
          'registrationCloseAtMs': 1700000000000,
          'checkInCloseAtMs': 1700000600000,
          'botDifficulty': 'NORMAL',
          'viewer': <String, dynamic>{
            'isRegistered': true,
            'isCheckedIn': false,
            'canRegister': false,
            'canCheckIn': true,
            'canWithdraw': false,
            'blockedReason': null,
          },
        };

    test('keeps the human and AI counts apart', () {
      final AutoTournament row = AutoTournament.fromJson(payload());

      expect(row.humanPlayerCount, 1);
      expect(row.botPlayerCount, 3);
      expect(row.totalPlayers, 4);
    });

    test('counts down to the deadline its status is waiting on', () {
      expect(
        AutoTournament.fromJson(payload()).activeDeadlineMs,
        1700000000000,
      );
      expect(
        AutoTournament.fromJson(payload(status: 'CHECK_IN')).activeDeadlineMs,
        1700000600000,
      );
      // A running tournament is not waiting for anything the player can act on.
      expect(
        AutoTournament.fromJson(payload(status: 'RUNNING')).activeDeadlineMs,
        isNull,
      );
    });

    test('carries the viewer state the buttons are drawn from', () {
      final AutoTournament row = AutoTournament.fromJson(payload());

      expect(row.viewer.isRegistered, isTrue);
      expect(row.viewer.canCheckIn, isTrue);
      expect(row.viewer.canRegister, isFalse);
      expect(row.viewer.activeMatch, isNull);
    });

    test('falls back to the closed end of the lifecycle on an unknown status',
        () {
      final AutoTournament row =
          AutoTournament.fromJson(payload(status: 'SOMETHING_NEW'));

      // `upcoming`, not `registration`: an unrecognised status must never
      // render a join button on a tournament that may have closed.
      expect(row.status, AutoTournamentStatus.upcoming);
      expect(row.status.isLive, isTrue);
    });

    test('knows which statuses still hold a slot', () {
      expect(AutoTournamentStatus.registration.isLive, isTrue);
      expect(AutoTournamentStatus.running.isLive, isTrue);
      expect(AutoTournamentStatus.completed.isLive, isFalse);
      expect(AutoTournamentStatus.cancelled.isLive, isFalse);
    });
  });

  group('a slot', () {
    test('parses an empty slot as present with nothing in it', () {
      final TournamentSlot slot =
          TournamentSlot.fromJson(const <String, dynamic>{'slotNumber': 3});

      expect(slot.slotNumber, 3);
      expect(slot.tournament, isNull);
    });
  });

  group('a bracket', () {
    test('keeps a room code only where the server sent one', () {
      final TournamentBracket bracket =
          TournamentBracket.fromJson(const <String, dynamic>{
        'tournamentId': 't1',
        'totalRounds': 2,
        'currentRound': 1,
        'rounds': <dynamic>[
          <String, dynamic>{
            'roundNumber': 1,
            'name': 'Semi-final',
            'matches': <dynamic>[
              <String, dynamic>{
                'matchId': 'm1',
                'roundNumber': 1,
                'matchNumber': 1,
                'status': 'READY',
                'roomCode': 'AB12C',
              },
              <String, dynamic>{
                'matchId': 'm2',
                'roundNumber': 1,
                'matchNumber': 2,
                'status': 'READY',
                'roomCode': null,
              },
            ],
          },
        ],
      });

      final List<TournamentMatch> matches = bracket.rounds.single.matches;

      expect(matches.first.roomCode, 'AB12C');
      // The other pairing is somebody else's; its code never left the server.
      expect(matches.last.roomCode, isNull);
    });

    test('recognises a bye and a walkover', () {
      TournamentMatch of(String outcome) =>
          TournamentMatch.fromJson(<String, dynamic>{
            'matchId': 'm',
            'status': 'COMPLETED',
            'outcome': outcome,
          });

      expect(of('BYE').isBye, isTrue);
      expect(of('WALKOVER').isWalkover, isTrue);
      expect(of('PLAYED').isBye, isFalse);
      expect(of('PLAYED').isWalkover, isFalse);
    });

    test('leaves an undecided seat null rather than inventing one', () {
      final TournamentMatch match =
          TournamentMatch.fromJson(const <String, dynamic>{
        'matchId': 'm3',
        'status': 'PENDING',
        'playerA': null,
        'playerB': null,
      });

      expect(match.playerA, isNull);
      expect(match.playerB, isNull);
    });
  });

  group('a room seat', () {
    /// The in-game player list draws its badge from the same flag, so a seat
    /// that lost it in transit would show an AI opponent as a person for the
    /// whole match.
    test('carries the bot flag through a room snapshot', () {
      final Player bot = Player.fromJson(const <String, dynamic>{
        'id': 'b1',
        'name': 'Sketcher',
        'isBot': true,
        'botDifficulty': 'NORMAL',
      });

      expect(bot.isBot, isTrue);
      expect(bot.botDifficulty, 'NORMAL');
      expect(bot.toJson()['isBot'], isTrue);
    });

    test('defaults to a person when the server says nothing', () {
      final Player human = Player.fromJson(const <String, dynamic>{
        'id': 'u1',
        'name': 'Ana',
      });

      expect(human.isBot, isFalse);
      expect(human.botDifficulty, isNull);
    });
  });
}
