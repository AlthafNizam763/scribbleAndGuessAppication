import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/bot_chip.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/playing_card_view.dart';
import 'package:scribble_guess/models/games/bluff_bar_state.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// One seat at the bar, joined from the room roster and the match projection.
@immutable
class BarTableSeat {
  const BarTableSeat({required this.player, required this.seat});

  final PlatformSeat player;
  final BarSeat seat;

  String get id => player.playerId;
}

/// The back room: bare boards, one hanging bulb, a scarred table.
///
/// ## What makes it read as a bar rather than a card game in the dark
///
/// The light. There is exactly one source, it is low and directly over the
/// middle of the table, and everything falls off sharply from it — so the
/// players at the far side are dimmer than the cards in the middle, and the
/// corners of the screen are nearly black. A card room is evenly lit; a back
/// room is not, and that difference is most of the atmosphere.
///
/// The rest is the table itself: dark wood rather than baize, a worn ring
/// where glasses have stood, and a rim that catches the bulb.
class BluffBarRoom extends StatelessWidget {
  const BluffBarRoom({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RoomPainter(skin: context.skin),
      size: Size.infinite,
    );
  }
}

class _RoomPainter extends CustomPainter {
  const _RoomPainter({required this.skin});

  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset bulb = Offset(size.width / 2, size.height * 0.06);

    // The cone of light from the bulb, before anything is drawn in it.
    final Path cone = Path()
      ..moveTo(bulb.dx - size.width * 0.04, bulb.dy)
      ..lineTo(bulb.dx - size.width * 0.42, size.height)
      ..lineTo(bulb.dx + size.width * 0.42, size.height)
      ..lineTo(bulb.dx + size.width * 0.04, bulb.dy)
      ..close();

    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            skin.glow.withValues(alpha: 0.14),
            skin.glow.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    // The table: an ellipse of dark wood, pushed low so the near edge sits
    // behind the player's own cards.
    final Rect table = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.60),
      width: size.width * 0.86,
      height: size.height * 0.82,
    );
    final RRect body = RRect.fromRectAndRadius(
      table,
      Radius.circular(size.height * 0.30),
    );

    canvas.drawRRect(
      body.inflate(size.height * 0.018),
      Paint()..color = skin.edge.withValues(alpha: 0.9),
    );
    canvas.drawRRect(body, Paint()..color = skin.surface);

    // The bulb falling on the middle of the table.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 0.8,
          colors: <Color>[
            skin.surfaceRaised,
            skin.surface.withValues(alpha: 0),
          ],
        ).createShader(table),
    );

    // Rings where glasses have stood. Three, off-centre, faint — the detail
    // that says people have been drinking at this table for years.
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = skin.accent.withValues(alpha: 0.10);
    for (final (double dx, double dy, double r) in <(double, double, double)>[
      (-0.26, 0.10, 0.045),
      (0.30, -0.08, 0.038),
      (0.12, 0.22, 0.05),
    ]) {
      canvas.drawCircle(
        table.center + Offset(table.width * dx, table.height * dy),
        size.height * r,
        ring,
      );
    }

    // The bulb itself, hanging in from the top of the frame.
    canvas.drawLine(
      Offset(bulb.dx, 0),
      bulb,
      Paint()
        ..strokeWidth = 1.2
        ..color = skin.edge,
    );
    canvas.drawCircle(bulb, size.height * 0.022, Paint()..color = skin.glow);
    canvas.drawCircle(
      bulb,
      size.height * 0.07,
      Paint()
        ..color = skin.glow.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  @override
  bool shouldRepaint(_RoomPainter oldDelegate) => oldDelegate.skin != skin;
}

/// The tray of glasses in front of one player.
///
/// ## Why this is the most important widget on the screen
///
/// It is the risk, made literal. Six glasses means a lost call costs one in
/// six; one glass means a lost call is the end. A player deciding whether to
/// call a claim they are not sure about is really deciding whether they can
/// afford to be wrong, and this is the thing they look at to decide.
///
/// Drawn as glasses rather than as a number for exactly that reason: "3" is a
/// fact, and three glasses standing where there were six is a feeling.
class ShotTray extends StatelessWidget {
  const ShotTray({
    required this.remaining,
    required this.total,
    this.compact = false,
    super.key,
  });

  final int remaining;
  final int total;

  /// Smaller, for an opponent's seat rather than the player's own.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final double height = (compact ? 13 : 22) * metrics.scale;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int index = 0; index < total; index++)
          Padding(
            padding: EdgeInsets.only(right: (compact ? 1.5 : 3) * metrics.scale),
            child: CustomPaint(
              size: Size(height * 0.62, height),
              painter: _GlassPainter(
                filled: index < remaining,
                // The last one standing is not a gamble, and it is drawn as a
                // warning rather than as another glass.
                terminal: remaining == 1 && index == 0,
                skin: skin,
              ),
            ),
          ),
      ],
    );
  }
}

class _GlassPainter extends CustomPainter {
  const _GlassPainter({
    required this.filled,
    required this.terminal,
    required this.skin,
  });

  final bool filled;
  final bool terminal;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    // A shot glass: slightly tapered, heavier at the base.
    final Path glass = Path()
      ..moveTo(size.width * 0.12, 0)
      ..lineTo(size.width * 0.88, 0)
      ..lineTo(size.width * 0.76, size.height)
      ..lineTo(size.width * 0.24, size.height)
      ..close();

    final Color tint = terminal ? skin.danger : skin.accent;

    if (filled) {
      canvas.drawPath(glass, Paint()..color = tint.withValues(alpha: 0.55));
      // The liquid line, which is what makes it read as full rather than solid.
      canvas.drawLine(
        Offset(size.width * 0.16, size.height * 0.30),
        Offset(size.width * 0.84, size.height * 0.30),
        Paint()
          ..strokeWidth = 1
          ..color = tint,
      );
    }

    canvas.drawPath(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = filled ? tint : skin.inkMuted.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) =>
      oldDelegate.filled != filled || oldDelegate.terminal != terminal;
}

/// One opponent across the table: who they are, what they are holding, and how
/// much they have left to lose.
class BarSeatView extends StatelessWidget {
  const BarSeatView({
    required this.seat,
    required this.isTurn,
    required this.isClaimant,
    required this.reaction,
    super.key,
  });

  final BarTableSeat seat;
  final bool isTurn;

  /// They made the claim currently standing. Rimmed, because they are the one
  /// who can be called.
  final bool isClaimant;

  /// Their most recent reaction, if it was recent enough to still show.
  final BarReaction? reaction;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final bool dead = !seat.seat.alive;

    return AnimatedOpacity(
      duration: AppMotion.normal,
      opacity: dead ? 0.35 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _FaceDownCards(count: seat.seat.cardCount, metrics: metrics),
          SizedBox(height: metrics.gutter * 0.3),

          AnimatedContainer(
            duration: AppMotion.normal,
            padding: EdgeInsets.symmetric(
              horizontal: metrics.gutter * 0.5,
              vertical: metrics.gutter * 0.28,
            ),
            decoration: BoxDecoration(
              color: skin.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: isClaimant
                    ? skin.danger
                    : isTurn
                        ? skin.accent
                        : skin.edge,
                width: isTurn || isClaimant ? 2 : AppSpacing.border,
              ),
              boxShadow: isTurn
                  ? <BoxShadow>[
                      BoxShadow(
                        color: skin.glow.withValues(alpha: 0.35),
                        blurRadius: 14 * metrics.scale,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        PlayerAvatar(
                          avatarId: seat.player.avatarId,
                          colorIndex: seat.player.avatarColorIndex,
                          size: metrics.seatRadius,
                          dimmed: !seat.player.connected || dead,
                        ),
                        if (reaction != null)
                          Positioned(
                            right: -6,
                            top: -8,
                            child: _ReactionBubble(reaction: reaction!),
                          ),
                      ],
                    ),
                    SizedBox(width: metrics.gutter * 0.4),
                    // Flexible, not fixed. Six drinkers across a phone leaves
                    // about a hundred points each, and a name plus a
                    // difficulty chip wants more — so the name ellipsizes into
                    // whatever is actually left rather than the row running
                    // off the edge of the table.
                    Flexible(
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // The name gets the whole width, and the BOT chip
                        // takes its own line underneath.
                        //
                        // Side by side, the chip alone ("BOT · NORMAL") is
                        // most of the room a seat has on a phone with six
                        // drinkers at the table, which left nothing for the
                        // name. Stacking costs one line of height, which this
                        // badge has, and buys back the horizontal space,
                        // which it does not.
                        Text(
                          seat.player.username,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(
                            color: dead ? skin.inkMuted : skin.ink,
                            fontWeight: FontWeight.w700,
                            decoration:
                                dead ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (seat.player.isBot)
                          BotChip(difficulty: seat.player.botDifficulty),
                        SizedBox(height: 2 * metrics.scale),
                        if (dead)
                          Text(
                            'Out',
                            style: text.labelSmall?.copyWith(color: skin.danger),
                          )
                        else
                          ShotTray(
                            remaining: seat.seat.glassesRemaining,
                            total: 6,
                            compact: true,
                          ),
                      ],
                    ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceDownCards extends StatelessWidget {
  const _FaceDownCards({required this.count, required this.metrics});

  final int count;
  final GameMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final double height = metrics.cardHeight * 0.38;
    final double width = height * PlayingCardView.aspect;
    final int drawn = count.clamp(0, 5);
    final double overlap = width * 0.45;

    if (drawn == 0) {
      final GameSkin skin = context.skin;
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'empty',
            style: TextStyle(
              color: skin.inkMuted,
              fontSize: 9 * metrics.scale,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
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

class _ReactionBubble extends StatelessWidget {
  const _ReactionBubble({required this.reaction});

  final BarReaction reaction;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;

    return Container(
      padding: EdgeInsets.all(3 * metrics.scale),
      decoration: BoxDecoration(
        color: skin.surfaceRaised,
        shape: BoxShape.circle,
        border: Border.all(color: skin.accent, width: 1),
      ),
      child: Text(
        reaction.glyph,
        style: TextStyle(fontSize: 11 * metrics.scale),
      ),
    );
  }
}

/// The local player's hand, with the honest cards marked.
///
/// ## Why the honest ones are marked
///
/// Because the player can see their own cards, and working out which of them
/// match the called rank is bookkeeping rather than skill — especially with
/// jokers, which count as anything. Marking them removes a clerical step and
/// changes no decision: the interesting question was never "which of these are
/// aces", it is "how many am I prepared to claim I have".
class BluffBarHand extends StatelessWidget {
  const BluffBarHand({
    required this.cards,
    required this.selected,
    required this.isHonest,
    required this.enabled,
    required this.onToggle,
    super.key,
  });

  final List<BarCard> cards;
  final Set<String> selected;

  /// Whether a given card would be honest if claimed. Decided by the state.
  final bool Function(BarCard) isHonest;

  final bool enabled;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;
    final GameSkin skin = context.skin;

    if (cards.isEmpty) {
      final TextTheme text = Theme.of(context).textTheme;
      return Text(
        'Out of cards — safe until the round ends',
        style: text.labelMedium?.copyWith(color: skin.inkMuted),
      );
    }

    final double height = metrics.cardHeight;
    final double width = height * PlayingCardView.aspect;
    final double available = metrics.size.width * 0.66;
    final double step = cards.length <= 1
        ? 0
        : math.min(width * 0.78, (available - width) / (cards.length - 1));

    return SizedBox(
      height: height * 1.3,
      width: width + step * math.max(0, cards.length - 1),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (int index = 0; index < cards.length; index++)
            Positioned(
              left: step * index,
              bottom: 0,
              child: _HandCard(
                entry: cards[index],
                honest: isHonest(cards[index]),
                selected: selected.contains(cards[index].id),
                enabled: enabled,
                height: height,
                onTap: () => onToggle(cards[index].id),
              ),
            ),
        ],
      ),
    );
  }
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    required this.entry,
    required this.honest,
    required this.selected,
    required this.enabled,
    required this.height,
    required this.onTap,
  });

  final BarCard entry;
  final bool honest;
  final bool selected;
  final bool enabled;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        // Selected cards lift out of the hand, which is what putting a card
        // forward looks like and how a player checks what they are about to
        // commit to before they commit to it.
        transform: Matrix4.translationValues(0, selected ? -18 * metrics.scale : 0, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // A quiet tick above the honest ones. Not a colour on the card
            // itself: the cards have to stay readable as cards.
            SizedBox(
              height: 12 * metrics.scale,
              child: honest
                  ? Icon(
                      Icons.check_circle_rounded,
                      size: 11 * metrics.scale,
                      color: skin.success,
                    )
                  : null,
            ),
            PlayingCardView(
              card: entry.card,
              height: height,
              highlighted: selected,
              dimmed: !enabled,
            ),
          ],
        ),
      ),
    );
  }
}
