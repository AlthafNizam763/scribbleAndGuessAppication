import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// The server-backed social models: ranked players, friends, requests, blocks.
///
/// ## Why these live together rather than one class per file
///
/// They are one payload family. Every leaderboard row, friend, request and
/// search result is the same public card — id, name, avatar — with a different
/// set of extra fields hung off it, and they are parsed by the same three
/// endpoints. Splitting them across six files would mean six imports to render
/// one screen and would hide the fact that [UserCard] is the thing they all
/// share.
///
/// ## They are read-only
///
/// None of these has a `toJson`. They are decoded from server responses and
/// never sent back: score, rank, win rate, relation and friendship status are
/// all server-owned, and a client that could serialise one could be asked to.
/// The only thing this app sends about another player is their id.
///
/// Every `fromJson` tolerates a malformed or missing field rather than
/// throwing, in the same style as the rest of `lib/models`: a leaderboard that
/// drops one bad row still renders.

/// The public card every social payload carries: who somebody is.
class UserCard extends Equatable {
  /// Creates a user card.
  const UserCard({
    this.id = '',
    this.name = '',
    this.avatarId = 0,
    this.avatarColorIndex = 0,
  });

  /// Builds a card from a decoded JSON map.
  factory UserCard.fromJson(Map<String, dynamic> json) => UserCard(
        id: asString(json['id']),
        name: asString(json['username']).isNotEmpty
            ? asString(json['username'])
            : asString(json['name']),
        avatarId: asInt(json['avatarId']),
        avatarColorIndex: asInt(json['avatarColorIndex']),
      );

  /// The server-issued player id.
  final String id;

  /// Display name.
  final String name;

  /// Index of the procedural doodle avatar.
  final int avatarId;

  /// Index into the avatar colour palette.
  final int avatarColorIndex;

  /// Whether this card refers to a real player.
  bool get isEmpty => id.isEmpty;

  @override
  List<Object?> get props => <Object?>[id, name, avatarId, avatarColorIndex];

  @override
  bool get stringify => true;
}

/// A player's lifetime record, as every screen shows it.
class PlayerStats extends Equatable {
  /// Creates a stats block.
  const PlayerStats({
    this.totalScore = 0,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.winRate = 0,
    this.bestRoundScore = 0,
  });

  /// Builds stats from a decoded JSON map.
  factory PlayerStats.fromJson(Map<String, dynamic> json) => PlayerStats(
        totalScore: asInt(json['totalScore']),
        gamesPlayed: asInt(json['gamesPlayed']),
        gamesWon: asInt(json['gamesWon']),
        winRate: asDouble(json['winRate']),
        bestRoundScore: asInt(json['bestRoundScore']),
      );

  /// Points scored across every finished game.
  final int totalScore;

  /// How many games were finished.
  final int gamesPlayed;

  /// How many games ended in first place.
  final int gamesWon;

  /// Wins as a percentage, to one decimal place. Computed by the server.
  final double winRate;

  /// Best single-round score.
  final int bestRoundScore;

  /// The win rate as it is printed, e.g. `33.3%`.
  ///
  /// Formatted here rather than at each call site so the leaderboard and the
  /// profile cannot disagree about how many decimals to show.
  String get winRateLabel =>
      gamesPlayed == 0 ? '—' : '${winRate.toStringAsFixed(1)}%';

  @override
  List<Object?> get props =>
      <Object?>[totalScore, gamesPlayed, gamesWon, winRate, bestRoundScore];

  @override
  bool get stringify => true;
}

/// Where a player plays from. A town at finest — never an address.
class Locality extends Equatable {
  /// Creates a locality.
  const Locality({
    this.city = '',
    this.region = '',
    this.country = '',
    this.label = '',
  });

  /// Builds a locality from a decoded JSON map, or returns null for `null`.
  static Locality? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> json = asMap(raw);

    final Locality locality = Locality(
      city: asString(json['city']),
      region: asString(json['region']),
      country: asString(json['country']),
      label: asString(json['label']),
    );

    return locality.isEmpty ? null : locality;
  }

  /// Town or city.
  final String city;

  /// State, province or region.
  final String region;

  /// ISO 3166-1 alpha-2 country code.
  final String country;

  /// One display line built by the server, e.g. `Kochi, Kerala, IN`.
  final String label;

  /// Whether nothing at all has been set.
  bool get isEmpty =>
      city.isEmpty && region.isEmpty && country.isEmpty && label.isEmpty;

  /// The line to show, falling back to the city when the server sent no label.
  String get display => label.isNotEmpty ? label : city;

  @override
  List<Object?> get props => <Object?>[city, region, country, label];

  @override
  bool get stringify => true;
}

/// One row of a leaderboard, at an absolute rank within its scope.
class RankedPlayer extends Equatable {
  /// Creates a leaderboard row.
  const RankedPlayer({
    this.card = const UserCard(),
    this.stats = const PlayerStats(),
    this.rank = 0,
    this.rankChange,
    this.isSelf = false,
    this.locality,
  });

  /// Builds a row from a decoded JSON map.
  factory RankedPlayer.fromJson(Map<String, dynamic> json) => RankedPlayer(
        card: UserCard.fromJson(json),
        stats: PlayerStats.fromJson(json),
        rank: asInt(json['rank']),
        // Deliberately not `asInt`: null and zero mean different things here.
        // Null is "no history to compare against"; zero is "held their place".
        rankChange: json['rankChange'] is num
            ? (json['rankChange'] as num).toInt()
            : null,
        isSelf: asBool(json['isSelf']),
        locality: Locality.fromJson(json['locality']),
      );

  /// Who this row is.
  final UserCard card;

  /// Their lifetime record.
  final PlayerStats stats;

  /// 1-based, and absolute within the scope rather than within the page.
  final int rank;

  /// Places gained since the last recorded ranking, or null with no history.
  ///
  /// Always null today: the backend records no ranking snapshots, and a
  /// movement arrow computed from no history would be invented. The field is
  /// parsed so that a server which starts sending it needs no new app build.
  final int? rankChange;

  /// Whether this row is the local player. Set by the server.
  final bool isSelf;

  /// Only populated on the locality board.
  final Locality? locality;

  /// Whether this row belongs on the podium.
  bool get isPodium => rank >= 1 && rank <= 3;

  @override
  List<Object?> get props =>
      <Object?>[card, stats, rank, rankChange, isSelf, locality];

  @override
  bool get stringify => true;
}

/// One page of a leaderboard, with the local player's standing attached.
class LeaderboardPage extends Equatable {
  /// Creates a leaderboard page.
  const LeaderboardPage({
    this.scope = LeaderboardScope.world,
    this.items = const <RankedPlayer>[],
    this.currentUserRank,
    this.currentUserEntry,
    this.total = 0,
    this.page = 1,
    this.limit = 25,
    this.hasMore = false,
    this.locality,
  });

  /// Builds a page from a decoded JSON map.
  factory LeaderboardPage.fromJson(Map<String, dynamic> json) {
    final Object? entry = json['currentUserEntry'];

    return LeaderboardPage(
      scope: LeaderboardScope.fromName(asString(json['scope'])),
      items: asList(json['items'])
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> row) => RankedPlayer.fromJson(asMap(row)))
          .toList(growable: false),
      currentUserRank: json['currentUserRank'] is num
          ? (json['currentUserRank'] as num).toInt()
          : null,
      currentUserEntry:
          entry is Map ? RankedPlayer.fromJson(asMap(entry)) : null,
      total: asInt(json['total']),
      page: asInt(json['page'], 1),
      limit: asInt(json['limit'], 25),
      hasMore: asBool(json['hasMore']),
      locality: Locality.fromJson(json['locality']),
    );
  }

  /// An empty first page, used as the initial state of a tab.
  static const LeaderboardPage empty = LeaderboardPage();

  /// Which board this is.
  final LeaderboardScope scope;

  /// The rows on this page, already ranked.
  final List<RankedPlayer> items;

  /// The local player's absolute rank, or null when they are unranked.
  final int? currentUserRank;

  /// The local player's own row, so it can be pinned outside the page.
  ///
  /// Present even when they are far past the last loaded page — which is the
  /// point: somebody in four-thousandth place should not have to scroll there
  /// to find out.
  final RankedPlayer? currentUserEntry;

  /// How many players are in this scope altogether.
  final int total;

  /// The 1-based page number these rows came from.
  final int page;

  /// How many rows were asked for.
  final int limit;

  /// Whether another page exists.
  final bool hasMore;

  /// Whose town this board is. Only set on the locality board.
  final Locality? locality;

  /// Whether the local player has no locality set, on the locality board.
  ///
  /// The signal for the "finish your profile" prompt, distinguished from a
  /// town that simply has nobody else in it yet.
  bool get needsLocality =>
      scope == LeaderboardScope.locality && locality == null;

  /// Returns a copy with [next]'s rows appended, for infinite scroll.
  ///
  /// Rows already present are dropped rather than appended again: a page
  /// boundary that shifts because somebody finished a game mid-scroll would
  /// otherwise show the same player twice.
  LeaderboardPage appending(LeaderboardPage next) {
    final Set<String> seen =
        items.map((RankedPlayer row) => row.card.id).toSet();

    return LeaderboardPage(
      scope: next.scope,
      items: <RankedPlayer>[
        ...items,
        ...next.items.where((RankedPlayer row) => !seen.contains(row.card.id)),
      ],
      currentUserRank: next.currentUserRank,
      currentUserEntry: next.currentUserEntry,
      total: next.total,
      page: next.page,
      limit: next.limit,
      hasMore: next.hasMore,
      locality: next.locality ?? locality,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        scope,
        items,
        currentUserRank,
        currentUserEntry,
        total,
        page,
        limit,
        hasMore,
        locality,
      ];

  @override
  bool get stringify => true;
}

/// An accepted friend.
class Friend extends Equatable {
  /// Creates a friend.
  const Friend({
    this.card = const UserCard(),
    this.stats = const PlayerStats(),
    this.friendsSinceMs = 0,
    this.lastSeenAtMs = 0,
  });

  /// Builds a friend from a decoded JSON map.
  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        card: UserCard.fromJson(json),
        stats: PlayerStats.fromJson(json),
        friendsSinceMs: asInt(json['friendsSinceMs']),
        lastSeenAtMs: asInt(json['lastSeenAtMs']),
      );

  /// Who they are.
  final UserCard card;

  /// Their lifetime record.
  final PlayerStats stats;

  /// When the friendship was accepted.
  final int friendsSinceMs;

  /// When they were last seen online.
  final int lastSeenAtMs;

  @override
  List<Object?> get props => <Object?>[card, stats, friendsSinceMs, lastSeenAtMs];

  @override
  bool get stringify => true;
}

/// A pending friend request, from whichever side is looking at it.
class FriendRequest extends Equatable {
  /// Creates a friend request.
  const FriendRequest({
    this.id = '',
    this.status = FriendRequestStatus.pending,
    this.user = const UserCard(),
    this.createdAtMs = 0,
  });

  /// Builds a request from a decoded JSON map.
  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        id: asString(json['id']),
        status: FriendRequestStatus.fromName(asString(json['status'])),
        user: UserCard.fromJson(asMap(json['user'])),
        createdAtMs: asInt(json['createdAtMs']),
      );

  /// The request id, which is what accept, reject and cancel act on.
  final String id;

  /// Where the request stands.
  final FriendRequestStatus status;

  /// The *other* party — the sender on an incoming request, the receiver on an
  /// outgoing one. Never the local player, who would be useless to draw.
  final UserCard user;

  /// When it was sent.
  final int createdAtMs;

  @override
  List<Object?> get props => <Object?>[id, status, user, createdAtMs];

  @override
  bool get stringify => true;
}

/// A player the local player has blocked.
class BlockedPlayer extends Equatable {
  /// Creates a blocked player entry.
  const BlockedPlayer({this.card = const UserCard(), this.blockedAtMs = 0});

  /// Builds an entry from a decoded JSON map.
  factory BlockedPlayer.fromJson(Map<String, dynamic> json) => BlockedPlayer(
        card: UserCard.fromJson(json),
        blockedAtMs: asInt(json['blockedAtMs']),
      );

  /// Who they are.
  final UserCard card;

  /// When the block was placed.
  final int blockedAtMs;

  @override
  List<Object?> get props => <Object?>[card, blockedAtMs];

  @override
  bool get stringify => true;
}

/// One result of a user search, with the relation needed to draw its button.
class SearchResult extends Equatable {
  /// Creates a search result.
  const SearchResult({
    this.card = const UserCard(),
    this.stats = const PlayerStats(),
    this.relation = SocialRelation.none,
  });

  /// Builds a result from a decoded JSON map.
  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        card: UserCard.fromJson(json),
        stats: PlayerStats.fromJson(asMap(json['stats'])),
        relation: SocialRelation.fromName(asString(json['relation'])),
      );

  /// Who they are.
  final UserCard card;

  /// Their lifetime record.
  final PlayerStats stats;

  /// How the local player stands relative to them, decided by the server.
  final SocialRelation relation;

  @override
  List<Object?> get props => <Object?>[card, stats, relation];

  @override
  bool get stringify => true;
}

/// Another player's full profile, as the local player may see it.
class PublicProfile extends Equatable {
  /// Creates a public profile.
  const PublicProfile({
    this.card = const UserCard(),
    this.stats = const PlayerStats(),
    this.locality,
    this.rank,
    this.relation = SocialRelation.none,
    this.pendingRequestId = '',
    this.lastSeenAtMs = 0,
    this.bio = '',
    this.profileFrame = 'none',
    this.profileTheme = 'paper',
    this.favoriteCategory,
  });

  /// Builds a profile from a decoded JSON map.
  factory PublicProfile.fromJson(Map<String, dynamic> json) => PublicProfile(
        card: UserCard.fromJson(json),
        stats: PlayerStats.fromJson(asMap(json['stats'])),
        locality: Locality.fromJson(json['locality']),
        rank: json['rank'] is num ? (json['rank'] as num).toInt() : null,
        relation: SocialRelation.fromName(asString(json['relation'])),
        pendingRequestId: asString(json['pendingRequestId']),
        lastSeenAtMs: asInt(json['lastSeenAtMs']),
        bio: asString(json['bio']),
        profileFrame: asString(json['profileFrame'], 'none'),
        profileTheme: asString(json['profileTheme'], 'paper'),
        favoriteCategory: json['favoriteCategory'] == null
            ? null
            : asString(json['favoriteCategory']),
      );

  /// Who they are.
  final UserCard card;

  /// Their lifetime record.
  final PlayerStats stats;

  /// Where they play from, when they have said.
  final Locality? locality;

  /// Their world rank, or null when they have never finished a game.
  final int? rank;

  /// How the local player stands relative to them.
  ///
  /// The server decides this. The action buttons below the profile are a pure
  /// function of it, which is what keeps this screen from offering something
  /// the server would refuse.
  final SocialRelation relation;

  /// The request to act on when [relation] is pending. Empty otherwise.
  final String pendingRequestId;

  /// When they were last seen online.
  final int lastSeenAtMs;

  /// A short self-description, masked by the server on save.
  final String bio;

  /// Cosmetic keys. An unknown key renders as the default.
  final String profileFrame;
  final String profileTheme;

  /// The category this player plays most, or null before they have one.
  final String? favoriteCategory;

  /// Returns a copy with the relation replaced, for an optimistic update.
  ///
  /// Used only where the server has already confirmed the change and the
  /// screen is avoiding a second round trip to redraw — never to guess at a
  /// relation the server has not agreed to.
  PublicProfile withRelation(SocialRelation next, {String requestId = ''}) =>
      PublicProfile(
        card: card,
        stats: stats,
        locality: locality,
        rank: rank,
        relation: next,
        pendingRequestId: requestId,
        lastSeenAtMs: lastSeenAtMs,
        bio: bio,
        profileFrame: profileFrame,
        profileTheme: profileTheme,
        favoriteCategory: favoriteCategory,
      );

  @override
  List<Object?> get props => <Object?>[
        card,
        stats,
        locality,
        rank,
        relation,
        pendingRequestId,
        lastSeenAtMs,
      ];

  @override
  bool get stringify => true;
}

/// One page of any of the friend lists.
class SocialPage<T> extends Equatable {
  /// Creates a page.
  const SocialPage({
    this.items = const <Never>[],
    this.total = 0,
    this.page = 1,
    this.hasMore = false,
  });

  /// Builds a page, decoding each row with [itemOf].
  factory SocialPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> row) itemOf,
  ) =>
      SocialPage<T>(
        items: asList(json['items'])
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> row) => itemOf(asMap(row)))
            .toList(growable: false),
        total: asInt(json['total']),
        page: asInt(json['page'], 1),
        hasMore: asBool(json['hasMore']),
      );

  /// The rows on this page.
  final List<T> items;

  /// How many rows exist altogether.
  final int total;

  /// The 1-based page number.
  final int page;

  /// Whether another page exists.
  final bool hasMore;

  /// Returns a copy with [next]'s rows appended.
  SocialPage<T> appending(SocialPage<T> next) => SocialPage<T>(
        items: <T>[...items, ...next.items],
        total: next.total,
        page: next.page,
        hasMore: next.hasMore,
      );

  @override
  List<Object?> get props => <Object?>[items, total, page, hasMore];
}
