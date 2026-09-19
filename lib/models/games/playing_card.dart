import 'package:flutter/foundation.dart';

/// The four suits, and what a card table calls them.
enum CardSuit {
  spades('S', '♠', true),
  hearts('H', '♥', false),
  diamonds('D', '♦', false),
  clubs('C', '♣', true);

  const CardSuit(this.wire, this.pip, this.isBlack);

  final String wire;

  /// The glyph printed in the corner. Unicode rather than an asset: it is in
  /// every font the app ships, it scales to any card size without a second
  /// bitmap, and it is what a suit actually is.
  final String pip;

  /// Spades and clubs are black; hearts and diamonds are red. The single most
  /// important thing about a card after its rank, and the reason a player can
  /// read a fanned hand at a glance.
  final bool isBlack;

  static CardSuit? fromWire(String value) {
    for (final CardSuit suit in values) {
      if (suit.wire == value) return suit;
    }
    return null;
  }
}

/// Ranks, low to high, as they are printed.
///
/// `T` on the wire and `10` on the card: the server keeps every id two
/// characters wide so nothing has to parse them, and the table shows what a
/// real ten shows. That translation lives here and nowhere else.
enum CardRank {
  two('2', '2'),
  three('3', '3'),
  four('4', '4'),
  five('5', '5'),
  six('6', '6'),
  seven('7', '7'),
  eight('8', '8'),
  nine('9', '9'),
  ten('T', '10'),
  jack('J', 'J'),
  queen('Q', 'Q'),
  king('K', 'K'),
  ace('A', 'A');

  const CardRank(this.wire, this.label);

  final String wire;
  final String label;

  /// Whether this rank is drawn with a face rather than a column of pips.
  bool get isCourt =>
      this == CardRank.jack || this == CardRank.queen || this == CardRank.king;

  static CardRank? fromWire(String value) {
    for (final CardRank rank in values) {
      if (rank.wire == value) return rank;
    }
    return null;
  }
}

/// One playing card, parsed from the server's two-character id.
///
/// ## Why a model and not just the string
///
/// Because everything that draws a card needs the rank, the suit and the
/// colour, and doing `card[0]` and `card[1]` at each of those call sites is
/// how a ten ends up rendered as a `T` on one screen and a `10` on another.
/// Parsing once, here, also means a malformed id fails in one place instead of
/// producing a card with no suit halfway through a fan.
///
/// A joker has neither rank nor suit and is drawn as itself.
@immutable
class PlayingCard {
  const PlayingCard({required this.id, required this.rank, required this.suit});

  /// Parses `<rank><suit>` — `AS`, `TD`, `QS` — or a joker, `X1` / `X2`.
  ///
  /// Returns `null` for anything else. A caller rendering a hand should drop
  /// an unparseable card rather than substitute one, because a card that is
  /// not what the server dealt is worse than a gap.
  static PlayingCard? parse(String id) {
    if (id.length != 2) return null;
    if (id.startsWith('X')) {
      return PlayingCard(id: id, rank: null, suit: null);
    }

    final CardRank? rank = CardRank.fromWire(id[0]);
    final CardSuit? suit = CardSuit.fromWire(id[1]);
    if (rank == null || suit == null) return null;

    return PlayingCard(id: id, rank: rank, suit: suit);
  }

  /// The id exactly as the server sent it. This is what goes back on the wire.
  final String id;

  /// `null` on a joker.
  final CardRank? rank;

  /// `null` on a joker.
  final CardSuit? suit;

  bool get isJoker => rank == null || suit == null;

  /// Black unless it is a heart or a diamond. Jokers are black.
  bool get isBlack => suit?.isBlack ?? true;

  /// What a player would call it out loud.
  String get spoken {
    if (isJoker) return 'the joker';
    const Map<CardSuit, String> names = <CardSuit, String>{
      CardSuit.spades: 'spades',
      CardSuit.hearts: 'hearts',
      CardSuit.diamonds: 'diamonds',
      CardSuit.clubs: 'clubs',
    };
    const Map<CardRank, String> ranks = <CardRank, String>{
      CardRank.jack: 'jack',
      CardRank.queen: 'queen',
      CardRank.king: 'king',
      CardRank.ace: 'ace',
    };
    final String face = ranks[rank!] ?? rank!.label;
    return '$face of ${names[suit!]}';
  }

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}
