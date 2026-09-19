import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/playing_card_view.dart';
import 'package:scribble_guess/features/games/common/rematch_bar.dart';
import 'package:scribble_guess/models/games/kazhutha_state.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/sound_provider.dart';
import 'package:scribble_guess/services/sound_service.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The end of a hand: who went out, in what order, and who is the Kazhutha.
///
/// ## Why the loser is the headline
///
/// Because that is the game. Everybody who got out is on the podium, but the
/// thing the table has spent ten minutes trying to avoid is being the one left
/// holding her — so the donkey gets the big card, the name and the reaction,
/// and the placings are a list underneath. A results screen that led with
/// "1st: Mr Whiskers" would be describing a different game.
///
/// The tone is teasing rather than grim. This is a game people play to laugh
/// at whoever loses, and the loser is shown the same card everybody else is.
class KazhuthaResultOverlay extends ConsumerStatefulWidget {
  const KazhuthaResultOverlay({
    required this.state,
    required this.room,
    required this.selfId,
    super.key,
  });

  final KazhuthaState state;
  final PlatformRoom? room;
  final String selfId;

  @override
  ConsumerState<KazhuthaResultOverlay> createState() =>
      _KazhuthaResultOverlayState();
}

class _KazhuthaResultOverlayState extends ConsumerState<KazhuthaResultOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  )..forward();

  @override
  void initState() {
    super.initState();
    // Fired once, from initState rather than from build: a result that chimed
    // again every time the chat panel opened behind it would be maddening.
    ref.read(soundServiceProvider).play(SoundEffect.gameEnd);
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final KazhuthaState state = widget.state;
    final bool iAmTheDonkey = state.kazhuthaId == widget.selfId;
    final String donkeyName = _nameOf(state.kazhuthaId);

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.82),
        child: FadeTransition(
          opacity: _entrance,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(metrics.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.8, end: 1).animate(
                      CurvedAnimation(parent: _entrance, curve: Curves.easeOutBack),
                    ),
                    child: PlayingCardView(
                      card: state.donkeyCard,
                      height: metrics.cardHeight * 1.1,
                      highlighted: true,
                    ),
                  ),
                  SizedBox(height: metrics.gutter),

                  Text(
                    iAmTheDonkey ? 'You are the Kazhutha' : '$donkeyName is the Kazhutha',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(
                      color: iAmTheDonkey ? skin.danger : skin.accent,
                      fontFamily: skin.display,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: metrics.gutter * 0.4),
                  Text(
                    iAmTheDonkey
                        ? 'Left holding the queen of spades. Again.'
                        : 'Left holding the queen of spades.',
                    style: text.bodySmall?.copyWith(color: skin.inkMuted),
                  ),

                  SizedBox(height: metrics.gutter * 1.5),
                  _Podium(
                    finishOrder: state.finishOrder,
                    selfId: widget.selfId,
                    nameOf: _nameOf,
                    seatOf: widget.room?.seatOf,
                  ),

                  SizedBox(height: metrics.gutter * 1.2),
                  // Rematch, find another, or leave — one widget for all three games,
                  // because the offer is the same whichever table it was.
                  const RematchBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _nameOf(String playerId) {
    if (playerId.isEmpty) return 'Nobody';
    if (playerId == widget.selfId) return 'You';
    return widget.room?.seatOf(playerId)?.username ?? 'Somebody';
  }
}

/// Everybody who got out, in the order they managed it.
class _Podium extends StatelessWidget {
  const _Podium({
    required this.finishOrder,
    required this.selfId,
    required this.nameOf,
    required this.seatOf,
  });

  final List<String> finishOrder;
  final String selfId;
  final String Function(String) nameOf;
  final PlatformSeat? Function(String)? seatOf;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    if (finishOrder.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: EdgeInsets.all(metrics.gutter),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: skin.edge, width: AppSpacing.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'GOT OUT',
            style: text.labelSmall?.copyWith(
              color: skin.inkMuted,
              fontFamily: skin.display,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          SizedBox(height: metrics.gutter * 0.6),
          for (int index = 0; index < finishOrder.length; index++)
            Padding(
              padding: EdgeInsets.only(bottom: metrics.gutter * 0.5),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 24 * metrics.scale,
                    child: Text(
                      '${index + 1}',
                      style: text.labelLarge?.copyWith(
                        color: index == 0 ? skin.accent : skin.inkMuted,
                        fontFamily: skin.display,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (seatOf?.call(finishOrder[index]) case final PlatformSeat seat) ...<Widget>[
                    PlayerAvatar(
                      avatarId: seat.avatarId,
                      colorIndex: seat.avatarColorIndex,
                      size: 24 * metrics.scale,
                    ),
                    SizedBox(width: metrics.gutter * 0.5),
                  ],
                  Expanded(
                    child: Text(
                      nameOf(finishOrder[index]),
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: finishOrder[index] == selfId ? skin.accent : skin.ink,
                        fontWeight: finishOrder[index] == selfId
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (index == 0)
                    Text(
                      'first out',
                      style: text.labelSmall?.copyWith(color: skin.success),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
