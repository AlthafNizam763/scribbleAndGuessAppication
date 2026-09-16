import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/social.dart';

/// The social models and their wire formats.
///
/// The enum groups matter more than they look, for the same reason the game
/// enums do: a mistyped wire value does not fail loudly, it silently falls
/// back. A wrong [SocialRelation] would leave the profile screen offering "Add
/// friend" to somebody who is already a friend, and the only symptom would be
/// a refusal the player cannot explain.
void main() {
  group('SocialRelation wire format', () {
    test('parses the values the backend actually sends', () {
      expect(SocialRelation.fromName('self'), SocialRelation.self);
      expect(SocialRelation.fromName('none'), SocialRelation.none);
      expect(SocialRelation.fromName('request_sent'), SocialRelation.requestSent);
      expect(
        SocialRelation.fromName('request_received'),
        SocialRelation.requestReceived,
      );
      expect(SocialRelation.fromName('friends'), SocialRelation.friends);
      expect(SocialRelation.fromName('blocked'), SocialRelation.blocked);
    });

    test('round-trips through its wire name', () {
      for (final SocialRelation relation in SocialRelation.values) {
        expect(
          SocialRelation.fromName(relation.wire),
          relation,
          reason: relation.name,
        );
      }
    });

    test('falls back to none rather than throwing', () {
      // A relation this build has not heard of must leave the profile showing
      // its safest action, which the server will refuse if it is wrong.
      expect(SocialRelation.fromName('teleported'), SocialRelation.none);
      expect(SocialRelation.fromName(null), SocialRelation.none);
    });

    test('has no value for being blocked by somebody', () {
      // The server collapses that case to `none` on purpose, so a blocked
      // player cannot tell they were blocked. A value here would invite a
      // client to render it.
      expect(
        SocialRelation.values.map((SocialRelation r) => r.wire),
        isNot(contains('blocked_by')),
      );
    });
  });

  group('LeaderboardScope wire format', () {
    test('matches the endpoint path segments', () {
      expect(LeaderboardScope.world.wire, 'world');
      expect(LeaderboardScope.friends.wire, 'friends');
      expect(LeaderboardScope.locality.wire, 'locality');
    });

    test('round-trips and falls back to world', () {
      for (final LeaderboardScope scope in LeaderboardScope.values) {
        expect(LeaderboardScope.fromName(scope.wire), scope);
      }
      expect(LeaderboardScope.fromName('galaxy'), LeaderboardScope.world);
    });
  });

  group('PlayerStats', () {
    test('parses a stats payload', () {
      final PlayerStats stats = PlayerStats.fromJson(const <String, dynamic>{
        'totalScore': 1200,
        'gamesPlayed': 10,
        'gamesWon': 3,
        'winRate': 30.0,
        'bestRoundScore': 140,
      });

      expect(stats.totalScore, 1200);
      expect(stats.winRateLabel, '30.0%');
    });

    test('shows a dash rather than 0% for a player who has not played', () {
      const PlayerStats stats = PlayerStats();
      expect(stats.winRateLabel, '—');
    });

    test('tolerates a malformed payload instead of throwing', () {
      final PlayerStats stats = PlayerStats.fromJson(const <String, dynamic>{
        'totalScore': 'lots',
        'gamesPlayed': null,
      });
      expect(stats.totalScore, 0);
      expect(stats.gamesPlayed, 0);
    });
  });

  group('Locality', () {
    test('is null when the server sent null', () {
      expect(Locality.fromJson(null), isNull);
    });

    test('is null when every field is blank', () {
      expect(
        Locality.fromJson(const <String, dynamic>{'city': '', 'country': ''}),
        isNull,
      );
    });

    test('prefers the label the server built', () {
      final Locality? locality = Locality.fromJson(const <String, dynamic>{
        'city': 'Kochi',
        'country': 'IN',
        'label': 'Kochi, IN',
      });
      expect(locality?.display, 'Kochi, IN');
    });

    test('falls back to the city when there is no label', () {
      final Locality? locality =
          Locality.fromJson(const <String, dynamic>{'city': 'Kochi'});
      expect(locality?.display, 'Kochi');
    });
  });

  group('RankedPlayer', () {
    Map<String, dynamic> row({Object? rankChange, int rank = 1}) =>
        <String, dynamic>{
          'id': 'u1',
          'username': 'Ada',
          'avatarId': 2,
          'avatarColorIndex': 3,
          'totalScore': 900,
          'gamesPlayed': 6,
          'gamesWon': 2,
          'winRate': 33.3,
          'bestRoundScore': 120,
          'rank': rank,
          'rankChange': rankChange,
          'isSelf': true,
        };

    test('parses a leaderboard row', () {
      final RankedPlayer player = RankedPlayer.fromJson(row());
      expect(player.card.name, 'Ada');
      expect(player.stats.totalScore, 900);
      expect(player.rank, 1);
      expect(player.isSelf, isTrue);
    });

    test('keeps null and zero rank change apart', () {
      // Null means "no history to compare against"; zero means "held their
      // place". Collapsing them would draw an arrow that says nothing.
      expect(RankedPlayer.fromJson(row()).rankChange, isNull);
      expect(RankedPlayer.fromJson(row(rankChange: 0)).rankChange, 0);
      expect(RankedPlayer.fromJson(row(rankChange: -3)).rankChange, -3);
    });

    test('knows which rows are on the podium', () {
      expect(RankedPlayer.fromJson(row(rank: 3)).isPodium, isTrue);
      expect(RankedPlayer.fromJson(row(rank: 4)).isPodium, isFalse);
      expect(RankedPlayer.fromJson(row(rank: 0)).isPodium, isFalse);
    });
  });

  group('LeaderboardPage', () {
    LeaderboardPage page({
      required List<String> ids,
      int number = 1,
      bool hasMore = true,
      int total = 100,
    }) =>
        LeaderboardPage.fromJson(<String, dynamic>{
          'scope': 'world',
          'items': <Map<String, dynamic>>[
            for (final String id in ids)
              <String, dynamic>{'id': id, 'username': id, 'rank': 1},
          ],
          'page': number,
          'hasMore': hasMore,
          'total': total,
        });

    test('parses an empty page', () {
      final LeaderboardPage empty =
          LeaderboardPage.fromJson(const <String, dynamic>{});
      expect(empty.items, isEmpty);
      expect(empty.currentUserRank, isNull);
    });

    test('appends the next page', () {
      final LeaderboardPage merged = page(ids: <String>['a', 'b'])
          .appending(page(ids: <String>['c'], number: 2, hasMore: false));

      expect(
        merged.items.map((RankedPlayer p) => p.card.id),
        <String>['a', 'b', 'c'],
      );
      expect(merged.page, 2);
      expect(merged.hasMore, isFalse);
    });

    test('drops a row that both pages contain', () {
      // A page boundary shifts when somebody finishes a game mid-scroll, and
      // the overlapping row would otherwise appear twice.
      final LeaderboardPage merged = page(ids: <String>['a', 'b'])
          .appending(page(ids: <String>['b', 'c'], number: 2));

      expect(
        merged.items.map((RankedPlayer p) => p.card.id),
        <String>['a', 'b', 'c'],
      );
    });

    test('flags a missing locality only on the locality board', () {
      final LeaderboardPage world =
          LeaderboardPage.fromJson(const <String, dynamic>{'scope': 'world'});
      final LeaderboardPage locality =
          LeaderboardPage.fromJson(const <String, dynamic>{'scope': 'locality'});

      expect(world.needsLocality, isFalse);
      expect(locality.needsLocality, isTrue);
    });

    test('does not flag a locality board that simply has nobody on it', () {
      final LeaderboardPage populated =
          LeaderboardPage.fromJson(const <String, dynamic>{
        'scope': 'locality',
        'locality': <String, dynamic>{'city': 'Kochi', 'label': 'Kochi, IN'},
        'items': <Map<String, dynamic>>[],
      });

      // Empty, but the player *has* set a city — so the prompt to set one
      // would be wrong and the ordinary empty state is right.
      expect(populated.needsLocality, isFalse);
      expect(populated.items, isEmpty);
    });

    test('carries the local player rank even when they are off the page', () {
      final LeaderboardPage board =
          LeaderboardPage.fromJson(const <String, dynamic>{
        'scope': 'world',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'rank': 1},
        ],
        'currentUserRank': 4212,
        'currentUserEntry': <String, dynamic>{
          'id': 'me',
          'username': 'Me',
          'rank': 4212,
          'isSelf': true,
        },
      });

      expect(board.currentUserRank, 4212);
      expect(board.currentUserEntry?.card.id, 'me');
      expect(board.items.any((RankedPlayer p) => p.card.id == 'me'), isFalse);
    });
  });

  group('FriendRequest', () {
    test('parses the other party, not the reader', () {
      final FriendRequest request = FriendRequest.fromJson(const <String, dynamic>{
        'id': 'r1',
        'status': 'pending',
        'user': <String, dynamic>{'id': 'u2', 'username': 'Grace'},
        'createdAtMs': 1700,
      });

      expect(request.id, 'r1');
      expect(request.status, FriendRequestStatus.pending);
      expect(request.user.name, 'Grace');
    });
  });

  group('PublicProfile', () {
    test('parses a profile and its relation', () {
      final PublicProfile profile = PublicProfile.fromJson(const <String, dynamic>{
        'id': 'u3',
        'username': 'Linus',
        'stats': <String, dynamic>{'totalScore': 40, 'gamesPlayed': 2},
        'rank': 17,
        'relation': 'request_received',
        'pendingRequestId': 'r9',
      });

      expect(profile.card.name, 'Linus');
      expect(profile.rank, 17);
      expect(profile.relation, SocialRelation.requestReceived);
      expect(profile.pendingRequestId, 'r9');
    });

    test('keeps an unranked player unranked rather than zero', () {
      final PublicProfile profile =
          PublicProfile.fromJson(const <String, dynamic>{'id': 'u4'});
      expect(profile.rank, isNull);
    });
  });

  group('SocialPage', () {
    test('decodes each row with the supplied builder', () {
      final SocialPage<Friend> friends = SocialPage<Friend>.fromJson(
        const <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'a', 'username': 'Ann'},
            <String, dynamic>{'id': 'b', 'username': 'Bo'},
          ],
          'total': 2,
          'page': 1,
          'hasMore': false,
        },
        Friend.fromJson,
      );

      expect(friends.items.map((Friend f) => f.card.name), <String>['Ann', 'Bo']);
      expect(friends.hasMore, isFalse);
    });

    test('tolerates a missing items array', () {
      final SocialPage<Friend> friends =
          SocialPage<Friend>.fromJson(const <String, dynamic>{}, Friend.fromJson);
      expect(friends.items, isEmpty);
    });
  });
}
