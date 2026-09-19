import 'package:flutter/foundation.dart';
import 'package:scribble_guess/models/games/playing_card.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// What a player can throw across the table. Flavour; never affects a rule.
enum BarReaction {
  stare('stare', 'Stare', '👁'),
  smirk('smirk', 'Smirk', '😏'),
  sweat('sweat', 'Sweat', '😅'),
  laugh('laugh', 'Laugh', '😂'),
  drink('drink', 'Drink', '🥃'),
  shrug('shrug', 'Shrug', '🤷');

  const BarReaction(this.wire, this.label, this.glyph);

  final String wire;
  final String label;
  final String glyph;

  static BarReaction? fromWire(String value) {
    for (final BarReaction reaction in values) {
      if (reaction.wire == value) return reaction;
    }
    return null;
  }
}

/// One card in a hand: a face, and an identity that survives a duplicate face.
///
/// The shoe holds more than one of some faces — only three ranks are in play
/// and a table of six needs thirty cards — so two aces of spades can sit in one
/// hand exactly as they would out of a casino's six-deck shoe. The id is what
/// distinguishes them, and it is what goes back on the wire when one is played.
@immutable
class BarCard {
  const BarCard({required this.id, required this.card});

  static BarCard? fromJson(Map<String, dynamic> json) {
    final String id = asString(json['id']);
    final PlayingCard? card = PlayingCard.parse(asString(json['card']));
    if (id.isEmpty || card == null) return null;
    return BarCard(id: id, card: card);
  }

  final String id;
  final PlayingCard card;
}

/// One seat at the bar.
@immutable
class BarSeat {
  const BarSeat({
    required this.playerId,
    required this.cardCount,
    required this.alive,
    required this.glassesRemaining,
    required this.shotsTaken,
    required this.outOfRound,
  });

  factory BarSeat.fromJson(Map<String, dynamic> json) => BarSeat(
        playerId: asString(json['playerId']),
        cardCount: asInt(json['cardCount']),
        alive: asBool(json['alive'], true),
        glassesRemaining: asInt(json['glassesRemaining'], 6),
        shotsTaken: asInt(json['shotsTaken']),
        outOfRound: asBool(json['outOfRound']),
      );

  final String playerId;
  final int cardCount;

  /// Still in the match. A player who hits the bad glass is out for good.
  final bool alive;

  /// Glasses left on their tray. Six is untouched; one is a certainty.
  ///
  /// The odds on their next lost call are exactly `1 / glassesRemaining`,
  /// which is why this is on screen: it is the risk half of the game and both
  /// the player and the bots are looking at the same number.
  final int glassesRemaining;

  final int shotsTaken;

  /// Emptied their hand this round. Still on the hook for their last claim.
  final bool outOfRound;

  /// How exposed they are, 0 to 1, for the tray and the nerve meter.
  double get peril => glassesRemaining <= 0 ? 1 : 1 - (glassesRemaining - 1) / 5;
}

/// A claim somebody made, before anybody has paid to see it.
@immutable
class BarClaim {
  const BarClaim({required this.playerId, required this.count, required this.atMs});

  static BarClaim? fromJson(Map<String, dynamic> json) {
    final String playerId = asString(json['playerId']);
    if (playerId.isEmpty) return null;
    return BarClaim(
      playerId: playerId,
      count: asInt(json['count']),
      atMs: asInt(json['atMs']),
    );
  }

  final String playerId;

  /// How many cards went down. **Never what they were** — that is the game.
  final int count;

  final int atMs;
}

/// A call, and the cards it turned over.
@immutable
class BarChallenge {
  const BarChallenge({
    required this.challengerId,
    required this.claimantId,
    required this.honest,
    required this.revealed,
    required this.loserId,
    required this.atMs,
  });

  static BarChallenge? fromJson(Map<String, dynamic> json) {
    final String challengerId = asString(json['challengerId']);
    if (challengerId.isEmpty) return null;

    return BarChallenge(
      challengerId: challengerId,
      claimantId: asString(json['claimantId']),
      honest: asBool(json['honest']),
      revealed: <BarCard>[
        for (final Object? row in asList(json['revealed']))
          if (row is Map)
            if (BarCard.fromJson(asMap(row)) case final BarCard card) card,
      ],
      loserId: asString(json['loserId']),
      atMs: asInt(json['atMs']),
    );
  }

  final String challengerId;
  final String claimantId;

  /// Whether every revealed card really was the table rank or a joker.
  /// One wrong card out of three makes the whole claim a lie.
  final bool honest;

  /// The cards, face up. A call is paid for with a shot, and this is what it
  /// bought: everybody got to see them.
  final List<BarCard> revealed;

  final String loserId;
  final int atMs;
}

/// The house shot: one glass off a tray that is never refilled.
@immutable
class BarShot {
  const BarShot({
    required this.playerId,
    required this.glassesBefore,
    required this.glassesRemaining,
    required this.eliminated,
    required this.atMs,
  });

  static BarShot? fromJson(Map<String, dynamic> json) {
    final String playerId = asString(json['playerId']);
    if (playerId.isEmpty) return null;

    return BarShot(
      playerId: playerId,
      glassesBefore: asInt(json['glassesBefore'], 6),
      glassesRemaining: asInt(json['glassesRemaining']),
      eliminated: asBool(json['eliminated']),
      atMs: asInt(json['atMs']),
    );
  }

  final String playerId;

  /// How many were standing when they drank. The odds they were facing.
  final int glassesBefore;

  final int glassesRemaining;

  /// Whether that was the one the house does not talk about.
  final bool eliminated;

  final int atMs;
}

/// A reaction somebody threw across the table.
@immutable
class BarReactionEvent {
  const BarReactionEvent({
    required this.playerId,
    required this.reaction,
    required this.atMs,
  });

  static BarReactionEvent? fromJson(Map<String, dynamic> json) {
    final String playerId = asString(json['playerId']);
    final BarReaction? reaction = BarReaction.fromWire(asString(json['reaction']));
    if (playerId.isEmpty || reaction == null) return null;
    return BarReactionEvent(
      playerId: playerId,
      reaction: reaction,
      atMs: asInt(json['atMs']),
    );
  }

  final String playerId;
  final BarReaction reaction;
  final int atMs;
}

/// Everything a Bluff Bar screen needs, parsed from one projection.
@immutable
class BluffBarState {
  const BluffBarState({
    required this.status,
    required this.currentPlayerId,
    required this.tableRank,
    required this.roundNumber,
    required this.deckComposition,
    required this.seats,
    required this.hand,
    required this.pileCount,
    required this.claims,
    required this.lastClaim,
    required this.lastChallenge,
    required this.lastShot,
    required this.lastReaction,
    required this.eliminated,
  });

  static const BluffBarState empty = BluffBarState(
    status: '',
    currentPlayerId: '',
    tableRank: null,
    roundNumber: 0,
    deckComposition: <String, int>{},
    seats: <BarSeat>[],
    hand: <BarCard>[],
    pileCount: 0,
    claims: <BarClaim>[],
    lastClaim: null,
    lastChallenge: null,
    lastShot: null,
    lastReaction: null,
    eliminated: <String>[],
  );

  factory BluffBarState.fromJson(Map<String, dynamic> json) => BluffBarState(
        status: asString(json['status']),
        currentPlayerId: asString(json['currentPlayerId']),
        tableRank: CardRank.fromWire(asString(json['tableRank'])),
        roundNumber: asInt(json['roundNumber']),
        deckComposition: asIntMap(json['deckComposition']),
        seats: <BarSeat>[
          for (final Object? row in asList(json['players']))
            if (row is Map) BarSeat.fromJson(asMap(row)),
        ],
        hand: <BarCard>[
          for (final Object? row in asList(json['hand']))
            if (row is Map)
              if (BarCard.fromJson(asMap(row)) case final BarCard card) card,
        ],
        pileCount: asInt(json['pileCount']),
        claims: <BarClaim>[
          for (final Object? row in asList(json['claims']))
            if (row is Map)
              if (BarClaim.fromJson(asMap(row)) case final BarClaim claim) claim,
        ],
        lastClaim: BarClaim.fromJson(asMap(json['lastClaim'])),
        lastChallenge: BarChallenge.fromJson(asMap(json['lastChallenge'])),
        lastShot: BarShot.fromJson(asMap(json['lastShot'])),
        lastReaction: BarReactionEvent.fromJson(asMap(json['lastReaction'])),
        eliminated: asStringList(json['eliminated']),
      );

  final String status;
  final String currentPlayerId;

  /// The rank everybody at this table is claiming to hold.
  final CardRank? tableRank;

  final int roundNumber;

  /// Exactly how many of each face went into this round's shoe.
  ///
  /// Public, and the most important number on the screen: once the claims add
  /// up to more than the shoe can hold, somebody is lying and the arithmetic
  /// says so. See [claimedSoFar] and [honestCeilingFor].
  final Map<String, int> deckComposition;

  final List<BarSeat> seats;

  /// The local player's cards.
  final List<BarCard> hand;

  final int pileCount;

  /// Every claim this round, in order, so the table can count along.
  final List<BarClaim> claims;

  final BarClaim? lastClaim;
  final BarChallenge? lastChallenge;
  final BarShot? lastShot;
  final BarReactionEvent? lastReaction;
  final List<String> eliminated;

  bool get isPlaying => status == 'playing';
  bool get isOver => status == 'completed';

  bool isTurnOf(String playerId) =>
      isPlaying && currentPlayerId.isNotEmpty && currentPlayerId == playerId;

  BarSeat? seatOf(String playerId) {
    for (final BarSeat seat in seats) {
      if (seat.playerId == playerId) return seat;
    }
    return null;
  }

  /// Whether a card would be honest if claimed as the table rank.
  ///
  /// A joker is whatever the table is calling, which is what makes one worth
  /// holding on to.
  bool playsHonestly(BarCard entry) =>
      entry.card.isJoker || (tableRank != null && entry.card.rank == tableRank);

  /// The local player's honest cards, and the rest.
  List<BarCard> get honestCards =>
      <BarCard>[for (final BarCard entry in hand) if (playsHonestly(entry)) entry];

  List<BarCard> get lyingCards =>
      <BarCard>[for (final BarCard entry in hand) if (!playsHonestly(entry)) entry];

  /// How many cards have been claimed as the table rank so far this round.
  int get claimedSoFar =>
      claims.fold(0, (int total, BarClaim claim) => total + claim.count);

  /// The most that *could* honestly have been claimed by everybody but me.
  ///
  /// The shoe's supply of the table rank plus the jokers, less what is in my
  /// own hand. Once [claimedSoFar] passes it, somebody at this table is lying
  /// — and that is a fact, not a read.
  int honestCeilingFor(String selfId) {
    if (tableRank == null) return 0;
    final int supply = (deckComposition[tableRank!.wire] ?? 0) +
        (deckComposition['JOKER'] ?? 0);
    final int mine = honestCards.length;
    return (supply - mine).clamp(0, supply);
  }

  /// Whether the arithmetic already proves somebody has lied this round.
  bool liarIsCertain(String selfId) =>
      tableRank != null && claimedSoFar > honestCeilingFor(selfId);

  /// Whether [playerId] may call the standing claim.
  bool canChallenge(String playerId) =>
      isPlaying &&
      isTurnOf(playerId) &&
      lastClaim != null &&
      lastClaim!.playerId != playerId;

  /// Whether [playerId] may put cards down.
  bool canDeclare(String playerId) =>
      isPlaying && isTurnOf(playerId) && hand.isNotEmpty;
}
