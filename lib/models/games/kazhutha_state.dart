import 'package:flutter/foundation.dart';
import 'package:scribble_guess/models/games/playing_card.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// One seat at the Kazhutha table, as this viewer is allowed to see it.
///
/// Note what is **not** here: anybody else's cards. The server sends a count
/// and nothing more, which is why a client cannot show a fan face-up even if
/// it wanted to — it has never been told what is in one.
@immutable
class KazhuthaSeat {
  const KazhuthaSeat({
    required this.playerId,
    required this.cardCount,
    required this.isOut,
    required this.finishPosition,
  });

  factory KazhuthaSeat.fromJson(Map<String, dynamic> json) => KazhuthaSeat(
        playerId: asString(json['playerId']),
        cardCount: asInt(json['cardCount']),
        isOut: asBool(json['out']),
        finishPosition: asInt(json['finishPosition']),
      );

  final String playerId;

  /// How many cards they hold. The only thing visible about another hand.
  final int cardCount;

  /// Out of the game — and *safe*. Going out is how Kazhutha is won.
  final bool isOut;

  /// 1 for the first player to go out, 0 while still holding cards.
  final int finishPosition;

  /// Whether this seat can legally be drawn from right now.
  bool get isDrawable => !isOut && cardCount > 0;
}

/// A pair somebody laid down, face up, where everybody can count it.
@immutable
class KazhuthaDiscard {
  const KazhuthaDiscard({
    required this.playerId,
    required this.rank,
    required this.cards,
    required this.atMs,
  });

  factory KazhuthaDiscard.fromJson(Map<String, dynamic> json) => KazhuthaDiscard(
        playerId: asString(json['playerId']),
        rank: CardRank.fromWire(asString(json['rank'])),
        cards: <PlayingCard>[
          for (final Object? id in asList(json['cards']))
            if (PlayingCard.parse(asString(id)) case final PlayingCard card) card,
        ],
        atMs: asInt(json['atMs']),
      );

  final String playerId;
  final CardRank? rank;
  final List<PlayingCard> cards;
  final int atMs;
}

/// The last draw anybody made, for the animation and the running commentary.
@immutable
class KazhuthaDraw {
  const KazhuthaDraw({
    required this.playerId,
    required this.targetId,
    required this.cardIndex,
    required this.paired,
    required this.pairedRanks,
    required this.atMs,
  });

  static KazhuthaDraw? fromJson(Map<String, dynamic> json) {
    final String playerId = asString(json['playerId']);
    if (playerId.isEmpty) return null;

    return KazhuthaDraw(
      playerId: playerId,
      targetId: asString(json['targetId']),
      cardIndex: asInt(json['cardIndex']),
      paired: asBool(json['paired']),
      pairedRanks: <CardRank>[
        for (final Object? value in asList(json['pairedRanks']))
          if (CardRank.fromWire(asString(value)) case final CardRank rank) rank,
      ],
      atMs: asInt(json['atMs']),
    );
  }

  final String playerId;
  final String targetId;

  /// Which position in the fan was reached for. Cosmetic by design — the
  /// server reshuffles the target's hand immediately before the pick — but it
  /// is the real position, so the animation flies the right card.
  final int cardIndex;

  /// Whether the drawn card paired off and went straight onto the table.
  final bool paired;
  final List<CardRank> pairedRanks;
  final int atMs;
}

/// Everything a Kazhutha screen needs, parsed from one projection.
///
/// ## What this is a view of
///
/// The server's `getPrivatePlayerState` output for *this seat*. It is not the
/// match and never can be: `hand` is the local player's, and no other hand
/// exists anywhere in the payload. A field that is missing is a field this
/// player is not entitled to, so the correct response to one is to draw
/// nothing rather than to guess.
@immutable
class KazhuthaState {
  const KazhuthaState({
    required this.status,
    required this.currentPlayerId,
    required this.donkeyCard,
    required this.seats,
    required this.hand,
    required this.discards,
    required this.finishOrder,
    required this.lastDraw,
    required this.kazhuthaId,
  });

  /// The empty table, before the first projection arrives.
  static const KazhuthaState empty = KazhuthaState(
    status: '',
    currentPlayerId: '',
    donkeyCard: null,
    seats: <KazhuthaSeat>[],
    hand: <PlayingCard>[],
    discards: <KazhuthaDiscard>[],
    finishOrder: <String>[],
    lastDraw: null,
    kazhuthaId: '',
  );

  factory KazhuthaState.fromJson(Map<String, dynamic> json) => KazhuthaState(
        status: asString(json['status']),
        currentPlayerId: asString(json['currentPlayerId']),
        donkeyCard: PlayingCard.parse(asString(json['donkeyCard'])),
        seats: <KazhuthaSeat>[
          for (final Object? row in asList(json['players']))
            if (row is Map) KazhuthaSeat.fromJson(asMap(row)),
        ],
        hand: <PlayingCard>[
          for (final Object? id in asList(json['hand']))
            if (PlayingCard.parse(asString(id)) case final PlayingCard card) card,
        ],
        discards: <KazhuthaDiscard>[
          for (final Object? row in asList(json['discards']))
            if (row is Map) KazhuthaDiscard.fromJson(asMap(row)),
        ],
        finishOrder: asStringList(json['finishOrder']),
        lastDraw: KazhuthaDraw.fromJson(asMap(json['lastAction'])),
        kazhuthaId: asString(json['kazhuthaId']),
      );

  final String status;

  /// Whose turn it is. Empty between a match ending and the next starting.
  final String currentPlayerId;

  /// Which card is the donkey — common knowledge, exactly as at a real table.
  /// Who is *holding* her is not, and is not in this object.
  final PlayingCard? donkeyCard;

  final List<KazhuthaSeat> seats;

  /// The local player's hand, sorted as the server arranged it.
  final List<PlayingCard> hand;

  /// Every pair laid down so far, oldest first. The only countable
  /// information in the game.
  final List<KazhuthaDiscard> discards;

  /// Who went out, best first.
  final List<String> finishOrder;

  final KazhuthaDraw? lastDraw;

  /// Set only once the match is over: whoever was left holding her.
  final String kazhuthaId;

  bool get isPlaying => status == 'playing';
  bool get isOver => status == 'completed';

  /// Whether it is [playerId]'s turn to draw.
  bool isTurnOf(String playerId) =>
      isPlaying && currentPlayerId.isNotEmpty && currentPlayerId == playerId;

  KazhuthaSeat? seatOf(String playerId) {
    for (final KazhuthaSeat seat in seats) {
      if (seat.playerId == playerId) return seat;
    }
    return null;
  }

  /// Everybody [viewerId] may legally draw from this turn.
  ///
  /// Derived from the same projection the server validates against, so the
  /// table can grey out a seat rather than offering a tap that will be
  /// refused. It is a courtesy, not a rule: the server checks it again.
  List<KazhuthaSeat> drawableBy(String viewerId) => <KazhuthaSeat>[
        for (final KazhuthaSeat seat in seats)
          if (seat.playerId != viewerId && seat.isDrawable) seat,
      ];

  /// How many cards are still in play across the whole table.
  int get cardsInPlay =>
      seats.fold(0, (int total, KazhuthaSeat seat) => total + seat.cardCount);
}
