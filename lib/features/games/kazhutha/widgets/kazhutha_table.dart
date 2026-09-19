import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/bot_chip.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/playing_card_view.dart';
import 'package:scribble_guess/models/games/kazhutha_state.dart';
import 'package:scribble_guess/models/games/playing_card.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// One seat's worth of everything the table needs to draw it.
///
/// Joins the two halves the server deliberately keeps apart: the *room* knows
/// who somebody is — name, avatar, whether they are a Stupid — and the *match*
/// knows what they are holding. Neither payload carries both, because the
/// roster outlives any one match, so they are joined here rather than by
/// widening either one.
@immutable
class KazhuthaTableSeat {
  const KazhuthaTableSeat({required this.player, required this.hand});

  final PlatformSeat player;
  final KazhuthaSeat hand;

  String get id => player.playerId;
}

/// The felt, drawn as felt.
///
/// An oval table inset from the edges with a darker rim, a sheen where the
/// lamp falls on it and a stitched border. It is three shapes and it is the
/// single thing that stops the screen reading as a UI with cards on it.
class KazhuthaFelt extends StatelessWidget {
  const KazhuthaFelt({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FeltPainter(skin: context.skin),
      size: Size.infinite,
    );
  }
}

class _FeltPainter extends CustomPainter {
  const _FeltPainter({required this.skin});

  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    // Wider than it is tall and pushed down the screen, so the near edge sits
    // behind the player's own hand exactly as a real table does.
    final Rect table = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.52),
      width: size.width * 0.94,
      height: size.height * 1.02,
    );

    final RRect body = RRect.fromRectAndRadius(
      table,
      Radius.circular(size.height * 0.34),
    );

    // The rail: the padded wooden edge a player rests their arms on.
    canvas.drawRRect(
      body.inflate(size.height * 0.022),
      Paint()..color = skin.edge.withValues(alpha: 0.85),
    );

    canvas.drawRRect(body, Paint()..color = skin.surface);

    // Baize has a nap, and the lamp above the table catches it in the middle.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 0.85,
          colors: <Color>[
            skin.surfaceRaised.withValues(alpha: 0.95),
            skin.surface.withValues(alpha: 0),
          ],
        ).createShader(table),
    );

    // The stitch line, inset from the rail like the one on a real table.
    canvas.drawRRect(
      body.deflate(size.height * 0.035),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = skin.accent.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(_FeltPainter oldDelegate) => oldDelegate.skin != skin;
}

/// One player around the table: who they are, and how many cards they hold.
///
/// Tapping it is how a draw begins, so the whole thing is the target rather
/// than some button inside it — a seat is a big obvious thing to reach for,
/// and on a phone in landscape the alternative is a 20-pixel icon.
class KazhuthaSeatView extends StatelessWidget {
  const KazhuthaSeatView({
    required this.seat,
    required this.isTurn,
    required this.isSelectable,
    required this.onTap,
    super.key,
  });

  final KazhuthaTableSeat seat;

  /// It is this seat's turn to draw. Haloed in the game's own light.
  final bool isTurn;

  /// The local player may draw from this seat right now.
  final bool isSelectable;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final bool out = seat.hand.isOut;

    return Semantics(
      button: isSelectable,
      label: '${seat.player.username}, ${seat.hand.cardCount} cards'
          '${seat.player.isBot ? ', a bot' : ''}'
          '${out ? ', out' : ''}',
      child: GestureDetector(
        onTap: isSelectable ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: AppMotion.normal,
          // Out is *safe*, not dead — so they fade back rather than greying
          // out entirely, and their finishing place is still shown.
          opacity: out ? 0.55 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _FaceDownFan(count: seat.hand.cardCount, metrics: metrics),
              SizedBox(height: metrics.gutter * 0.3),
              _Badge(
                seat: seat,
                isTurn: isTurn,
                isSelectable: isSelectable,
                skin: skin,
                metrics: metrics,
                text: text,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The little stack of backs above a seat.
///
/// Capped at five drawn cards however many are held, because the count is
/// written underneath and six overlapping backs at phone scale is a smudge.
/// The stack still *grows* up to that cap, so the difference between somebody
/// holding one card and somebody holding four is visible across the table —
/// which is the only read anybody has on anybody else.
class _FaceDownFan extends StatelessWidget {
  const _FaceDownFan({required this.count, required this.metrics});

  final int count;
  final GameMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final double height = metrics.cardHeight * 0.42;
    final double width = height * PlayingCardView.aspect;
    final int drawn = count.clamp(0, 5);
    final double overlap = width * 0.42;

    if (drawn == 0) {
      return SizedBox(height: height, width: width);
    }

    return SizedBox(
      height: height,
      width: width + overlap * (drawn - 1),
      child: Stack(
        children: <Widget>[
          for (int index = 0; index < drawn; index++)
            Positioned(
              left: overlap * index,
              child: PlayingCardView(card: null, height: height),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.seat,
    required this.isTurn,
    required this.isSelectable,
    required this.skin,
    required this.metrics,
    required this.text,
  });

  final KazhuthaTableSeat seat;
  final bool isTurn;
  final bool isSelectable;
  final GameSkin skin;
  final GameMetrics metrics;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.normal,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gutter * 0.55,
        vertical: metrics.gutter * 0.3,
      ),
      decoration: BoxDecoration(
        color: skin.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: isTurn
              ? skin.accent
              : isSelectable
                  ? skin.accent.withValues(alpha: 0.5)
                  : skin.edge,
          width: isTurn ? 2 : AppSpacing.border,
        ),
        boxShadow: isTurn
            ? <BoxShadow>[
                // The lamp picking out whoever is to act. Peripheral, so a
                // player looking at their own hand still registers it.
                BoxShadow(
                  color: skin.glow.withValues(alpha: 0.4),
                  blurRadius: 14 * metrics.scale,
                ),
              ]
            : null,
      ),
      // Six seats across a 640-point phone leaves about a hundred points each,
      // and an avatar beside a name beside a difficulty chip needs half as
      // much again. So the badge *reflows* rather than shrinking: side by side
      // where there is room, stacked where there is not. Shrinking would have
      // made every seat on every device smaller to fix the worst one.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 160 * metrics.scale;

          final Widget avatar = PlayerAvatar(
            avatarId: seat.player.avatarId,
            colorIndex: seat.player.avatarColorIndex,
            size: metrics.seatRadius,
            dimmed: !seat.player.connected,
          );

          final Widget name = Text(
            seat.player.username,
            overflow: TextOverflow.ellipsis,
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: text.labelMedium?.copyWith(
              color: skin.ink,
              fontWeight: FontWeight.w700,
            ),
          );

          final Widget status = Text(
            seat.hand.isOut
                ? _placeLabel(seat.hand.finishPosition)
                : '${seat.hand.cardCount} card${seat.hand.cardCount == 1 ? '' : 's'}',
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(
              color: seat.hand.isOut ? skin.success : skin.inkMuted,
              fontWeight: seat.hand.isOut ? FontWeight.w700 : FontWeight.w500,
            ),
          );

          if (!wide) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                avatar,
                SizedBox(height: metrics.gutter * 0.2),
                name,
                status,
                if (seat.player.isBot) BotChip(difficulty: seat.player.botDifficulty),
              ],
            );
          }

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              avatar,
              SizedBox(width: metrics.gutter * 0.4),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Flexible(child: name),
                        if (seat.player.isBot) ...<Widget>[
                          SizedBox(width: metrics.gutter * 0.3),
                          BotChip(difficulty: seat.player.botDifficulty),
                        ],
                      ],
                    ),
                    status,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Going out is winning, so it is announced as a placing and not as an exit.
  static String _placeLabel(int position) => switch (position) {
        1 => 'Safe — 1st out',
        2 => 'Safe — 2nd out',
        3 => 'Safe — 3rd out',
        <= 0 => 'Safe',
        _ => 'Safe — ${position}th out',
      };
}

/// The local player's hand, fanned along the bottom of the screen.
///
/// Fanned rather than laid in a row because a fan is what a hand of cards
/// looks like, and because the overlap lets ten cards fit across a phone
/// without shrinking each one below the size a rank can be read at. The fan
/// tightens as the hand grows rather than the cards getting smaller — which is
/// exactly what happens when somebody holds more cards than their hand is
/// comfortable with.
class KazhuthaHand extends StatelessWidget {
  const KazhuthaHand({
    required this.cards,
    required this.donkey,
    super.key,
  });

  final List<PlayingCard> cards;

  /// Which card is the donkey, so the one holding her can see it.
  final PlayingCard? donkey;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;
    final GameSkin skin = context.skin;

    if (cards.isEmpty) {
      return _OutOfCards(skin: skin, metrics: metrics);
    }

    final double height = metrics.cardHeight;
    final double width = height * PlayingCardView.aspect;

    // Spread tightens as the hand grows, so a big hand stays on screen.
    final double available = metrics.size.width * 0.78;
    final double ideal = width * 0.62;
    final double step = cards.length <= 1
        ? 0
        : math.min(ideal, (available - width) / (cards.length - 1));

    final double span = width + step * (cards.length - 1);
    final double centre = (cards.length - 1) / 2;

    return SizedBox(
      height: height * 1.22,
      width: span,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: <Widget>[
          for (int index = 0; index < cards.length; index++)
            Positioned(
              left: step * index,
              bottom: () {
                // A fanned hand arcs: the middle cards sit slightly higher.
                final double fromCentre = (index - centre).abs();
                return (centre == 0 ? 0 : (1 - fromCentre / centre)) * height * 0.06;
              }(),
              child: PlayingCardView(
                card: cards[index],
                height: height,
                highlighted: donkey != null && cards[index].id == donkey!.id,
                tilt: cards.length <= 1
                    ? 0
                    : (index - centre) / math.max(1, cards.length) * 0.30,
              ),
            ),
        ],
      ),
    );
  }
}

class _OutOfCards extends StatelessWidget {
  const _OutOfCards({required this.skin, required this.metrics});

  final GameSkin skin;
  final GameMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gutter * 1.5,
        vertical: metrics.gutter * 0.75,
      ),
      decoration: BoxDecoration(
        color: skin.success.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: skin.success, width: AppSpacing.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.check_circle_rounded, color: skin.success, size: 18 * metrics.scale),
          SizedBox(width: metrics.gutter * 0.5),
          Text(
            'You are out — and safe',
            style: text.labelLarge?.copyWith(
              color: skin.success,
              fontFamily: skin.display,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pairs everybody has laid down, stacked in the middle of the table.
///
/// Public information, exactly as at a real table, and the only thing a sharp
/// player can count: every rank showing here is a rank that can no longer pair
/// with anything in anybody's hand.
class KazhuthaDiscardPile extends StatelessWidget {
  const KazhuthaDiscardPile({required this.discards, super.key});

  final List<KazhuthaDiscard> discards;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    if (discards.isEmpty) {
      return Text(
        'No pairs down yet',
        style: text.labelSmall?.copyWith(color: skin.inkMuted),
      );
    }

    // Only the last few, fanned. The full history is a scoreboard, not a
    // table, and the interesting fact is what went down most recently.
    final List<KazhuthaDiscard> recent =
        discards.length <= 6 ? discards : discards.sublist(discards.length - 6);
    final double height = metrics.cardHeight * 0.55;
    final double step = height * 0.30;

    // The box has to be given a width as well as a height.
    //
    // Every child of the Stack below is `Positioned`, and a Stack whose
    // children are all positioned cannot size itself — so under an unbounded
    // constraint it throws rather than overflowing. This sits in a Row in the
    // middle of the felt, where width is unbounded, so without this the table
    // asserted the moment the first pair went down. Found by
    // `landscape_layout_test`; it is not a case a screenshot would show.
    final double span = height * PlayingCardView.aspect + step * (recent.length - 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: height,
          width: span,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              for (int index = 0; index < recent.length; index++)
                if (recent[index].cards.isNotEmpty)
                  Positioned(
                    left: index * step,
                    child: Transform.rotate(
                      // A laid pair is never square to the table.
                      angle: (index.isEven ? 1 : -1) * 0.06 * (index + 1),
                      child: PlayingCardView(
                        card: recent[index].cards.first,
                        height: height,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SizedBox(height: metrics.gutter * 0.4),
        Text(
          '${discards.length} pair${discards.length == 1 ? '' : 's'} down',
          style: text.labelSmall?.copyWith(color: skin.inkMuted),
        ),
      ],
    );
  }
}
