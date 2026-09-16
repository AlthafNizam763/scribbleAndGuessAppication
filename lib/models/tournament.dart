import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_mode.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/social.dart';

/// Where a tournament is in its life.
///
/// The server derives this from three timestamps every time it answers, so a
/// value parsed here is current as of the response and goes stale like any
/// other snapshot — a screen left open across a start time shows the old
/// status until it refreshes. That is why [Tournament.startsAtMs] and
/// [Tournament.endsAtMs] come down too: the countdown is drawn from the
/// timestamps, not from this.
enum TournamentStatus {
  /// Announced; registration has not opened.
  announced,

  /// Registration is open and the event has not begun.
  registering,

  /// Running. Ranked matches count towards it.
  live,

  /// Over. The board is final.
  finished;

  /// Parses [v], falling back to [TournamentStatus.announced].
  ///
  /// The conservative fallback: an unrecognised status shows an event as not
  /// yet open rather than as one the player can start scoring in.
  static TournamentStatus fromName(String? v) =>
      asEnum(TournamentStatus.values, v) ?? TournamentStatus.announced;

  /// Whether registration is possible right now.
  ///
  /// Registering during a live points tournament is allowed by the server on
  /// purpose — there are no pairings to disturb — so this is true for both
  /// open states.
  bool get acceptsEntries =>
      this == TournamentStatus.registering || this == TournamentStatus.live;

  /// Whether matches count towards the board.
  bool get isLive => this == TournamentStatus.live;

  /// A short label for the status chip.
  String get label => switch (this) {
        TournamentStatus.announced => 'Soon',
        TournamentStatus.registering => 'Open',
        TournamentStatus.live => 'Live',
        TournamentStatus.finished => 'Finished',
      };
}

/// One scheduled event.
class Tournament extends Equatable {
  /// Creates a tournament.
  const Tournament({
    this.id = '',
    this.name = '',
    this.description = '',
    this.format = 'points',
    this.gameMode = GameMode.classic,
    this.categories = const <WordCategory>[],
    this.status = TournamentStatus.announced,
    this.registerFromMs = 0,
    this.startsAtMs = 0,
    this.endsAtMs = 0,
    this.rewardXp = 0,
    this.rewardBadgeKey,
    this.entrantCount = 0,
    this.isRegistered = false,
    this.winner,
  });

  /// Builds a tournament from a decoded JSON map, tolerating malformed values.
  factory Tournament.fromJson(Map<String, dynamic> json) {
    final Object? winner = json['winner'];

    return Tournament(
      id: asString(json['id']),
      name: asString(json['name']),
      description: asString(json['description']),
      // Left as a raw string rather than an enum: `bracket` is reserved on the
      // server and unimplemented on both sides, so there is nothing for the
      // app to branch on yet and an enum would only invite a switch that
      // pretends otherwise.
      format: asString(json['format'], 'points'),
      gameMode: GameMode.parse(json['gameMode']),
      categories: <WordCategory>[
        for (final dynamic raw in asList(json['categories']))
          WordCategory.fromName(asString(raw)),
      ],
      status: TournamentStatus.fromName(asString(json['status'])),
      registerFromMs: asInt(json['registerFromMs']),
      startsAtMs: asInt(json['startsAtMs']),
      endsAtMs: asInt(json['endsAtMs']),
      rewardXp: asInt(json['rewardXp']),
      rewardBadgeKey: asString(json['rewardBadgeKey']).isEmpty
          ? null
          : asString(json['rewardBadgeKey']),
      entrantCount: asInt(json['entrantCount']),
      isRegistered: asBool(json['isRegistered']),
      winner: winner is Map ? UserCard.fromJson(asMap(winner)) : null,
    );
  }

  /// The server-issued id.
  final String id;

  /// Display name of the event.
  final String name;

  /// What the event is, in a sentence or two. May be empty.
  final String description;

  /// `points` today; `bracket` is reserved. See [Tournament.fromJson].
  final String format;

  /// The mode every match in the event plays under.
  final GameMode gameMode;

  /// Word categories the event is restricted to, or empty for no restriction.
  final List<WordCategory> categories;

  /// Where the event is, as of when this was fetched.
  final TournamentStatus status;

  /// When registration opens, in milliseconds since epoch.
  final int registerFromMs;

  /// When the event begins, in milliseconds since epoch.
  final int startsAtMs;

  /// When the event ends, in milliseconds since epoch.
  final int endsAtMs;

  /// XP awarded to the winner.
  final int rewardXp;

  /// Achievement key awarded to the winner, or null for none.
  final String? rewardBadgeKey;

  /// How many players have registered.
  final int entrantCount;

  /// Whether the local player has registered.
  ///
  /// Decided by the server from its own rows, so a stale `false` costs at most
  /// one refused-as-duplicate registration, which the server treats as a no-op.
  final bool isRegistered;

  /// Who won, once the event has been closed. Null before then.
  final UserCard? winner;

  /// Whether this refers to a real event.
  bool get isEmpty => id.isEmpty;

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        description,
        format,
        gameMode,
        categories,
        status,
        registerFromMs,
        startsAtMs,
        endsAtMs,
        rewardXp,
        rewardBadgeKey,
        entrantCount,
        isRegistered,
        winner,
      ];

  @override
  bool get stringify => true;
}

/// One row of a tournament's own leaderboard.
class TournamentStanding extends Equatable {
  /// Creates a standing.
  const TournamentStanding({
    this.card = const UserCard(),
    this.rank = 0,
    this.score = 0,
    this.matchesPlayed = 0,
    this.matchesWon = 0,
    this.isSelf = false,
  });

  /// Builds a standing from a decoded JSON map.
  factory TournamentStanding.fromJson(Map<String, dynamic> json) =>
      TournamentStanding(
        card: UserCard.fromJson(json),
        rank: asInt(json['rank']),
        score: asInt(json['score']),
        matchesPlayed: asInt(json['matchesPlayed']),
        matchesWon: asInt(json['matchesWon']),
        isSelf: asBool(json['isSelf']),
      );

  /// Who this row is.
  final UserCard card;

  /// 1-based, and absolute within the tournament rather than within the page.
  final int rank;

  /// Total points scored inside the event window.
  ///
  /// Server-computed from matches it ran. There is no endpoint that writes a
  /// tournament score, so this is not a number the app could influence even
  /// if it wanted to.
  final int score;

  /// Matches finished inside the window.
  final int matchesPlayed;

  /// How many of those ended in first place.
  final int matchesWon;

  /// Whether this row is the local player. Set by the server.
  final bool isSelf;

  @override
  List<Object?> get props =>
      <Object?>[card, rank, score, matchesPlayed, matchesWon, isSelf];

  @override
  bool get stringify => true;
}

/// One page of a tournament board.
class TournamentBoard extends Equatable {
  /// Creates a board page.
  const TournamentBoard({
    this.items = const <TournamentStanding>[],
    this.total = 0,
    this.page = 1,
    this.hasMore = false,
  });

  /// Builds a page from a decoded JSON map.
  factory TournamentBoard.fromJson(Map<String, dynamic> json) =>
      TournamentBoard(
        items: <TournamentStanding>[
          for (final dynamic raw in asList(json['items']))
            TournamentStanding.fromJson(asMap(raw)),
        ],
        total: asInt(json['total']),
        page: asInt(json['page'], 1),
        hasMore: asBool(json['hasMore']),
      );

  /// An empty first page.
  static const TournamentBoard empty = TournamentBoard();

  /// The rows on this page, best first.
  final List<TournamentStanding> items;

  /// How many entrants the event has in total.
  final int total;

  /// 1-based page number.
  final int page;

  /// Whether another page follows.
  final bool hasMore;

  @override
  List<Object?> get props => <Object?>[items, total, page, hasMore];

  @override
  bool get stringify => true;
}
