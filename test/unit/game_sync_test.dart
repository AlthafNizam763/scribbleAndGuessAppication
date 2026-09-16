import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/round_result.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/repositories/impl/socket_game_repository.dart';

import '../support/fake_gateway.dart';

/// Word selection and round timing, as the client sees them.
///
/// Every case here is about one thing: the server pushes state at a phase
/// boundary, which is exactly when the app is busy changing screens. A screen
/// built a moment *after* a push has to end up with the same state as one that
/// was already listening, or the drawer gets no word to choose and the results
/// screen has no word to show.

/// The per-viewer `game` payload the server sends, as the drawer sees it.
Map<String, dynamic> gameJson({
  required String phase,
  String? word,
  String maskedWord = '',
  int currentRound = 1,
  int turnIndex = 0,
  String? drawerId = 'a',
  List<Map<String, dynamic>> wordChoices = const <Map<String, dynamic>>[],
  int turnStartMs = 0,
  int turnEndMs = 0,
}) =>
    <String, dynamic>{
      'roomCode': 'A7K9P',
      'phase': phase,
      'currentRound': currentRound,
      'totalRounds': 3,
      'turnIndex': turnIndex,
      'drawerId': drawerId,
      'word': word,
      'maskedWord': maskedWord,
      'wordLength': word?.length ?? 0,
      'hintIndices': <int>[],
      'turnStartMs': turnStartMs,
      'turnEndMs': turnEndMs,
      'correctGuesserIds': <String>[],
      'roundScores': <String, int>{},
      'wordChoices': wordChoices,
    };

Map<String, dynamic> choice(String text) => <String, dynamic>{
      'text': text,
      'category': 'animals',
      'difficulty': 'easy',
    };

void main() {
  late FakeGateway gateway;
  late SocketGameRepository repository;

  setUp(() {
    gateway = FakeGateway();
    repository = SocketGameRepository(gateway);
  });

  tearDown(() {
    repository.dispose();
    gateway.dispose();
  });

  group('word selection', () {
    test('the drawer choices survive until a listener arrives', () async {
      // The choices go out as the turn opens, while this device may still be
      // showing the previous round's scoreboard. Nothing is listening yet.
      gateway.push(SocketEvents.serverGameWordChoices, <String, dynamic>{
        'choices': <Map<String, dynamic>>[choice('cat'), choice('house')],
      });
      await pumpEventQueue();

      // The picker is opened from here, so this is what has to hold the words.
      final GameState state = await repository.gameStream.first;
      expect(state.wordChoices.map((WordItem w) => w.text), <String>['cat', 'house']);
    });

    test('the authoritative state carries the choices for the drawer', () async {
      gateway.push(SocketEvents.serverGameState, <String, dynamic>{
        'game': gameJson(
          phase: 'word_selection',
          wordChoices: <Map<String, dynamic>>[choice('cat')],
        ),
      });
      await pumpEventQueue();

      final GameState state = await repository.gameStream.first;
      expect(state.phase, GamePhase.wordSelection);
      expect(state.wordChoices, hasLength(1));
    });

    test('a reconnect mid-selection gets the choices back', () async {
      // The server does not re-send `s:game:wordChoices` on reconnect; it
      // re-sends the game state. Driving the picker from the state is what
      // makes the drawer's sheet come back with them.
      gateway.push(SocketEvents.serverGameState, <String, dynamic>{
        'game': gameJson(
          phase: 'word_selection',
          wordChoices: <Map<String, dynamic>>[choice('cat'), choice('house')],
        ),
      });
      await pumpEventQueue();

      final GameState afterReconnect = await repository.gameStream.first;
      expect(afterReconnect.phase, GamePhase.wordSelection);
      expect(afterReconnect.wordChoices, hasLength(2));
    });

    test('the choices are withdrawn once the drawing phase begins', () async {
      gateway.push(SocketEvents.serverGameState, <String, dynamic>{
        'game': gameJson(
          phase: 'word_selection',
          wordChoices: <Map<String, dynamic>>[choice('cat')],
        ),
      });
      await pumpEventQueue();

      gateway.push(SocketEvents.serverGameRoundStart, <String, dynamic>{
        'game': gameJson(phase: 'drawing', word: 'cat', turnEndMs: 1000),
      });
      await pumpEventQueue();

      final GameState state = await repository.gameStream.first;
      expect(state.phase, GamePhase.drawing);
      expect(state.wordChoices, isEmpty);
    });
  });

  group('the selected word', () {
    test('reaches the drawer with the round start, deadline and all', () async {
      gateway.push(SocketEvents.serverGameRoundStart, <String, dynamic>{
        'game': gameJson(
          phase: 'drawing',
          word: 'guitar',
          turnStartMs: 1000,
          turnEndMs: 81000,
        ),
      });
      await pumpEventQueue();

      final GameState state = await repository.gameStream.first;
      expect(state.word, 'guitar');
      expect(state.turnEndMs, 81000);
    });

    test('survives the state pushes that follow it', () async {
      // Hints, scores and presence all re-broadcast the game state during a
      // turn. None of them may take the word off the drawer.
      gateway.push(SocketEvents.serverGameRoundStart, <String, dynamic>{
        'game': gameJson(phase: 'drawing', word: 'guitar', turnEndMs: 81000),
      });
      await pumpEventQueue();

      gateway.push(SocketEvents.serverGameHint, <String, dynamic>{
        'hintIndices': <int>[0],
        'maskedWord': 'g _ _ _ _ _',
      });
      gateway.push(SocketEvents.serverGameState, <String, dynamic>{
        'game': gameJson(
          phase: 'drawing',
          word: 'guitar',
          maskedWord: 'g _ _ _ _ _',
          turnEndMs: 81000,
        ),
      });
      await pumpEventQueue();

      final GameState state = await repository.gameStream.first;
      expect(state.word, 'guitar');
      expect(state.maskedWord, 'g _ _ _ _ _');
    });

    test('never survives into somebody else turn', () async {
      gateway.push(SocketEvents.serverGameRoundStart, <String, dynamic>{
        'game': gameJson(phase: 'drawing', word: 'guitar', turnEndMs: 81000),
      });
      await pumpEventQueue();

      // The next turn, seen as a guesser: no word in the payload at all.
      gateway.push(SocketEvents.serverGameRoundStart, <String, dynamic>{
        'game': gameJson(
          phase: 'drawing',
          drawerId: 'b',
          turnIndex: 1,
          maskedWord: '_ _ _',
          turnEndMs: 162000,
        ),
      });
      await pumpEventQueue();

      final GameState state = await repository.gameStream.first;
      expect(state.word, isNull);
      expect(state.drawerId, 'b');
    });

    test('is not shown to a guesser during the turn', () async {
      gateway.push(SocketEvents.serverGameRoundStart, <String, dynamic>{
        'game': gameJson(
          phase: 'drawing',
          drawerId: 'a',
          maskedWord: '_ _ _ _ _ _',
          turnEndMs: 81000,
        ),
      });
      await pumpEventQueue();

      final GameState state = await repository.gameStream.first;
      expect(state.word, isNull);
      expect(state.maskedWord, '_ _ _ _ _ _');
      expect(state.wordChoices, isEmpty);
    });
  });

  group('the round result', () {
    test('is still there for a screen pushed by the same phase change', () async {
      // The results screen is pushed *because* of this event, so it is never
      // listening when the event arrives. Without a replay it renders a
      // spinner under a heading with no word beneath it.
      gateway.push(SocketEvents.serverGameRoundEnd, <String, dynamic>{
        'result': <String, dynamic>{
          'round': 1,
          'word': 'guitar',
          'drawerId': 'a',
          'scoreDeltas': <String, int>{'b': 80},
          'totals': <String, int>{'a': 40, 'b': 80},
          'correctOrder': <String>['b'],
        },
        'game': gameJson(phase: 'round_result', word: 'guitar'),
      });
      await pumpEventQueue();

      final RoundResult result = await repository.roundResultStream.first;
      expect(result.word, 'guitar');
      expect(result.scoreDeltas['b'], 80);
    });

    test('reveals the word to everyone, which is the one time it is public',
        () async {
      gateway.push(SocketEvents.serverGameRoundEnd, <String, dynamic>{
        'result': <String, dynamic>{
          'round': 1,
          'word': 'guitar',
          'drawerId': 'a',
          'scoreDeltas': <String, int>{},
          'totals': <String, int>{},
          'correctOrder': <String>[],
        },
        'game': gameJson(phase: 'round_result', word: 'guitar'),
      });
      await pumpEventQueue();

      final GameState state = await repository.gameStream.first;
      expect(state.phase, GamePhase.roundEnd);
      expect(state.word, 'guitar');
    });

    test('does not leak into the next round', () async {
      gateway.push(SocketEvents.serverGameRoundEnd, <String, dynamic>{
        'result': <String, dynamic>{
          'round': 1,
          'word': 'guitar',
          'drawerId': 'a',
          'scoreDeltas': <String, int>{},
          'totals': <String, int>{},
          'correctOrder': <String>[],
        },
        'game': gameJson(phase: 'round_result', word: 'guitar'),
      });
      await pumpEventQueue();

      gateway.push(SocketEvents.serverGameRoundStart, <String, dynamic>{
        'game': gameJson(
          phase: 'drawing',
          drawerId: 'b',
          turnIndex: 1,
          maskedWord: '_ _ _',
          turnEndMs: 162000,
        ),
      });
      await pumpEventQueue();

      // A results screen opening now would otherwise replay the last word.
      final Future<RoundResult> next =
          repository.roundResultStream.first.timeout(
        const Duration(milliseconds: 50),
        onTimeout: () => throw TimeoutException('nothing replayed'),
      );
      await expectLater(next, throwsA(isA<TimeoutException>()));
    });
  });

  group('a paused game', () {
    test('parses the phase and clears the turn', () async {
      gateway.push(SocketEvents.serverGameRoundStart, <String, dynamic>{
        'game': gameJson(phase: 'drawing', word: 'guitar', turnEndMs: 81000),
      });
      await pumpEventQueue();

      // What the server sends once the room drops below the minimum: no round,
      // so no drawer, no word and no deadline.
      gateway.push(SocketEvents.serverGameState, <String, dynamic>{
        'game': gameJson(phase: 'paused', drawerId: null, turnIndex: 0),
      });
      await pumpEventQueue();

      final GameState state = await repository.gameStream.first;
      expect(state.phase, GamePhase.paused);
      expect(state.drawerId, isNull);
      expect(state.word, isNull);
      expect(state.turnEndMs, 0);
    });
  });
}
