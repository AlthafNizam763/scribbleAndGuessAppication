import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/player_stats.dart';
import 'package:scribble_guess/models/social.dart';

/// The career record and the profile fields, as the client parses them.
///
/// ## What is worth asserting
///
/// Everything here is derived by the server, so the client's job is parsing
/// and formatting. The failure that matters is a fresh account: every ratio is
/// zero, and a screen that rendered a wall of zeroes would read as broken
/// rather than as new. [PlayerCareerStats.hasPlayed] is what the screen keys
/// its empty state off, so it is pinned.
void main() {
  group('PlayerCareerStats', () {
    Map<String, dynamic> payload() => <String, dynamic>{
          'gamesPlayed': 10,
          'gamesWon': 4,
          'gamesLost': 6,
          'winRate': 40.0,
          'totalScore': 2500,
          'bestRoundScore': 480,
          'averageScore': 250,
          'correctGuesses': 120,
          'firstGuesses': 30,
          'fastGuesses': 8,
          'drawingTurns': 20,
          'perfectDrawings': 5,
          'perfectDrawingRate': 25.0,
          'currentWinStreak': 2,
          'bestWinStreak': 6,
          'xp': 1200,
          'level': 7,
          'levelTitle': 'Sketcher',
          'achievementsUnlocked': 3,
          'achievementsTotal': 12,
          'joinedAtMs': 1700000000000,
          'lastSeenAtMs': 1700000900000,
        };

    test('parses a complete record', () {
      final PlayerCareerStats stats = PlayerCareerStats.fromJson(payload());

      expect(stats.gamesPlayed, 10);
      expect(stats.gamesLost, 6);
      expect(stats.averageScore, 250);
      expect(stats.levelTitle, 'Sketcher');
      expect(stats.hasPlayed, isTrue);
    });

    test('formats the rates it prints', () {
      final PlayerCareerStats stats = PlayerCareerStats.fromJson(payload());

      expect(stats.winRateLabel, '40.0%');
      expect(stats.perfectDrawingRateLabel, '25.0%');
      expect(stats.achievementsLabel, '3 / 12');
    });

    /// A fresh account has nothing to divide by. The labels must say so rather
    /// than printing a misleading `0.0%`.
    test('prints a dash rather than a zero rate for a new account', () {
      final PlayerCareerStats stats =
          PlayerCareerStats.fromJson(const <String, dynamic>{});

      expect(stats.hasPlayed, isFalse);
      expect(stats.winRateLabel, '—');
      expect(stats.perfectDrawingRateLabel, '—');
    });

    test('defaults to a level-1 account on a malformed response', () {
      final PlayerCareerStats stats =
          PlayerCareerStats.fromJson(const <String, dynamic>{});

      expect(stats.level, 1);
      expect(stats.xp, 0);
      expect(stats.achievementsTotal, 0);
    });
  });

  group('profile customisation', () {
    test('parses the new fields', () {
      final PublicProfile profile = PublicProfile.fromJson(const <String, dynamic>{
        'id': 'u-1',
        'username': 'Ana',
        'bio': 'I draw badly on purpose.',
        'profileFrame': 'gold',
        'profileTheme': 'mint',
        'favoriteCategory': 'animals',
      });

      expect(profile.bio, 'I draw badly on purpose.');
      expect(profile.profileFrame, 'gold');
      expect(profile.profileTheme, 'mint');
      expect(profile.favoriteCategory, 'animals');
    });

    /// An older server sends none of these. The defaults must be the neutral
    /// cosmetics rather than empty strings the renderer would have to guard.
    test('falls back to the default cosmetics', () {
      final PublicProfile profile =
          PublicProfile.fromJson(const <String, dynamic>{'id': 'u-1'});

      expect(profile.bio, isEmpty);
      expect(profile.profileFrame, 'none');
      expect(profile.profileTheme, 'paper');
      expect(profile.favoriteCategory, isNull);
    });

    /// The relation copy is used after the server confirms a friend action; it
    /// must not quietly drop the rest of the profile.
    test('keeps the cosmetics when the relation changes', () {
      final PublicProfile profile = PublicProfile.fromJson(const <String, dynamic>{
        'id': 'u-1',
        'bio': 'Hello',
        'profileFrame': 'leaf',
      });

      final PublicProfile updated = profile.withRelation(SocialRelation.friends);

      expect(updated.bio, 'Hello');
      expect(updated.profileFrame, 'leaf');
      expect(updated.relation, SocialRelation.friends);
    });
  });
}
