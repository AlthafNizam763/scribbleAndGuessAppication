import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// The automatic knockout tournaments.
///
/// ## Why this is a separate model from [Tournament]
///
/// `models/tournament.dart` describes a *points* event: a window, a running
/// score and a leaderboard. This one has a bracket, a check-in step and AI
/// players, and its status is stored by the server rather than derived from
/// timestamps. They share a word and almost nothing else, and folding them
/// together would produce one class where half the fields are meaningless for
/// half the instances.
///
/// ## What the app can and cannot do with one
///
/// Register, withdraw, check in, and enter a match it has been called to.
/// There is no method here that creates a tournament, adds a bot, changes a
/// setting or reports a result — not because those are gated, but because the
/// server has no endpoint for them. The organiser is the backend.

/// Where a tournament is in its life.
///
/// Stored server-side and sent as-is, so a value parsed here is current as of
/// the response. The countdowns are drawn from the timestamps rather than from
/// this, which is why they come down too.
enum AutoTournamentStatus {
  /// Created, registration has not opened. Usually momentary.
  upcoming('UPCOMING'),

  /// Anybody may join.
  registration('REGISTRATION'),

  /// Registration closed; registered players are confirming they are here.
  checkIn('CHECK_IN'),

  /// The bracket is drawn and matches are being played.
  running('RUNNING'),

  /// Finished, with a winner.
  completed('COMPLETED'),

  /// Called off before it could run.
  cancelled('CANCELLED');

  const AutoTournamentStatus(this.wire);

  /// The value the server sends.
  final String wire;

  /// Parses [v], falling back to [AutoTournamentStatus.upcoming].
  ///
  /// The conservative fallback: an unrecognised status shows a tournament as
  /// not yet open rather than as one the player can act on.
  static AutoTournamentStatus fromWire(String? v) {
    for (final AutoTournamentStatus status in AutoTournamentStatus.values) {
      if (status.wire == v) return status;
    }
    return AutoTournamentStatus.upcoming;
  }

  /// Whether this tournament still occupies its slot.
  bool get isLive =>
      this == AutoTournamentStatus.upcoming ||
      this == AutoTournamentStatus.registration ||
      this == AutoTournamentStatus.checkIn ||
      this == AutoTournamentStatus.running;
}

/// Whether a seat belongs to a person or to the server.
enum TournamentPlayerType {
  /// A real player.
  human('HUMAN'),

  /// An AI player the server added to make the field up.
  aiBot('AI_BOT');

  const TournamentPlayerType(this.wire);

  /// The value the server sends.
  final String wire;

  /// Parses [v].
  ///
  /// Falls back to [TournamentPlayerType.human], and that direction matters:
  /// an unknown value shown as a person is a cosmetic mistake, while a person
  /// shown as a robot is an insult. The `isBot` flag is what the UI actually
  /// branches on anyway — see [TournamentParticipant.isBot].
  static TournamentPlayerType fromWire(String? v) =>
      v == TournamentPlayerType.aiBot.wire
          ? TournamentPlayerType.aiBot
          : TournamentPlayerType.human;
}

/// How hard an AI player plays.
enum BotDifficulty {
  /// Slow, and often wrong.
  easy('EASY', 'Easy'),

  /// The default.
  normal('NORMAL', 'Normal'),

  /// Fast, and usually right.
  hard('HARD', 'Hard');

  const BotDifficulty(this.wire, this.label);

  /// The value the server sends.
  final String wire;

  /// What to show beside the AI badge.
  final String label;

  /// Parses [v], or null when there is none — which is every human.
  static BotDifficulty? fromWire(String? v) {
    if (v == null || v.isEmpty) return null;
    for (final BotDifficulty difficulty in BotDifficulty.values) {
      if (difficulty.wire == v) return difficulty;
    }
    return BotDifficulty.normal;
  }
}

/// Where one bracket match is.
enum TournamentMatchStatus {
  /// Waiting for the round below to decide who plays.
  pending('PENDING'),

  /// Both players known and the room is open.
  ready('READY'),

  /// Being played.
  running('RUNNING'),

  /// Decided.
  completed('COMPLETED'),

  /// Abandoned.
  cancelled('CANCELLED');

  const TournamentMatchStatus(this.wire);

  /// The value the server sends.
  final String wire;

  /// Parses [v], falling back to [TournamentMatchStatus.pending].
  static TournamentMatchStatus fromWire(String? v) {
    for (final TournamentMatchStatus status in TournamentMatchStatus.values) {
      if (status.wire == v) return status;
    }
    return TournamentMatchStatus.pending;
  }

  /// Whether this match can be entered right now.
  bool get isEnterable =>
      this == TournamentMatchStatus.ready || this == TournamentMatchStatus.running;
}

/// One entrant, human or AI.
class TournamentParticipant extends Equatable {
  /// Creates a participant.
  const TournamentParticipant({
    this.registrationId = '',
    this.playerId = '',
    this.displayName = '',
    this.avatarId = 0,
    this.avatarColorIndex = 0,
    this.playerType = TournamentPlayerType.human,
    this.isBot = false,
    this.botDifficulty,
    this.status = '',
    this.seed,
    this.isSelf = false,
    this.placement = 0,
  });

  /// Builds a participant from a decoded JSON map.
  factory TournamentParticipant.fromJson(Map<String, dynamic> json) =>
      TournamentParticipant(
        registrationId: asString(json['registrationId']),
        playerId: asString(json['playerId']),
        displayName: asString(json['displayName']),
        avatarId: asInt(json['avatarId']),
        avatarColorIndex: asInt(json['avatarColorIndex']),
        playerType: TournamentPlayerType.fromWire(asString(json['playerType'])),
        isBot: asBool(json['isBot']),
        botDifficulty: BotDifficulty.fromWire(asString(json['botDifficulty'])),
        status: asString(json['status']),
        seed: json['seed'] == null ? null : asInt(json['seed']),
        isSelf: asBool(json['isSelf']),
        placement: asInt(json['placement']),
      );

  /// The server's id for this seat.
  final String registrationId;

  /// The id this entrant plays under: a user id, or a bot's play id.
  final String playerId;

  /// What to show.
  final String displayName;

  /// Avatar index.
  final int avatarId;

  /// Avatar colour index.
  final int avatarColorIndex;

  /// Human or AI.
  final TournamentPlayerType playerType;

  /// Whether to draw the AI badge.
  ///
  /// The server sends this on every participant, so the badge is drawn from
  /// what arrived rather than inferred. That is the whole of "do not show AI
  /// bots as real humans" on this side: a client that ignores it is choosing
  /// to, not lacking the information.
  final bool isBot;

  /// How hard this AI plays, or null for a person.
  final BotDifficulty? botDifficulty;

  /// Raw registration status, for the results table.
  final String status;

  /// Position in the draw, once seeded.
  final int? seed;

  /// Whether this row is the local player. Never true for an AI.
  final bool isSelf;

  /// Placement in the results table. Zero outside one.
  final int placement;

  /// Whether this entrant has been knocked out.
  bool get isEliminated => status == 'ELIMINATED';

  /// Whether this entrant won the tournament.
  bool get isWinner => status == 'WINNER';

  @override
  List<Object?> get props => <Object?>[
        registrationId,
        playerId,
        displayName,
        avatarId,
        avatarColorIndex,
        playerType,
        isBot,
        botDifficulty,
        status,
        seed,
        isSelf,
        placement,
      ];
}

/// A match the local player has been called to.
class ViewerMatch extends Equatable {
  /// Creates a viewer match.
  const ViewerMatch({
    this.matchId = '',
    this.roundNumber = 0,
    this.matchNumber = 0,
    this.status = TournamentMatchStatus.pending,
    this.roomCode,
    this.entryDeadlineMs = 0,
  });

  /// Builds one from a decoded JSON map.
  factory ViewerMatch.fromJson(Map<String, dynamic> json) => ViewerMatch(
        matchId: asString(json['matchId']),
        roundNumber: asInt(json['roundNumber']),
        matchNumber: asInt(json['matchNumber']),
        status: TournamentMatchStatus.fromWire(asString(json['status'])),
        roomCode: asString(json['roomCode']).isEmpty
            ? null
            : asString(json['roomCode']),
        entryDeadlineMs: asInt(json['entryDeadlineMs']),
      );

  /// The server's id for this match.
  final String matchId;

  /// Which round it is in, 1-based.
  final int roundNumber;

  /// Which match of that round, 1-based.
  final int matchNumber;

  /// Where the match is.
  final TournamentMatchStatus status;

  /// The room to join. Only ever sent to this match's two players.
  final String? roomCode;

  /// When entry closes and the match is decided without the absentee.
  final int entryDeadlineMs;

  @override
  List<Object?> get props =>
      <Object?>[matchId, roundNumber, matchNumber, status, roomCode, entryDeadlineMs];
}

/// What the local player can do with one tournament.
///
/// Computed by the server rather than derived here, because the rules it
/// encodes are server rules — one tournament at a time, check-in only for the
/// registered, no entry after the window. Deriving them locally would be a
/// second implementation that could disagree, and the disagreement would look
/// like a button that does nothing.
class ViewerTournamentState extends Equatable {
  /// Creates a viewer state.
  const ViewerTournamentState({
    this.isRegistered = false,
    this.isCheckedIn = false,
    this.canRegister = false,
    this.canCheckIn = false,
    this.canWithdraw = false,
    this.blockedReason,
    this.activeMatch,
  });

  /// Builds one from a decoded JSON map.
  factory ViewerTournamentState.fromJson(Map<String, dynamic> json) {
    final Object? match = json['activeMatch'];

    return ViewerTournamentState(
      isRegistered: asBool(json['isRegistered']),
      isCheckedIn: asBool(json['isCheckedIn']),
      canRegister: asBool(json['canRegister']),
      canCheckIn: asBool(json['canCheckIn']),
      canWithdraw: asBool(json['canWithdraw']),
      blockedReason: asString(json['blockedReason']).isEmpty
          ? null
          : asString(json['blockedReason']),
      activeMatch: match is Map ? ViewerMatch.fromJson(asMap(match)) : null,
    );
  }

  /// Whether the player holds a place.
  final bool isRegistered;

  /// Whether they have confirmed they are here.
  final bool isCheckedIn;

  /// Whether registering would succeed right now.
  final bool canRegister;

  /// Whether checking in would succeed right now.
  final bool canCheckIn;

  /// Whether withdrawing would succeed right now.
  final bool canWithdraw;

  /// Why they cannot join, in a sentence to show them. Null when they can.
  final String? blockedReason;

  /// The match they should be entering, if any.
  final ViewerMatch? activeMatch;

  @override
  List<Object?> get props => <Object?>[
        isRegistered,
        isCheckedIn,
        canRegister,
        canCheckIn,
        canWithdraw,
        blockedReason,
        activeMatch,
      ];
}

/// One automatic tournament.
class AutoTournament extends Equatable {
  /// Creates a tournament.
  const AutoTournament({
    this.id = '',
    this.slotNumber = 0,
    this.tournamentNumber = 0,
    this.name = '',
    this.description = '',
    this.status = AutoTournamentStatus.upcoming,
    this.format = 'KNOCKOUT',
    this.minPlayers = 0,
    this.maxPlayers = 0,
    this.minHumanPlayers = 0,
    this.maxBots = 0,
    this.allowBots = true,
    this.botDifficulty = BotDifficulty.normal,
    this.humanPlayerCount = 0,
    this.botPlayerCount = 0,
    this.totalPlayers = 0,
    this.registrationOpenAtMs = 0,
    this.registrationCloseAtMs = 0,
    this.checkInOpenAtMs = 0,
    this.checkInCloseAtMs = 0,
    this.startAtMs = 0,
    this.totalRounds = 0,
    this.currentRound = 0,
    this.entryFee = 0,
    this.cancelReason,
    this.viewer = const ViewerTournamentState(),
    this.winner,
  });

  /// Builds a tournament from a decoded JSON map, tolerating malformed values.
  factory AutoTournament.fromJson(Map<String, dynamic> json) {
    final Object? winner = json['winner'];

    return AutoTournament(
      id: asString(json['id']),
      slotNumber: asInt(json['slotNumber']),
      tournamentNumber: asInt(json['tournamentNumber']),
      name: asString(json['name']),
      description: asString(json['description']),
      status: AutoTournamentStatus.fromWire(asString(json['status'])),
      format: asString(json['format'], 'KNOCKOUT'),
      minPlayers: asInt(json['minPlayers']),
      maxPlayers: asInt(json['maxPlayers']),
      minHumanPlayers: asInt(json['minHumanPlayers']),
      maxBots: asInt(json['maxBots']),
      allowBots: asBool(json['allowBots'], true),
      botDifficulty:
          BotDifficulty.fromWire(asString(json['botDifficulty'])) ??
              BotDifficulty.normal,
      humanPlayerCount: asInt(json['humanPlayerCount']),
      botPlayerCount: asInt(json['botPlayerCount']),
      totalPlayers: asInt(json['totalPlayers']),
      registrationOpenAtMs: asInt(json['registrationOpenAtMs']),
      registrationCloseAtMs: asInt(json['registrationCloseAtMs']),
      checkInOpenAtMs: asInt(json['checkInOpenAtMs']),
      checkInCloseAtMs: asInt(json['checkInCloseAtMs']),
      startAtMs: asInt(json['startAtMs']),
      totalRounds: asInt(json['totalRounds']),
      currentRound: asInt(json['currentRound']),
      entryFee: asInt(json['entryFee']),
      cancelReason: asString(json['cancelReason']).isEmpty
          ? null
          : asString(json['cancelReason']),
      viewer: ViewerTournamentState.fromJson(asMap(json['viewer'])),
      winner: winner is Map
          ? TournamentParticipant.fromJson(asMap(winner))
          : null,
    );
  }

  /// The server-issued id.
  final String id;

  /// Which of the slots this occupies, 1-based.
  final int slotNumber;

  /// The display number, unique for all time.
  final int tournamentNumber;

  /// "Daily Scribble Cup #7".
  final String name;

  /// What it is, in a sentence.
  final String description;

  /// Where it is in its life.
  final AutoTournamentStatus status;

  /// `KNOCKOUT`.
  final String format;

  /// Fewest players it can start with.
  final int minPlayers;

  /// Most players it can hold.
  final int maxPlayers;

  /// Fewest real people it can run with.
  final int minHumanPlayers;

  /// Most AI players it may contain.
  final int maxBots;

  /// Whether AI players may be used to fill a shortfall.
  final bool allowBots;

  /// How hard those AI players play.
  final BotDifficulty botDifficulty;

  /// How many real people have joined.
  ///
  /// Kept apart from [botPlayerCount] on purpose. A single total would let a
  /// screen draw "4 / 4" on a tournament that is one person and three robots,
  /// which is exactly what the product forbids — so the honest rendering is
  /// the easy one and the misleading one takes effort.
  final int humanPlayerCount;

  /// How many AI players are on the roster.
  final int botPlayerCount;

  /// The two above, added up.
  final int totalPlayers;

  /// When registration opened, in milliseconds since epoch.
  final int registrationOpenAtMs;

  /// When registration closes.
  final int registrationCloseAtMs;

  /// When check-in opens. Equal to [registrationCloseAtMs].
  final int checkInOpenAtMs;

  /// When check-in closes and the bracket is drawn.
  final int checkInCloseAtMs;

  /// When play begins.
  final int startAtMs;

  /// How many bracket rounds there are. Zero before seeding.
  final int totalRounds;

  /// Which round is being played, 1-based. Zero before seeding.
  final int currentRound;

  /// Always zero. Sent so the UI does not hardcode a product decision.
  final int entryFee;

  /// Why a cancelled tournament was cancelled.
  final String? cancelReason;

  /// What the local player can do here.
  final ViewerTournamentState viewer;

  /// Who won, once it is over.
  final TournamentParticipant? winner;

  /// Whether this refers to a real tournament.
  bool get isEmpty => id.isEmpty;

  /// The deadline this tournament is currently counting down to, or null.
  int? get activeDeadlineMs => switch (status) {
        AutoTournamentStatus.registration => registrationCloseAtMs,
        AutoTournamentStatus.checkIn => checkInCloseAtMs,
        _ => null,
      };

  @override
  List<Object?> get props => <Object?>[
        id,
        slotNumber,
        tournamentNumber,
        name,
        status,
        humanPlayerCount,
        botPlayerCount,
        totalPlayers,
        registrationCloseAtMs,
        checkInCloseAtMs,
        totalRounds,
        currentRound,
        cancelReason,
        viewer,
        winner,
      ];
}

/// One slot, holding a tournament or nothing.
///
/// An empty slot is a row rather than an absence, because the screen shows
/// three cards and "a new tournament will be created automatically" is a card.
class TournamentSlot extends Equatable {
  /// Creates a slot.
  const TournamentSlot({this.slotNumber = 0, this.tournament});

  /// Builds a slot from a decoded JSON map.
  factory TournamentSlot.fromJson(Map<String, dynamic> json) {
    final Object? tournament = json['tournament'];

    return TournamentSlot(
      slotNumber: asInt(json['slotNumber']),
      tournament: tournament is Map
          ? AutoTournament.fromJson(asMap(tournament))
          : null,
    );
  }

  /// 1-based.
  final int slotNumber;

  /// What is in it, or null between tournaments.
  final AutoTournament? tournament;

  @override
  List<Object?> get props => <Object?>[slotNumber, tournament];
}

/// One pairing in a bracket.
class TournamentMatch extends Equatable {
  /// Creates a match.
  const TournamentMatch({
    this.matchId = '',
    this.roundNumber = 0,
    this.matchNumber = 0,
    this.status = TournamentMatchStatus.pending,
    this.outcome,
    this.playerA,
    this.playerB,
    this.scoreA = 0,
    this.scoreB = 0,
    this.winnerRegistrationId,
    this.roomCode,
    this.entryDeadlineMs,
  });

  /// Builds a match from a decoded JSON map.
  factory TournamentMatch.fromJson(Map<String, dynamic> json) {
    final Object? a = json['playerA'];
    final Object? b = json['playerB'];

    return TournamentMatch(
      matchId: asString(json['matchId']),
      roundNumber: asInt(json['roundNumber']),
      matchNumber: asInt(json['matchNumber']),
      status: TournamentMatchStatus.fromWire(asString(json['status'])),
      outcome: asString(json['outcome']).isEmpty
          ? null
          : asString(json['outcome']),
      playerA: a is Map ? TournamentParticipant.fromJson(asMap(a)) : null,
      playerB: b is Map ? TournamentParticipant.fromJson(asMap(b)) : null,
      scoreA: asInt(json['scoreA']),
      scoreB: asInt(json['scoreB']),
      winnerRegistrationId: asString(json['winnerRegistrationId']).isEmpty
          ? null
          : asString(json['winnerRegistrationId']),
      roomCode: asString(json['roomCode']).isEmpty
          ? null
          : asString(json['roomCode']),
      entryDeadlineMs: json['entryDeadlineMs'] == null
          ? null
          : asInt(json['entryDeadlineMs']),
    );
  }

  /// The server's id.
  final String matchId;

  /// Which round, 1-based.
  final int roundNumber;

  /// Which match of the round, 1-based.
  final int matchNumber;

  /// Where it is.
  final TournamentMatchStatus status;

  /// `PLAYED`, `BYE` or `WALKOVER`, once decided.
  final String? outcome;

  /// The top seat, or null while the round below decides it.
  final TournamentParticipant? playerA;

  /// The bottom seat.
  final TournamentParticipant? playerB;

  /// Final score for [playerA].
  final int scoreA;

  /// Final score for [playerB].
  final int scoreB;

  /// Who won.
  final String? winnerRegistrationId;

  /// The room. Null unless the local player is in this match.
  final String? roomCode;

  /// When entry closes.
  final int? entryDeadlineMs;

  /// Whether this pairing was decided without being played.
  bool get isBye => outcome == 'BYE';

  /// Whether one player failed to turn up.
  bool get isWalkover => outcome == 'WALKOVER';

  @override
  List<Object?> get props => <Object?>[
        matchId,
        roundNumber,
        matchNumber,
        status,
        outcome,
        playerA,
        playerB,
        scoreA,
        scoreB,
        winnerRegistrationId,
        roomCode,
      ];
}

/// One round of a bracket.
class TournamentBracketRound extends Equatable {
  /// Creates a round.
  const TournamentBracketRound({
    this.roundNumber = 0,
    this.name = '',
    this.matches = const <TournamentMatch>[],
  });

  /// Builds a round from a decoded JSON map.
  factory TournamentBracketRound.fromJson(Map<String, dynamic> json) =>
      TournamentBracketRound(
        roundNumber: asInt(json['roundNumber']),
        name: asString(json['name']),
        matches: <TournamentMatch>[
          for (final dynamic raw in asList(json['matches']))
            TournamentMatch.fromJson(asMap(raw)),
        ],
      );

  /// 1-based.
  final int roundNumber;

  /// "Quarter-final", "Final".
  final String name;

  /// The pairings, in bracket order.
  final List<TournamentMatch> matches;

  @override
  List<Object?> get props => <Object?>[roundNumber, name, matches];
}

/// A whole bracket.
class TournamentBracket extends Equatable {
  /// Creates a bracket.
  const TournamentBracket({
    this.tournamentId = '',
    this.totalRounds = 0,
    this.currentRound = 0,
    this.rounds = const <TournamentBracketRound>[],
  });

  /// Builds a bracket from a decoded JSON map.
  factory TournamentBracket.fromJson(Map<String, dynamic> json) =>
      TournamentBracket(
        tournamentId: asString(json['tournamentId']),
        totalRounds: asInt(json['totalRounds']),
        currentRound: asInt(json['currentRound']),
        rounds: <TournamentBracketRound>[
          for (final dynamic raw in asList(json['rounds']))
            TournamentBracketRound.fromJson(asMap(raw)),
        ],
      );

  /// An empty bracket, for a tournament that has not been drawn yet.
  static const TournamentBracket empty = TournamentBracket();

  /// Which tournament this is.
  final String tournamentId;

  /// How many rounds it has.
  final int totalRounds;

  /// Which round is being played.
  final int currentRound;

  /// The rounds, widest first.
  final List<TournamentBracketRound> rounds;

  /// Whether there is anything to draw.
  bool get isEmpty => rounds.isEmpty;

  @override
  List<Object?> get props =>
      <Object?>[tournamentId, totalRounds, currentRound, rounds];
}

/// Where a player's match is, after asking to enter it.
class TournamentMatchEntry extends Equatable {
  /// Creates an entry.
  const TournamentMatchEntry({
    this.roomId = '',
    this.roomCode = '',
    this.matchId = '',
    this.roundNumber = 0,
    this.matchNumber = 0,
    this.entryDeadlineMs,
  });

  /// Builds one from a decoded JSON map.
  factory TournamentMatchEntry.fromJson(Map<String, dynamic> json) =>
      TournamentMatchEntry(
        roomId: asString(json['roomId']),
        roomCode: asString(json['roomCode']),
        matchId: asString(json['matchId']),
        roundNumber: asInt(json['roundNumber']),
        matchNumber: asInt(json['matchNumber']),
        entryDeadlineMs: json['entryDeadlineMs'] == null
            ? null
            : asInt(json['entryDeadlineMs']),
      );

  /// The room's id.
  final String roomId;

  /// The code to join with.
  final String roomCode;

  /// Which match this is.
  final String matchId;

  /// Which round, 1-based.
  final int roundNumber;

  /// Which match of that round, 1-based.
  final int matchNumber;

  /// When entry closes.
  final int? entryDeadlineMs;

  @override
  List<Object?> get props =>
      <Object?>[roomId, roomCode, matchId, roundNumber, matchNumber];
}
