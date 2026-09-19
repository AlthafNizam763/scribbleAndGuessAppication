import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/bluff_bar/widgets/bluff_bar_table.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/playing_card_view.dart';
import 'package:scribble_guess/models/games/bluff_bar_state.dart';
import 'package:scribble_guess/models/games/playing_card.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The moment somebody pays to see the cards.
///
/// ## Why this is a takeover and not a toast
///
/// It is the only thing that happens in Bluff Bar. Every claim, every bluff
/// and every held nerve is building towards one of these, and it resolves in
/// about a second — so it gets the middle of the screen, the cards turn over
/// one at a time, and the tray is shown emptying by one. A line of text
/// sliding in at the corner would throw away the entire payoff.
///
/// The cards flip in sequence rather than together for the same reason a
/// dealer turns them one at a time: with three cards claimed and two of them
/// honest, the third is the whole story, and revealing it last is what makes
/// the table lean in.
class BluffBarReveal extends StatefulWidget {
  const BluffBarReveal({
    required this.challenge,
    required this.shot,
    required this.tableRank,
    required this.room,
    required this.selfId,
    super.key,
  });

  final BarChallenge challenge;
  final BarShot? shot;
  final CardRank? tableRank;
  final PlatformRoom? room;
  final String selfId;

  @override
  State<BluffBarReveal> createState() => _BluffBarRevealState();
}

class _BluffBarRevealState extends State<BluffBarReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Long enough to turn three cards and let the verdict land, short enough
    // that the next round is not held up by an animation.
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didUpdateWidget(BluffBarReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A *new* call, not a rebuild of the same one. Restarting on every rebuild
    // would make the reveal stutter every time chat opened behind it.
    if (oldWidget.challenge.atMs != widget.challenge.atMs) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final BarChallenge challenge = widget.challenge;
    final String caller = _nameOf(challenge.challengerId);
    final String claimant = _nameOf(challenge.claimantId);
    final bool loserIsMe = challenge.loserId == widget.selfId;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final double t = _controller.value;

        // Fades out at the end rather than vanishing, so the table underneath
        // is visible again before the next claim is made on it.
        final double opacity = t < 0.88 ? 1 : (1 - (t - 0.88) / 0.12);

        return IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.78),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '$caller calls $claimant a liar',
                      style: text.titleSmall?.copyWith(
                        color: skin.inkMuted,
                        fontFamily: skin.display,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: metrics.gutter),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (int index = 0; index < challenge.revealed.length; index++)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: metrics.gutter * 0.4,
                            ),
                            child: _FlipCard(
                              entry: challenge.revealed[index],
                              // Staggered: each card turns a quarter-second
                              // after the one before it.
                              progress: _stagger(t, index, challenge.revealed.length),
                              honest: _isHonest(challenge.revealed[index]),
                            ),
                          ),
                      ],
                    ),

                    SizedBox(height: metrics.gutter * 1.2),

                    // The verdict, once every card is over.
                    AnimatedOpacity(
                      duration: AppMotion.normal,
                      opacity: t > 0.62 ? 1 : 0,
                      child: Column(
                        children: <Widget>[
                          Text(
                            challenge.honest ? 'Telling the truth' : 'Caught lying',
                            style: text.headlineSmall?.copyWith(
                              color: challenge.honest ? skin.success : skin.danger,
                              fontFamily: skin.display,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: metrics.gutter * 0.3),
                          Text(
                            loserIsMe
                                ? 'You drink.'
                                : '${_nameOf(challenge.loserId)} drinks.',
                            style: text.bodyMedium?.copyWith(color: skin.ink),
                          ),
                          if (widget.shot != null) ...<Widget>[
                            SizedBox(height: metrics.gutter * 0.8),
                            _ShotOutcome(shot: widget.shot!, t: t),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isHonest(BarCard entry) =>
      entry.card.isJoker ||
      (widget.tableRank != null && entry.card.rank == widget.tableRank);

  /// How far through its own flip card [index] is, given overall progress [t].
  static double _stagger(double t, int index, int count) {
    const double start = 0.10;
    const double each = 0.17;
    final double begin = start + index * each;
    final double end = begin + 0.20;
    if (t <= begin) return 0;
    if (t >= end) return 1;
    return (t - begin) / (end - begin);
  }

  String _nameOf(String playerId) {
    if (playerId == widget.selfId) return 'you';
    return widget.room?.seatOf(playerId)?.username ?? 'somebody';
  }
}

/// One card turning face up.
///
/// A real flip: the card is scaled horizontally to zero and back, with the
/// back showing on the way in and the face on the way out. Rotating the whole
/// widget in 3D would need a perspective matrix for an effect nobody would be
/// able to tell apart at this size.
class _FlipCard extends StatelessWidget {
  const _FlipCard({
    required this.entry,
    required this.progress,
    required this.honest,
  });

  final BarCard entry;
  final double progress;
  final bool honest;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;
    final GameSkin skin = context.skin;
    final double height = metrics.cardHeight * 1.05;

    final bool turned = progress >= 0.5;
    // Zero at the halfway point, which is where the swap happens.
    final double squeeze = (progress - 0.5).abs() * 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scaleByDouble(squeeze.clamp(0.04, 1).toDouble(), 1, 1, 1),
          child: PlayingCardView(
            card: turned ? entry.card : null,
            height: height,
            highlighted: turned && !honest,
          ),
        ),
        SizedBox(height: metrics.gutter * 0.3),
        AnimatedOpacity(
          duration: AppMotion.fast,
          opacity: turned ? 1 : 0,
          child: Icon(
            honest ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: honest ? skin.success : skin.danger,
            size: 16 * metrics.scale,
          ),
        ),
      ],
    );
  }
}

/// The tray emptying by one, and whether that was the bad glass.
class _ShotOutcome extends StatelessWidget {
  const _ShotOutcome({required this.shot, required this.t});

  final BarShot shot;
  final double t;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    // The glass is drunk late in the reveal, after the verdict has landed.
    final bool drunk = t > 0.78;

    return Column(
      children: <Widget>[
        ShotTray(
          remaining: drunk ? shot.glassesRemaining : shot.glassesBefore,
          total: 6,
        ),
        SizedBox(height: metrics.gutter * 0.4),
        AnimatedOpacity(
          duration: AppMotion.normal,
          opacity: drunk ? 1 : 0,
          child: Text(
            shot.eliminated
                ? 'That was the one. They are out.'
                : 'They walk away from it — ${shot.glassesRemaining} left.',
            style: text.labelLarge?.copyWith(
              color: shot.eliminated ? skin.danger : skin.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
