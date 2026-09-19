import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/features/games/bluff_bar/bluff_bar_result_overlay.dart';
import 'package:scribble_guess/features/games/bluff_bar/widgets/bluff_bar_reveal.dart';
import 'package:scribble_guess/features/games/bluff_bar/widgets/bluff_bar_table.dart';
import 'package:scribble_guess/features/games/common/game_audio.dart';
import 'package:scribble_guess/features/games/common/game_chat_overlay.dart';
import 'package:scribble_guess/features/games/common/game_hud.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/game_voice_bar.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/playing_card_view.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/games/bluff_bar_state.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/games/bluff_bar_controller.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Bluff Bar, played.
///
/// ## The shape of the screen
///
/// One bulb, one table, everybody round it. The rank being called sits under
/// the light in the middle where nobody can miss it, the claims made so far
/// run beside it as a tally, and the player's own cards are along the bottom.
///
/// ## The two buttons
///
/// A turn is exactly one of two things — put cards down, or call the last
/// player a liar — so there are exactly two controls, and they appear only
/// when they are legal. The claim button counts what is selected, because the
/// size of a claim is the decision: one card is safe and slow, three is a
/// dash for the exit and reads as desperate from across the table.
///
/// ## Where the tension is
///
/// In the tray of glasses, which is on screen at all times for everybody. The
/// odds on a lost call are `1 / glassesRemaining`, they are printed next to
/// the call button, and they get worse for the rest of the match. A player who
/// has drunk four times is looking at a very different decision from the
/// player opposite who has not lost a call all night, and both of them can see
/// which is which.
class BluffBarGameScreen extends ConsumerStatefulWidget {
  const BluffBarGameScreen({super.key});

  @override
  ConsumerState<BluffBarGameScreen> createState() => _BluffBarGameScreenState();
}

class _BluffBarGameScreenState extends ConsumerState<BluffBarGameScreen> {
  final Set<String> _selected = <String>{};
  bool _chatOpen = false;

  /// The challenge we have already played a sting for, so a reveal that stays
  /// on screen does not re-fire the sound on every rebuild.
  int _announcedChallenge = 0;

  /// The call we have already reacted to, kept apart from the shot above
  /// because they are two moments and the gap between them is the whole
  /// drama of this game.
  int _announcedCall = 0;
  String _announcedTurn = '';

  void _onStateChanged(BluffBarState state, String selfId) {
    final String turn = state.currentPlayerId;
    if (turn != _announcedTurn) {
      _announcedTurn = turn;
      // Selection cannot survive a turn change: those cards may not be in this
      // hand any more, and a stale id would be refused on the next claim.
      _selected.clear();
      if (turn.isNotEmpty) _audio.turnChanged(mine: turn == selfId);
    }

    // A call is public the moment it is made. Before this, only the player
    // who tapped Challenge heard anything — everybody else sat in silence
    // until the glass came down, which is the wrong way round.
    final BarChallenge? call = state.lastChallenge;
    if (call != null && call.atMs != _announcedCall) {
      _announcedCall = call.atMs;
      // Three positions, and they are three different moments. The challenger
      // already heard their own call when they tapped it. The claimant is
      // about to have their cards turned over. Everybody else is watching.
      if (call.claimantId == selfId) {
        _audio.tension();
      } else if (call.challengerId != selfId) {
        _audio.challenged();
      }
    }

    final BarShot? shot = state.lastShot;
    if (shot != null && shot.atMs != _announcedChallenge) {
      _announcedChallenge = shot.atMs;
      // The glass, then the verdict. Elimination is the bigger sound and
      // takes the moment; surviving is the reveal sting and moves on.
      if (shot.eliminated) {
        _audio.eliminated();
      } else {
        _audio.revealed();
      }
    }
  }

  GameAudio get _audio => ref.read(gameAudioProvider(GameId.bluffBar));

  @override
  void initState() {
    super.initState();
    unawaited(_audio.warmUp().then((_) {
      if (mounted) _audio.arrive();
    }));
  }

  Future<void> _declare() async {
    if (_selected.isEmpty) return;
    final List<String> cards = _selected.toList(growable: false);
    setState(_selected.clear);
    await ref.read(bluffBarControllerProvider).declare(cardIds: cards);
  }

  Future<void> _challenge() async {
    _audio.challenged();
    setState(_selected.clear);
    await ref.read(bluffBarControllerProvider).challenge();
  }

  Future<void> _leave() async {
    final bool go = await confirm(
      context,
      title: 'Walk out?',
      message: 'You forfeit the night and the rest of the table plays on.',
      confirmLabel: 'Walk out',
      destructive: true,
    );
    if (!go || !mounted) return;

    await ref.read(platformSessionProvider.notifier).leave();
    if (!mounted) return;
    context.goNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final PlatformSession session = ref.watch(platformSessionProvider);
    final BluffBarState state = ref.watch(bluffBarStateProvider);
    final String selfId = ref.watch(platformSelfIdProvider);
    final bool myTurn = ref.watch(bluffBarIsMyTurnProvider);

    _onStateChanged(state, selfId);

    final List<BarTableSeat> opponents = _opponents(session.room, state, selfId);

    return LandscapeGameScaffold(
      skin: GameSkin.bluffBar,
      connection: session.connection,
      onLeave: _leave,
      table: _Table(
        opponents: opponents,
        state: state,
        selfId: selfId,
        myTurn: myTurn,
        busy: session.acting,
        selected: _selected,
        onToggle: (String id) => setState(() {
          if (_selected.contains(id)) {
            _selected.remove(id);
          } else if (_selected.length < 3) {
            // Three is the most a claim may ever be, so the fourth tap is
            // refused here rather than by the server.
            _selected.add(id);
          }
        }),
      ),
      hud: _Hud(
        state: state,
        session: session,
        selfId: selfId,
        myTurn: myTurn,
        chatOpen: _chatOpen,
        onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
      ),
      overlay: Stack(
        children: <Widget>[
          const GameErrorFlash(),

          // The action bar sits above the table so it is never covered by a
          // hand that has grown, and below the chat so opening chat does not
          // leave a claim button floating over it.
          if (state.isPlaying && !state.isOver)
            _Actions(
              state: state,
              selfId: selfId,
              selected: _selected,
              busy: session.acting,
              onDeclare: _declare,
              onChallenge: _challenge,
              onReact: (BarReaction reaction) =>
                  ref.read(bluffBarControllerProvider).react(reaction),
            ),

          // The moment a call is paid for: the cards turn over in the middle
          // of the table and somebody drinks.
          if (state.lastChallenge != null && !state.isOver)
            BluffBarReveal(
              challenge: state.lastChallenge!,
              shot: state.lastShot,
              tableRank: state.tableRank,
              room: session.room,
              selfId: selfId,
            ),

          GameChatOverlay(
            open: _chatOpen,
            onClose: () => setState(() => _chatOpen = false),
          ),

          if (state.isOver)
            BluffBarResultOverlay(
              state: state,
              room: session.room,
              selfId: selfId,
              result: session.match?.result,
            ),
        ],
      ),
    );
  }

  List<BarTableSeat> _opponents(
    PlatformRoom? room,
    BluffBarState state,
    String selfId,
  ) {
    if (room == null) return const <BarTableSeat>[];

    return <BarTableSeat>[
      for (final PlatformSeat player in room.seats)
        if (player.playerId != selfId)
          if (state.seatOf(player.playerId) case final BarSeat seat)
            BarTableSeat(player: player, seat: seat),
    ];
  }
}

// --------------------------------------------------------------- the table --

class _Table extends StatelessWidget {
  const _Table({
    required this.opponents,
    required this.state,
    required this.selfId,
    required this.myTurn,
    required this.busy,
    required this.selected,
    required this.onToggle,
  });

  final List<BarTableSeat> opponents;
  final BluffBarState state;
  final String selfId;
  final bool myTurn;
  final bool busy;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const BluffBarRoom(),

        Padding(
          padding: EdgeInsets.only(
            top: 42 * metrics.scale,
            left: metrics.gutter,
            right: metrics.gutter,
            // Room for the action bar, which floats above the hand.
            bottom: 52 * metrics.scale,
          ),
          child: Column(
            children: <Widget>[
              // Sized to its content rather than pinned, for the same reason
              // the Kazhutha arc is: a badge that reflows onto two lines
              // cannot fit in a box that was measured for one.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final BarTableSeat seat in opponents)
                    Flexible(
                      child: BarSeatView(
                        seat: seat,
                        isTurn: seat.id == state.currentPlayerId,
                        isClaimant: state.lastClaim?.playerId == seat.id,
                        reaction: state.lastReaction?.playerId == seat.id
                            ? state.lastReaction!.reaction
                            : null,
                      ),
                    ),
                ],
              ),

              // The middle of the table scales to whatever vertical room is
              // left after the seats and the hand — which on a 360-point
              // phone is very little, and on a tablet is plenty.
              //
              // Scaling *this cluster* rather than the whole screen is the
              // point: the cards a player has to read and the buttons they
              // have to hit stay full size on every device, and the
              // decoration gives way instead. A global shrink would have
              // fixed the same overflow by making the game worse everywhere.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _Centre(state: state, selfId: selfId),
                  ),
                ),
              ),

              BluffBarHand(
                cards: state.hand,
                selected: selected,
                isHonest: state.playsHonestly,
                enabled: myTurn && !busy,
                onToggle: onToggle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Under the bulb: the called rank, the pile, and what the table has claimed.
class _Centre extends StatelessWidget {
  const _Centre({required this.state, required this.selfId});

  final BluffBarState state;
  final String selfId;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final int claimed = state.claimedSoFar;
    final int ceiling = state.honestCeilingFor(selfId);
    final bool certain = state.liarIsCertain(selfId);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // The called rank. The biggest thing on the table, because every claim
        // made all round is a claim about this one letter.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'CALLING',
              style: text.labelSmall?.copyWith(
                color: skin.inkMuted,
                fontFamily: skin.display,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
            SizedBox(height: metrics.gutter * 0.2),
            Text(
              state.tableRank?.label ?? '—',
              style: TextStyle(
                color: skin.accent,
                fontFamily: skin.display,
                fontWeight: FontWeight.w900,
                fontSize: 54 * metrics.scale,
                height: 1,
              ),
            ),
            Text(
              'round ${state.roundNumber}',
              style: text.labelSmall?.copyWith(color: skin.inkMuted),
            ),
          ],
        ),

        SizedBox(width: metrics.gutter * 2),

        // The pile: face down, and it stays that way until somebody pays.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Pile(count: state.pileCount),
            SizedBox(height: metrics.gutter * 0.4),
            Text(
              '${state.pileCount} face down',
              style: text.labelSmall?.copyWith(color: skin.inkMuted),
            ),
          ],
        ),

        SizedBox(width: metrics.gutter * 2),

        // The counting argument, done for the player.
        //
        // Not a hint: every number here is public and any player could work it
        // out from the shoe and the tally. Doing the subtraction on their
        // behalf removes arithmetic, not judgement — whether *this* claim is
        // the lie is still entirely theirs.
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.gutter * 0.8,
            vertical: metrics.gutter * 0.5,
          ),
          decoration: BoxDecoration(
            color: skin.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: certain ? skin.danger : skin.edge,
              width: certain ? 2 : AppSpacing.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'CLAIMED',
                style: text.labelSmall?.copyWith(
                  color: skin.inkMuted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              Text(
                '$claimed of $ceiling possible',
                style: text.bodyMedium?.copyWith(
                  color: certain ? skin.danger : skin.ink,
                  fontFamily: skin.display,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (certain)
                Text(
                  'Somebody is lying.',
                  style: text.labelSmall?.copyWith(
                    color: skin.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pile extends StatelessWidget {
  const _Pile({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;
    final double height = metrics.cardHeight * 0.5;
    final int drawn = count.clamp(0, 6);

    if (drawn == 0) {
      return SizedBox(height: height, width: height * 0.68);
    }

    return SizedBox(
      height: height * 1.2,
      width: height * 0.68 + drawn * 3.0,
      child: Stack(
        children: <Widget>[
          for (int index = 0; index < drawn; index++)
            Positioned(
              left: index * 3.0,
              top: index * 2.0,
              child: Transform.rotate(
                angle: (index.isEven ? 1 : -1) * 0.04 * index,
                child: PlayingCardView(card: null, height: height),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- the HUD ---

class _Hud extends StatelessWidget {
  const _Hud({
    required this.state,
    required this.session,
    required this.selfId,
    required this.myTurn,
    required this.chatOpen,
    required this.onToggleChat,
  });

  final BluffBarState state;
  final PlatformSession session;
  final String selfId;
  final bool myTurn;
  final bool chatOpen;
  final VoidCallback onToggleChat;

  @override
  Widget build(BuildContext context) {
    final BarClaim? claim = state.lastClaim;
    final String turnName = _nameOf(state.currentPlayerId, session.room, selfId);

    final String label;
    if (!state.isPlaying) {
      label = 'Waiting for the deal';
    } else if (claim != null && claim.playerId != selfId) {
      final String claimant = _nameOf(claim.playerId, session.room, selfId);
      label = '$claimant says ${claim.count} × ${state.tableRank?.label ?? '?'}';
    } else if (myTurn) {
      label = 'Your move';
    } else {
      label = '$turnName is deciding';
    }

    return GameHudBar(
      title: 'Bluff Bar',
      headline: GameHeadline(label: label, mine: myTurn),
      actions: <Widget>[
        // One bar for all three games, in each one's own colours.
        const GameVoiceBar(),
        GameIconButton(
          icon: Icons.chat_bubble_outline_rounded,
          tooltip: 'Table talk',
          active: chatOpen,
          badge: chatOpen ? 0 : session.chat.length,
          onPressed: onToggleChat,
        ),
      ],
    );
  }

  static String _nameOf(String playerId, PlatformRoom? room, String selfId) {
    if (playerId.isEmpty) return 'Nobody';
    if (playerId == selfId) return 'You';
    return room?.seatOf(playerId)?.username ?? 'Somebody';
  }
}

// ------------------------------------------------------------- the actions --

/// The two things a turn can be, plus the tray that says what they cost.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.selfId,
    required this.selected,
    required this.busy,
    required this.onDeclare,
    required this.onChallenge,
    required this.onReact,
  });

  final BluffBarState state;
  final String selfId;
  final Set<String> selected;
  final bool busy;
  final VoidCallback onDeclare;
  final VoidCallback onChallenge;
  final ValueChanged<BarReaction> onReact;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final bool canDeclare = state.canDeclare(selfId) && selected.isNotEmpty && !busy;
    final bool canChallenge = state.canChallenge(selfId) && !busy;
    final BarSeat? mine = state.seatOf(selfId);
    final int glasses = mine?.glassesRemaining ?? 6;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: metrics.gutter * 0.5,
            left: metrics.gutter * 0.5,
            right: metrics.gutter * 0.5,
          ),
          // Wrap, not Row. The tray, two buttons and six reactions are wider
          // than a 640-point phone, and the right answer is for them to take a
          // second line rather than for every control to shrink until they
          // fit — which would make the two buttons that matter harder to hit
          // on every device in order to fix the narrowest one.
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: metrics.gutter * 0.6,
            runSpacing: metrics.gutter * 0.4,
            children: <Widget>[
              // The player's own tray, always visible. This is the number both
              // decisions are really about.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'YOUR TRAY',
                    style: text.labelSmall?.copyWith(
                      color: skin.inkMuted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: metrics.gutter * 0.25),
                  ShotTray(remaining: glasses, total: 6),
                ],
              ),

              _BarButton(
                label: selected.isEmpty
                    ? 'Pick cards'
                    : 'Claim ${selected.length} × ${state.tableRank?.label ?? ''}',
                icon: Icons.style_rounded,
                tone: skin.accent,
                onPressed: canDeclare ? onDeclare : null,
              ),

              _BarButton(
                label: 'Call a lie',
                // The odds of being wrong, printed on the button. It is the
                // whole risk-and-reward of the game and it changes every time
                // this player loses a call.
                detail: glasses > 0 ? '1 in $glasses if you are wrong' : null,
                icon: Icons.local_bar_rounded,
                tone: skin.danger,
                onPressed: canChallenge ? onChallenge : null,
              ),

              _ReactionStrip(onReact: busy ? null : onReact),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.icon,
    required this.tone,
    required this.onPressed,
    this.detail,
  });

  final String label;
  final String? detail;
  final IconData icon;
  final Color tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final bool enabled = onPressed != null;

    return Opacity(
      // Disabled rather than hidden: a control that vanishes and reappears
      // moves everything beside it, and a player reaching for "call" should
      // not find "claim" under their thumb because the layout shifted.
      opacity: enabled ? 1 : 0.38,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.gutter,
            vertical: metrics.gutter * 0.55,
          ),
          decoration: BoxDecoration(
            color: enabled ? tone.withValues(alpha: 0.18) : skin.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: enabled ? tone : skin.edge, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 16 * metrics.scale, color: enabled ? tone : skin.inkMuted),
                  SizedBox(width: metrics.gutter * 0.4),
                  Text(
                    label,
                    style: text.labelLarge?.copyWith(
                      color: enabled ? tone : skin.inkMuted,
                      fontFamily: skin.display,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: text.labelSmall?.copyWith(color: skin.inkMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Six things to throw across the table, none of which change a rule.
class _ReactionStrip extends StatelessWidget {
  const _ReactionStrip({required this.onReact});

  final ValueChanged<BarReaction>? onReact;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.gutter * 0.3),
      decoration: BoxDecoration(
        color: skin.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: skin.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final BarReaction reaction in BarReaction.values)
            IconButton(
              onPressed: onReact == null ? null : () => onReact!(reaction),
              tooltip: reaction.label,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(
                width: 30 * metrics.scale,
                height: 30 * metrics.scale,
              ),
              padding: EdgeInsets.zero,
              icon: Text(
                reaction.glyph,
                style: TextStyle(fontSize: 14 * metrics.scale),
              ),
            ),
        ],
      ),
    );
  }
}
