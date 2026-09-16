import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/game_mode.dart';
import 'package:scribble_guess/models/game_result.dart';

/// The match awards carried on `s:game:end`, for the shareable result card.
///
/// ## Why `isEmpty` is the field that matters
///
/// A match nobody drew in has no best drawer, and a match nobody guessed in
/// has no best guesser. The card keys its awards section off this: a `false`
/// here when nothing qualified would print a row of blank names, which reads
/// as a broken card rather than as an unusual match.
void main() {
  group('MatchAwards', () {
    test('parses a complete set', () {
      final MatchAwards awards = MatchAwards.fromJson(const <String, dynamic>{
        'topScorerId': 'u-1',
        'bestDrawerId': 'u-2',
        'bestGuesserId': 'u-3',
        'fastestGuesserId': 'u-4',
      });

      expect(awards.topScorerId, 'u-1');
      expect(awards.bestDrawerId, 'u-2');
      expect(awards.bestGuesserId, 'u-3');
      expect(awards.fastestGuesserId, 'u-4');
      expect(awards.isEmpty, isFalse);
    });

    /// The server sends null for an award nobody earned. An empty string would
    /// be a lookup that silently matches nobody, so it is normalised to null.
    test('reads a missing or blank award as null', () {
      final MatchAwards awards = MatchAwards.fromJson(const <String, dynamic>{
        'topScorerId': 'u-1',
        'bestDrawerId': null,
        'bestGuesserId': '',
      });

      expect(awards.topScorerId, 'u-1');
      expect(awards.bestDrawerId, isNull);
      expect(awards.bestGuesserId, isNull);
      expect(awards.fastestGuesserId, isNull);
    });

    test('reads a match with no awards at all as empty', () {
      expect(
        MatchAwards.fromJson(const <String, dynamic>{}).isEmpty,
        isTrue,
      );
    });

    test('is not empty when a single award was earned', () {
      expect(
        MatchAwards.fromJson(const <String, dynamic>{'topScorerId': 'u-1'}).isEmpty,
        isFalse,
      );
    });

    test('round-trips through its own wire format', () {
      const MatchAwards awards = MatchAwards(
        topScorerId: 'u-1',
        bestDrawerId: 'u-2',
      );

      final MatchAwards parsed = MatchAwards.fromJson(awards.toJson());

      expect(parsed.topScorerId, 'u-1');
      expect(parsed.bestDrawerId, 'u-2');
      expect(parsed.bestGuesserId, isNull);
    });
  });

  group('GameResult with awards', () {
    test('parses the mode and awards alongside the standings', () {
      final GameResult result = GameResult.fromJson(const <String, dynamic>{
        'roomCode': 'A7K9P',
        'totalRounds': 3,
        'gameMode': 'blind',
        'awards': <String, dynamic>{'topScorerId': 'u-1'},
        'standings': <dynamic>[
          <String, dynamic>{'playerId': 'u-1', 'name': 'Ana', 'score': 400, 'rank': 1},
        ],
      });

      expect(result.gameMode, GameMode.blind);
      expect(result.awards.topScorerId, 'u-1');
      expect(result.winner?.name, 'Ana');
    });

    /// An older server sends neither. The result must still render, as a
    /// Classic match with no highlights, rather than failing to parse.
    test('falls back to Classic with no awards', () {
      final GameResult result = GameResult.fromJson(const <String, dynamic>{
        'roomCode': 'A7K9P',
      });

      expect(result.gameMode, GameMode.classic);
      expect(result.awards.isEmpty, isTrue);
    });

    test('round-trips the mode and awards', () {
      const GameResult result = GameResult(
        roomCode: 'A7K9P',
        totalRounds: 5,
        gameMode: GameMode.relay,
        awards: MatchAwards(bestDrawerId: 'u-9'),
      );

      final GameResult parsed = GameResult.fromJson(result.toJson());

      expect(parsed.gameMode, GameMode.relay);
      expect(parsed.awards.bestDrawerId, 'u-9');
    });
  });
}
