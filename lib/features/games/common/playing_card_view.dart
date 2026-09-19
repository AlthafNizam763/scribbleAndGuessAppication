import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/models/games/playing_card.dart';

/// A playing card, drawn rather than shipped as a bitmap.
///
/// ## Why this is a painter and not fifty-two PNGs
///
/// Partly convention — this repository already generates its launcher art and
/// its sound effects from code, for the reason given in
/// `tool/generate_brand_assets.dart`: art that is *described* can be diffed,
/// reviewed and adjusted, and art that is exported cannot. Mostly, though, it
/// is because a deck is the one thing in a card game that is pure geometry.
/// Fifty-two bitmaps would be four megabytes that scale badly on a tablet, and
/// changing the red would mean re-exporting all of them.
///
/// ## What makes it read as a real card
///
/// The details a player does not consciously notice and would immediately miss:
///
///  - **Corner indices, twice.** Rank over suit, top-left and again
///    bottom-right rotated 180°, so a card reads whichever way up it is held
///    and so a fanned hand can be read from its left edge alone.
///  - **The traditional pip layout.** Two through ten have fixed arrangements
///    that have not changed in two centuries, and the lower half is printed
///    upside down. A grid of evenly spaced pips looks wrong in a way that is
///    hard to place.
///  - **A warm white.** Pure white cards look like paper cut-outs. Real ones
///    are slightly ivory and have a rim.
class PlayingCardView extends StatelessWidget {
  const PlayingCardView({
    required this.card,
    required this.height,
    this.highlighted = false,
    this.dimmed = false,
    this.tilt = 0,
    super.key,
  });

  /// The card to draw. Null draws a face-down back.
  final PlayingCard? card;

  final double height;

  /// Lifts and rims the card — for a selection, or the donkey at the reveal.
  final bool highlighted;

  /// Greys it back, for a card that cannot be acted on.
  final bool dimmed;

  /// Rotation in radians, for a fanned hand.
  final double tilt;

  /// The poker ratio. A card that is not this shape does not read as a card.
  static const double aspect = 0.68;

  double get width => height * aspect;

  @override
  Widget build(BuildContext context) {
    final Widget face = SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _CardPainter(card: card, highlighted: highlighted),
        isComplex: true,
        willChange: false,
      ),
    );

    final Widget shaded = dimmed
        ? ColorFiltered(
            colorFilter: const ColorFilter.mode(Color(0x66101010), BlendMode.srcATop),
            child: face,
          )
        : face;

    if (tilt == 0) return shaded;
    return Transform.rotate(alignment: Alignment.bottomCenter, angle: tilt, child: shaded);
  }
}

class _CardPainter extends CustomPainter {
  const _CardPainter({required this.card, required this.highlighted});

  final PlayingCard? card;
  final bool highlighted;

  /// Ivory, not white. See the class comment.
  static const Color _face = Color(0xFFF7F3E8);
  static const Color _rim = Color(0xFFD8CFB8);
  static const Color _red = Color(0xFFC0302B);
  static const Color _black = Color(0xFF1B1B1F);

  /// The back's two inks.
  static const Color _backInk = Color(0xFF7E2B2B);
  static const Color _backInkDeep = Color(0xFF4E1A1A);

  @override
  void paint(Canvas canvas, Size size) {
    final RRect body = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.085),
    );

    // A card sitting on a table has a shadow under it, and a fanned hand is
    // legible mostly because of the shadows between the cards.
    canvas.drawRRect(
      body.shift(const Offset(0, 1.5)),
      Paint()
        ..color = const Color(0x4D000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    if (card == null) {
      _paintBack(canvas, size, body);
    } else {
      canvas.drawRRect(body, Paint()..color = _face);
      _paintFace(canvas, size, card!);
    }

    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = highlighted ? const Color(0xFFD9A441) : _rim,
    );

    if (highlighted) {
      canvas.drawRRect(
        body.deflate(2.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xCCD9A441),
      );
    }
  }

  // ------------------------------------------------------------------ back --

  /// The back: a lattice inside a border, which is what almost every real deck
  /// does and why a face-down card reads as a card rather than a blank.
  void _paintBack(Canvas canvas, Size size, RRect body) {
    canvas.drawRRect(body, Paint()..color = _backInkDeep);

    final RRect panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.07,
        size.height * 0.05,
        size.width * 0.86,
        size.height * 0.9,
      ),
      Radius.circular(size.width * 0.055),
    );
    canvas.drawRRect(panel, Paint()..color = _backInk);

    canvas.save();
    canvas.clipRRect(panel);

    final Paint thread = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = const Color(0x59F7F3E8);

    // A diagonal lattice, stepped off the card's own width so it is the same
    // density at every size.
    final double step = size.width * 0.16;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), thread);
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), thread);
    }
    canvas.restore();

    canvas.drawRRect(
      panel.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x99F7F3E8),
    );
  }

  // ------------------------------------------------------------------ face --

  void _paintFace(Canvas canvas, Size size, PlayingCard card) {
    final Color ink = card.isBlack ? _black : _red;

    if (card.isJoker) {
      _paintJoker(canvas, size);
      return;
    }

    _paintIndex(canvas, size, card, ink);

    if (card.rank!.isCourt) {
      _paintCourt(canvas, size, card, ink);
      return;
    }

    for (final Offset spot in _pipLayout(card.rank!)) {
      _paintPip(
        canvas,
        size,
        card.suit!.pip,
        ink,
        spot,
        size.width * 0.19,
        // The lower half of a real card is printed upside down.
        inverted: spot.dy > 0.52,
      );
    }
  }

  /// Rank over suit, in both diagonal corners.
  void _paintIndex(Canvas canvas, Size size, PlayingCard card, Color ink) {
    final double rankSize = size.width * 0.235;
    final double pipSize = size.width * 0.17;

    void corner(Offset origin, bool inverted) {
      canvas.save();
      if (inverted) {
        canvas.translate(size.width, size.height);
        canvas.rotate(math.pi);
      }

      _text(canvas, card.rank!.label, rankSize, ink, origin, FontWeight.w700);
      _text(
        canvas,
        card.suit!.pip,
        pipSize,
        ink,
        Offset(origin.dx, origin.dy + rankSize * 0.98),
        FontWeight.w400,
      );
      canvas.restore();
    }

    final Offset origin = Offset(size.width * 0.085, size.height * 0.045);
    corner(origin, false);
    corner(origin, true);
  }

  /// A court card gets a panel and a large letter rather than a portrait.
  ///
  /// Drawing a credible jack is a week of vector work and would still look
  /// out of place beside everything else in this app. A bordered panel with
  /// the rank and suit large is what a minimalist deck does, and it stays
  /// readable at the size a phone actually renders a card.
  void _paintCourt(Canvas canvas, Size size, PlayingCard card, Color ink) {
    final RRect panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.21,
        size.height * 0.18,
        size.width * 0.58,
        size.height * 0.64,
      ),
      Radius.circular(size.width * 0.05),
    );

    canvas.drawRRect(panel, Paint()..color = ink.withValues(alpha: 0.07));
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = ink.withValues(alpha: 0.55),
    );

    _centred(canvas, card.rank!.label, size.width * 0.38, ink,
        Offset(size.width / 2, size.height * 0.40), FontWeight.w700);
    _centred(canvas, card.suit!.pip, size.width * 0.26, ink,
        Offset(size.width / 2, size.height * 0.64), FontWeight.w400);
  }

  void _paintJoker(Canvas canvas, Size size) {
    _centred(canvas, '★', size.width * 0.42, _red,
        Offset(size.width / 2, size.height * 0.40), FontWeight.w400);
    _centred(canvas, 'JOKER', size.width * 0.15, _black,
        Offset(size.width / 2, size.height * 0.68), FontWeight.w700);
  }

  void _paintPip(
    Canvas canvas,
    Size size,
    String pip,
    Color ink,
    Offset unit,
    double glyph, {
    required bool inverted,
  }) {
    final Offset spot = Offset(unit.dx * size.width, unit.dy * size.height);
    canvas.save();
    canvas.translate(spot.dx, spot.dy);
    if (inverted) canvas.rotate(math.pi);
    _centred(canvas, pip, glyph, ink, Offset.zero, FontWeight.w400);
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String value,
    double fontSize,
    Color ink,
    Offset at,
    FontWeight weight,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: ink,
          fontSize: fontSize,
          fontWeight: weight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  void _centred(
    Canvas canvas,
    String value,
    double fontSize,
    Color ink,
    Offset centre,
    FontWeight weight,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: ink,
          fontSize: fontSize,
          fontWeight: weight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
    );
  }

  /// The traditional arrangement for each rank, in unit coordinates.
  ///
  /// These are not evenly spaced and are not meant to be: they are the layout
  /// that has been printed on cards for two hundred years, and a regular grid
  /// is the single thing that makes a hand-drawn deck look wrong.
  static List<Offset> _pipLayout(CardRank rank) {
    const double left = 0.30;
    const double right = 0.70;
    const double mid = 0.50;

    const double top = 0.235;
    const double upper = 0.385;
    const double centre = 0.50;
    const double lower = 0.615;
    const double bottom = 0.765;

    return switch (rank) {
      CardRank.ace => const <Offset>[Offset(mid, centre)],
      CardRank.two => const <Offset>[Offset(mid, top), Offset(mid, bottom)],
      CardRank.three => const <Offset>[
          Offset(mid, top),
          Offset(mid, centre),
          Offset(mid, bottom),
        ],
      CardRank.four => const <Offset>[
          Offset(left, top),
          Offset(right, top),
          Offset(left, bottom),
          Offset(right, bottom),
        ],
      CardRank.five => const <Offset>[
          Offset(left, top),
          Offset(right, top),
          Offset(mid, centre),
          Offset(left, bottom),
          Offset(right, bottom),
        ],
      CardRank.six => const <Offset>[
          Offset(left, top),
          Offset(right, top),
          Offset(left, centre),
          Offset(right, centre),
          Offset(left, bottom),
          Offset(right, bottom),
        ],
      // Seven and eight add pips *between* the rows, which is the detail that
      // makes them look printed rather than generated.
      CardRank.seven => const <Offset>[
          Offset(left, top),
          Offset(right, top),
          Offset(mid, upper),
          Offset(left, centre),
          Offset(right, centre),
          Offset(left, bottom),
          Offset(right, bottom),
        ],
      CardRank.eight => const <Offset>[
          Offset(left, top),
          Offset(right, top),
          Offset(mid, upper),
          Offset(left, centre),
          Offset(right, centre),
          Offset(mid, lower),
          Offset(left, bottom),
          Offset(right, bottom),
        ],
      CardRank.nine => const <Offset>[
          Offset(left, top),
          Offset(right, top),
          Offset(left, upper),
          Offset(right, upper),
          Offset(mid, centre),
          Offset(left, lower),
          Offset(right, lower),
          Offset(left, bottom),
          Offset(right, bottom),
        ],
      CardRank.ten => const <Offset>[
          Offset(left, top),
          Offset(right, top),
          Offset(mid, upper),
          Offset(left, upper),
          Offset(right, upper),
          Offset(left, lower),
          Offset(right, lower),
          Offset(mid, lower),
          Offset(left, bottom),
          Offset(right, bottom),
        ],
      _ => const <Offset>[],
    };
  }

  @override
  bool shouldRepaint(_CardPainter oldDelegate) =>
      oldDelegate.card?.id != card?.id || oldDelegate.highlighted != highlighted;
}
