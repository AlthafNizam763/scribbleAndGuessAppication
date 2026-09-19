import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/features/games/common/game_audio.dart';
import 'package:scribble_guess/features/games/common/game_chat_overlay.dart';
import 'package:scribble_guess/features/games/common/game_hud.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/game_voice_bar.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/common/playing_card_view.dart';
import 'package:scribble_guess/features/games/kazhutha/kazhutha_result_overlay.dart';
import 'package:scribble_guess/features/games/kazhutha/widgets/kazhutha_table.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/games/kazhutha_state.dart';
import 'package:scribble_guess/models/games/playing_card.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/games/kazhutha_controller.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Kazhutha, played.
///
/// ## The shape of the screen
///
/// Opponents arc across the top with their backs showing, the pairs everybody
/// has laid down sit in the middle of the felt, and the player's own hand is
/// fanned along the bottom where a hand of cards actually is. Nothing here is
/// a portrait layout turned sideways: the table is wider than it is tall
/// because a table is, and the width is what makes room for six seats.
///
/// ## What a turn is
///
/// Tap a seat, and their fan opens face-down in front of you. Tap a card in
/// it. That is the whole interaction, and it is two taps rather than one on
/// purpose — reaching into somebody's hand is the moment the game is about,
/// and collapsing it into a single tap on an avatar throws that away.
///
/// Which position you pick is genuinely yours to choose and genuinely carries
/// no information: the server reshuffles that hand the instant before the
/// pick. See `KazhuthaController.draw`.
///
/// ## Authority
///
/// Nothing on this screen decides anything. The turn, the legality of a draw,
/// what was drawn, who paired, who went out and who is left holding the queen
/// are all the server's, and all of them arrive on the same broadcast every
/// other player gets. The only thing the client does with that is draw it.
class KazhuthaGameScreen extends ConsumerStatefulWidget {
  const KazhuthaGameScreen({super.key});

  @override
  ConsumerState<KazhuthaGameScreen> createState() => _KazhuthaGameScreenState();
}

class _KazhuthaGameScreenState extends ConsumerState<KazhuthaGameScreen> {
  /// The seat whose fan is open, or null when nobody's is.
  String? _pickingFrom;

  bool _chatOpen = false;

  /// The turn we last announced, so the chime fires once per turn rather than
  /// on every rebuild that happens to arrive while it is still our go.
  String _announcedTurn = '';

  /// The draw we last played a sound for, by the server's own timestamp.
  ///
  /// The same guard as [_announcedTurn] and for the same reason: a rebuild is
  /// not an event. The server stamps each draw, so a stamp we have already
  /// heard is a repaint and a new one is a card actually changing hands.
  int _heardDrawAtMs = 0;

  /// Whether the donkey has already been revealed, so her sting lands once.
  bool _heardDonkey = false;

  void _onTurnChanged(KazhuthaState state, String selfId) {
    final String turn = state.currentPlayerId;
    if (turn == _announcedTurn) return;
    _announcedTurn = turn;

    if (turn.isEmpty) return;
    _audio.turnChanged(mine: turn == selfId);
  }

  /// The table's own sounds: a card pulled, a pair going down, the donkey.
  ///
  /// Driven off the state the server sent rather than off the tap that caused
  /// it, so a draw somebody else made sounds exactly like one of ours — which
  /// is the point of a table where everybody watches everybody pick.
  void _onTableChanged(KazhuthaState state, String selfId) {
    if (state.lastDraw case final KazhuthaDraw draw
        when draw.atMs > _heardDrawAtMs) {
      _heardDrawAtMs = draw.atMs;
      // Being picked from sounds different from picking. Everything else at
      // this table is public, so this is the only cue that tells you a card
      // left your own fan without looking at it.
      if (draw.targetId == selfId) {
        _audio.cardTaken();
      } else {
        _audio.cardDrawn();
      }
      // And then, if it matched, the pair hits the table.
      if (draw.paired) _audio.cardPlayed();
    }

    if (!_heardDonkey && state.kazhuthaId.isNotEmpty) {
      _heardDonkey = true;
      _audio.revealed();
    }
  }

  /// This game's voice. Read once — the mapper is stateless and the service
  /// behind it is a singleton.
  GameAudio get _audio => ref.read(gameAudioProvider(GameId.kazhutha));

  @override
  void initState() {
    super.initState();
    // Unpacks only this game's folder; see `SoundService.warmUpGame`.
    unawaited(_audio.warmUp().then((_) {
      if (mounted) _audio.arrive();
    }));
  }

  Future<void> _draw(String targetId, int index) async {
    setState(() => _pickingFrom = null);
    await ref.read(kazhuthaControllerProvider).draw(
          targetPlayerId: targetId,
          cardIndex: index,
        );
  }

  Future<void> _leave() async {
    final bool go = await confirm(
      context,
      title: 'Leave the table?',
      message: 'Your seat is given up and the hand carries on without you.',
      confirmLabel: 'Leave',
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
    final KazhuthaState state = ref.watch(kazhuthaStateProvider);
    final String selfId = ref.watch(platformSelfIdProvider);
    final bool myTurn = ref.watch(kazhuthaIsMyTurnProvider);

    _onTurnChanged(state, selfId);
    _onTableChanged(state, selfId);

    final List<KazhuthaTableSeat> opponents = _opponents(session.room, state, selfId);

    return LandscapeGameScaffold(
      skin: GameSkin.kazhutha,
      connection: session.connection,
      onLeave: _leave,
      table: _Table(
        opponents: opponents,
        state: state,
        selfId: selfId,
        myTurn: myTurn,
        busy: session.acting,
        onPick: (String id) => setState(() => _pickingFrom = id),
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

          if (_pickingFrom != null)
            _PickFan(
              seat: opponents.firstWhere(
                (KazhuthaTableSeat seat) => seat.id == _pickingFrom,
                orElse: () => opponents.first,
              ),
              busy: session.acting,
              onCancel: () => setState(() => _pickingFrom = null),
              onPick: (int index) => _draw(_pickingFrom!, index),
            ),

          GameChatOverlay(
            open: _chatOpen,
            onClose: () => setState(() => _chatOpen = false),
          ),

          // Last, so it covers everything: the match is over and nothing
          // behind it can be acted on any more.
          if (state.isOver)
            KazhuthaResultOverlay(state: state, room: session.room, selfId: selfId),
        ],
      ),
    );
  }

  /// Everybody except the local player, joined across the two payloads.
  ///
  /// A seat the room knows about but the match does not — somebody who joined
  /// while a hand was being dealt — is dropped rather than drawn with an empty
  /// hand, because a seat with no cards and no finishing place is a seat that
  /// is not in this match.
  List<KazhuthaTableSeat> _opponents(
    PlatformRoom? room,
    KazhuthaState state,
    String selfId,
  ) {
    if (room == null) return const <KazhuthaTableSeat>[];

    return <KazhuthaTableSeat>[
      for (final PlatformSeat player in room.seats)
        if (player.playerId != selfId)
          if (state.seatOf(player.playerId) case final KazhuthaSeat hand)
            KazhuthaTableSeat(player: player, hand: hand),
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
    required this.onPick,
  });

  final List<KazhuthaTableSeat> opponents;
  final KazhuthaState state;
  final String selfId;
  final bool myTurn;
  final bool busy;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;
    final List<PlayingCard> hand = state.hand;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const KazhuthaFelt(),

        Padding(
          padding: EdgeInsets.only(
            top: 44 * metrics.scale,
            left: metrics.gutter,
            right: metrics.gutter,
            bottom: metrics.gutter * 0.5,
          ),
          child: Column(
            children: <Widget>[
              // The arc of opponents, sized to its own content.
              //
              // It used to be pinned to a fixed height, which broke the moment
              // the seat badge learned to stack on a narrow phone: a taller
              // badge overflowed a box that could not grow. The middle of the
              // table absorbs the difference instead — it is the one part of
              // this layout with slack in it, which is exactly what slack is
              // for.
              _SeatArc(
                opponents: opponents,
                currentPlayerId: state.currentPlayerId,
                selectable: myTurn && !busy,
                onPick: onPick,
              ),

              // Scaled to the room left between the seats and the hand. See
              // the same treatment in Bluff Bar: the fan and the seats keep
              // their size on every device, and the decoration in the middle
              // is what gives way on a short one.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _Centre(state: state, myTurn: myTurn),
                  ),
                ),
              ),

              KazhuthaHand(cards: hand, donkey: state.donkeyCard),
            ],
          ),
        ),
      ],
    );
  }
}

/// The opponents, arranged in a shallow arc across the far side of the table.
///
/// A [Row] with a per-seat vertical offset rather than real polar maths: the
/// arc only has to *read* as one, and a row can never overflow a narrow phone
/// the way positioned seats around an ellipse can. Six seats on a 20:9 phone
/// was the case that decided it.
class _SeatArc extends StatelessWidget {
  const _SeatArc({
    required this.opponents,
    required this.currentPlayerId,
    required this.selectable,
    required this.onPick,
  });

  final List<KazhuthaTableSeat> opponents;
  final String currentPlayerId;
  final bool selectable;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (opponents.isEmpty) return const SizedBox.shrink();

    final GameMetrics metrics = context.metrics;
    final double centre = (opponents.length - 1) / 2;
    final double lift = 10 * metrics.scale;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int index = 0; index < opponents.length; index++)
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                // Seats nearer the middle sit further back, which is what an
                // arc looks like from the near side of a table.
                top: centre == 0
                    ? 0
                    : (1 - (index - centre).abs() / math.max(centre, 1)) * -lift + lift,
              ),
              child: KazhuthaSeatView(
                seat: opponents[index],
                isTurn: opponents[index].id == currentPlayerId,
                isSelectable: selectable && opponents[index].hand.isDrawable,
                onTap: () => onPick(opponents[index].id),
              ),
            ),
          ),
      ],
    );
  }
}

/// The middle of the felt: what has been laid down, and who the donkey is.
class _Centre extends StatelessWidget {
  const _Centre({required this.state, required this.myTurn});

  final KazhuthaState state;
  final bool myTurn;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        KazhuthaDiscardPile(discards: state.discards),
        SizedBox(width: metrics.gutter * 2),

        // The donkey, face up, all match. Which card she is has never been a
        // secret — only who is holding her — so showing her here is the same
        // information everybody at a real table already has, and it is what
        // makes the game legible to somebody who has never played it.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'THE DONKEY',
              style: text.labelSmall?.copyWith(
                color: skin.inkMuted,
                fontFamily: skin.display,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            SizedBox(height: metrics.gutter * 0.4),
            PlayingCardView(
              card: state.donkeyCard,
              height: metrics.cardHeight * 0.62,
              highlighted: true,
            ),
            SizedBox(height: metrics.gutter * 0.4),
            Text(
              myTurn ? 'Tap a player to draw' : 'Last one holding her loses',
              style: text.labelSmall?.copyWith(
                color: myTurn ? skin.accent : skin.inkMuted,
                fontWeight: myTurn ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- the HUD --

class _Hud extends ConsumerWidget {
  const _Hud({
    required this.state,
    required this.session,
    required this.selfId,
    required this.myTurn,
    required this.chatOpen,
    required this.onToggleChat,
  });

  final KazhuthaState state;
  final PlatformSession session;
  final String selfId;
  final bool myTurn;
  final bool chatOpen;
  final VoidCallback onToggleChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String turnName = _nameOf(state.currentPlayerId, session.room, selfId);

    return GameHudBar(
      title: 'Kazhutha',
      headline: GameHeadline(
        label: state.isPlaying
            ? (myTurn ? 'Your turn' : '$turnName is drawing')
            : 'Waiting for the deal',
        detail: state.isPlaying ? '${state.cardsInPlay} cards in play' : null,
        mine: myTurn,
      ),
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

// ------------------------------------------------------------ the pick fan --

/// Somebody's hand, opened face-down in front of you to reach into.
///
/// This is the moment the game is about, so it takes over the screen: the fan
/// is big, the cards are individually tappable, and there is nothing else to
/// press except the way out. Anything smaller and a player is tapping at
/// 20-pixel slivers of card with a thumb.
class _PickFan extends StatelessWidget {
  const _PickFan({
    required this.seat,
    required this.busy,
    required this.onCancel,
    required this.onPick,
  });

  final KazhuthaTableSeat seat;
  final bool busy;
  final VoidCallback onCancel;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final int count = seat.hand.cardCount;
    final double height = metrics.cardHeight * 1.12;
    final double width = height * PlayingCardView.aspect;
    final double available = metrics.size.width * 0.8;
    final double step = count <= 1
        ? 0
        : math.min(width * 0.72, (available - width) / (count - 1));

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              "${seat.player.username}'s hand",
              style: text.titleMedium?.copyWith(
                color: skin.ink,
                fontFamily: skin.display,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: metrics.gutter * 0.3),
            Text(
              'Take one. You cannot see what it is.',
              style: text.bodySmall?.copyWith(color: skin.inkMuted),
            ),
            SizedBox(height: metrics.gutter * 1.5),

            SizedBox(
              height: height * 1.1,
              width: width + step * math.max(0, count - 1),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  for (int index = 0; index < count; index++)
                    Positioned(
                      left: step * index,
                      child: _PickCard(
                        height: height,
                        enabled: !busy,
                        onTap: () => onPick(index),
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(height: metrics.gutter * 1.5),
            TextButton(
              onPressed: busy ? null : onCancel,
              child: Text(
                'Pick somebody else',
                style: TextStyle(color: skin.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One face-down card in the pick fan, which lifts under a finger.
class _PickCard extends StatefulWidget {
  const _PickCard({
    required this.height,
    required this.enabled,
    required this.onTap,
  });

  final double height;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PickCard> createState() => _PickCardState();
}

class _PickCardState extends State<_PickCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _hovered = true),
        onTapCancel: () => setState(() => _hovered = false),
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: Curves.easeOut,
          // Lifts out of the fan, which is what picking a card out of
          // somebody's hand looks like and what tells a player which one
          // their thumb is actually over.
          transform: Matrix4.translationValues(0, _hovered ? -14 : 0, 0),
          child: PlayingCardView(
            card: null,
            height: widget.height,
            highlighted: _hovered,
          ),
        ),
      ),
    );
  }
}
