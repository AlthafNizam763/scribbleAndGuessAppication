import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/features/games/common/bot_chip.dart';
import 'package:scribble_guess/features/games/common/game_audio.dart';
import 'package:scribble_guess/features/games/common/game_chat_overlay.dart';
import 'package:scribble_guess/features/games/common/game_hud.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/game_voice_bar.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/ludo/ludo_result_overlay.dart';
import 'package:scribble_guess/features/games/ludo/widgets/ludo_board.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/games/ludo_state.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/games/ludo_controller.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Ludo, played.
///
/// ## The shape of the screen
///
/// The board is square and it is the game, so it takes as much of the height
/// as it can get and sits in the middle. Everything else — the four seats, the
/// die, the turn indicator — goes in the columns either side of it, which is
/// what landscape is *for*: a square board on a 20:9 phone leaves two tall
/// gaps, and those gaps are exactly where the rest of the furniture belongs.
///
/// ## A turn is two taps
///
/// Roll, then choose a counter. The counters the roll can move are ringed, so
/// the second tap is a choice between the ones that are lit rather than an
/// experiment. When only one can move, it is still a tap — auto-moving would
/// take the one decision Ludo has away from the player.
///
/// ## Authority
///
/// The dice are rolled on the server. Whether a counter may move, what it
/// captures, whether a six buys another turn and who has won are all decided
/// there, and all of it arrives on the same broadcast every other player gets.
/// The tumbling faces during a roll are decoration over a number that was
/// decided before the animation started.
class LudoGameScreen extends ConsumerStatefulWidget {
  const LudoGameScreen({super.key});

  @override
  ConsumerState<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends ConsumerState<LudoGameScreen> {
  bool _chatOpen = false;

  /// The counter under a finger, for the lift animation.
  int? _pressed;

  String _announcedTurn = '';
  int _announcedRoll = 0;
  int _announcedMove = 0;

  GameAudio get _audio => ref.read(gameAudioProvider(GameId.ludo));

  @override
  void initState() {
    super.initState();
    unawaited(_audio.warmUp());
  }

  /// One sound per thing that happened, once.
  ///
  /// Keyed on the server's own timestamps rather than on a rebuild, because
  /// this runs from `build` and a board that re-announced every roll whenever
  /// chat opened would be unbearable.
  void _announce(LudoState state, String selfId) {
    final String turn = state.currentPlayerId;
    if (turn != _announcedTurn) {
      _announcedTurn = turn;
      if (turn.isNotEmpty) _audio.turnChanged(mine: turn == selfId);
    }

    final LudoRoll? roll = state.lastRoll;
    if (roll != null && roll.atMs != _announcedRoll) {
      _announcedRoll = roll.atMs;
      _audio.diceRolled();
    }

    final LudoMove? move = state.lastMove;
    if (move != null && move.atMs != _announcedMove) {
      _announcedMove = move.atMs;
      if (move.captured.isNotEmpty) {
        _audio.eliminated();
      } else if (move.to >= LudoGeometry.home) {
        _audio.counterHome();
      } else if (move.to < 52 &&
          state.seatOf(move.playerId) >= 0 &&
          LudoGeometry.isSafeCell(
            LudoGeometry.boardCell(state.seatOf(move.playerId), move.to),
          )) {
        // A star. The same arithmetic the board paints it with, so what is
        // heard and what is seen cannot disagree — and only on the ring,
        // because the home lane has no stars and needs none.
        _audio.counterSafe();
      } else {
        _audio.counterMoved();
      }
    }
  }

  Future<void> _leave() async {
    final bool go = await confirm(
      context,
      title: 'Leave the board?',
      message: 'Your counters stay where they are and the game plays on.',
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
    final LudoState state = ref.watch(ludoStateProvider);
    final String selfId = ref.watch(platformSelfIdProvider);
    final bool myTurn = ref.watch(ludoIsMyTurnProvider);
    final List<int> movable = ref.watch(ludoMovableProvider);

    _announce(state, selfId);

    return LandscapeGameScaffold(
      skin: GameSkin.ludo,
      connection: session.connection,
      onLeave: _leave,
      table: _Table(
        state: state,
        room: session.room,
        selfId: selfId,
        myTurn: myTurn,
        movable: movable,
        busy: session.acting,
        pressed: _pressed,
        onPressToken: (int? index) => setState(() => _pressed = index),
        onRoll: () => ref.read(ludoControllerProvider).roll(),
        onMove: (int index) async {
          setState(() => _pressed = null);
          await ref.read(ludoControllerProvider).move(index);
        },
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
          GameChatOverlay(
            open: _chatOpen,
            onClose: () => setState(() => _chatOpen = false),
          ),
          if (state.isOver)
            LudoResultOverlay(state: state, room: session.room, selfId: selfId),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- the table --

class _Table extends StatelessWidget {
  const _Table({
    required this.state,
    required this.room,
    required this.selfId,
    required this.myTurn,
    required this.movable,
    required this.busy,
    required this.pressed,
    required this.onPressToken,
    required this.onRoll,
    required this.onMove,
  });

  final LudoState state;
  final PlatformRoom? room;
  final String selfId;
  final bool myTurn;
  final List<int> movable;
  final bool busy;
  final int? pressed;
  final ValueChanged<int?> onPressToken;
  final VoidCallback onRoll;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The board is square and takes the height. What is left either side
        // is where the seats and the die go — and on a 20:9 phone there is a
        // great deal left, while on a 4:3 tablet there is barely any, so the
        // columns are sized from what is actually spare rather than from a
        // fraction of the width.
        final double board = (constraints.maxHeight - metrics.gutter * 2)
            .clamp(120.0, constraints.maxWidth);
        final double spare = (constraints.maxWidth - board) / 2;
        final bool roomForColumns = spare >= 96 * metrics.scale;

        final Widget boardView = _Board(
          state: state,
          selfId: selfId,
          movable: movable,
          busy: busy,
          pressed: pressed,
          size: board,
          onPressToken: onPressToken,
          onMove: onMove,
        );

        if (!roomForColumns) {
          // Too narrow to flank the board: the seats go over the corners of
          // the board itself, which are the four yards and are the natural
          // place for them anyway.
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              boardView,
              Positioned(
                left: metrics.gutter * 0.5,
                bottom: metrics.gutter * 0.5,
                child: _DiePanel(
                  state: state,
                  myTurn: myTurn,
                  busy: busy,
                  onRoll: onRoll,
                ),
              ),
            ],
          );
        }

        return Row(
          children: <Widget>[
            SizedBox(
              width: spare,
              child: _SideColumn(
                seats: const <int>[0, 3],
                state: state,
                room: room,
                selfId: selfId,
              ),
            ),
            boardView,
            SizedBox(
              width: spare,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: _SideColumn(
                      seats: const <int>[1, 2],
                      state: state,
                      room: room,
                      selfId: selfId,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: metrics.gutter * 0.5),
                    child: _DiePanel(
                      state: state,
                      myTurn: myTurn,
                      busy: busy,
                      onRoll: onRoll,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The board plus the counters standing on it.
class _Board extends StatelessWidget {
  const _Board({
    required this.state,
    required this.selfId,
    required this.movable,
    required this.busy,
    required this.pressed,
    required this.size,
    required this.onPressToken,
    required this.onMove,
  });

  final LudoState state;
  final String selfId;
  final List<int> movable;
  final bool busy;
  final int? pressed;
  final double size;
  final ValueChanged<int?> onPressToken;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final double cell = size / LudoGeometry.gridSize;
    final double counter = cell * 0.82;
    final int mySeat = state.seatOf(selfId);

    // The squares this player's roll could reach, so the board can light them
    // as well as the counters. Derived from the same projection the server
    // validates against.
    final Set<int> reachable = <int>{
      if (mySeat >= 0)
        for (final int token in movable)
          if (state.positions[selfId]?[token] case final int from)
            if (from != LudoGeometry.inYard && from + (state.dice ?? 0) < 52)
              LudoGeometry.boardCell(mySeat, from + (state.dice ?? 0))
            else if (from == LudoGeometry.inYard)
              LudoGeometry.startCell(mySeat),
    };

    /// How many counters share a square, so a stack can fan out rather than
    /// hiding underneath itself.
    final Map<String, int> occupancy = <String, int>{};
    for (final ({String playerId, int seat, int slot, int position}) piece
        in state.counters) {
      final Offset at = LudoGeometry.cellFor(
        seat: piece.seat,
        position: piece.position,
        slot: piece.slot,
      );
      final String key = '${at.dx},${at.dy}';
      occupancy[key] = (occupancy[key] ?? 0) + 1;
    }
    final Map<String, int> placed = <String, int>{};

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: LudoBoardPainter(skin: skin, highlightCells: reachable),
          ),

          for (final ({String playerId, int seat, int slot, int position}) piece
              in state.counters)
            () {
              final Offset at = LudoGeometry.cellFor(
                seat: piece.seat,
                position: piece.position,
                slot: piece.slot,
              );
              final String key = '${at.dx},${at.dy}';
              final int index = placed[key] ?? 0;
              placed[key] = index + 1;

              // Two counters on one square are nudged apart so both are
              // visible; four in a yard well are already in separate wells.
              final int sharing = occupancy[key] ?? 1;
              final double spread = sharing > 1 ? cell * 0.18 : 0;
              final double nudge = (index - (sharing - 1) / 2) * spread;

              final bool mine = piece.playerId == selfId;
              final bool canMove = mine && movable.contains(piece.slot) && !busy;

              return AnimatedPositioned(
                key: ValueKey<String>('${piece.playerId}-${piece.slot}'),
                // The movement animation, and the only one on the board. A
                // counter walking from square to square is what makes a move
                // legible from across the table.
                duration: AppMotion.slow,
                curve: Curves.easeInOutCubic,
                left: at.dx * cell + (cell - counter) / 2 + nudge,
                top: at.dy * cell + (cell - counter) / 2,
                width: counter,
                height: counter,
                child: LudoCounter(
                  seat: piece.seat,
                  size: counter,
                  movable: canMove,
                  selected: canMove && pressed == piece.slot,
                  onTap: () {
                    onPressToken(piece.slot);
                    onMove(piece.slot);
                  },
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// Two seats, stacked down one side of the board.
class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.seats,
    required this.state,
    required this.room,
    required this.selfId,
  });

  final List<int> seats;
  final LudoState state;
  final PlatformRoom? room;
  final String selfId;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.gutter * 0.4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          for (final int seat in seats)
            if (seat < state.order.length)
              Flexible(
                child: _SeatCard(
                  seat: seat,
                  state: state,
                  player: room?.seatOf(state.order[seat]),
                  isSelf: state.order[seat] == selfId,
                ),
              ),
        ],
      ),
    );
  }
}

/// One player: their colour, their name, and how their four counters are doing.
class _SeatCard extends StatelessWidget {
  const _SeatCard({
    required this.seat,
    required this.state,
    required this.player,
    required this.isSelf,
  });

  final int seat;
  final LudoState state;
  final PlatformSeat? player;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final String playerId = state.order[seat];
    final LudoSeatState? counters = state.seatState(playerId);
    final bool onTurn = state.currentPlayerId == playerId;
    final Color tint = ludoSeatColours[seat % 4];

    return AnimatedContainer(
      duration: AppMotion.normal,
      margin: EdgeInsets.symmetric(vertical: metrics.gutter * 0.25),
      padding: EdgeInsets.all(metrics.gutter * 0.45),
      decoration: BoxDecoration(
        color: skin.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: onTurn ? tint : skin.edge,
          width: onTurn ? 2.5 : AppSpacing.border,
        ),
        boxShadow: onTurn
            ? <BoxShadow>[
                BoxShadow(color: tint.withValues(alpha: 0.35), blurRadius: 10),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 12 * metrics.scale,
                height: 12 * metrics.scale,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              SizedBox(width: metrics.gutter * 0.3),
              Flexible(
                child: Text(
                  isSelf ? 'You' : (player?.username ?? 'Seat ${seat + 1}'),
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (player?.isBot ?? false) ...<Widget>[
            SizedBox(height: metrics.gutter * 0.2),
            BotChip(difficulty: player!.botDifficulty),
          ],
          SizedBox(height: metrics.gutter * 0.25),
          Text(
            '${counters?.finished ?? 0} home · ${counters?.onBoard ?? 0} out',
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: skin.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// The die, and what it is telling this player to do.
class _DiePanel extends StatelessWidget {
  const _DiePanel({
    required this.state,
    required this.myTurn,
    required this.busy,
    required this.onRoll,
  });

  final LudoState state;
  final bool myTurn;
  final bool busy;
  final VoidCallback onRoll;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final bool canRoll = myTurn && state.dice == null && !busy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LudoDie(
          value: state.dice,
          size: 52 * metrics.scale,
          enabled: canRoll,
          onRoll: onRoll,
        ),
        SizedBox(height: metrics.gutter * 0.35),
        Text(
          canRoll
              ? 'Tap to roll'
              : myTurn
                  ? 'Pick a counter'
                  : 'Waiting',
          textAlign: TextAlign.center,
          style: text.labelSmall?.copyWith(
            color: myTurn ? skin.accent : skin.inkMuted,
            fontWeight: myTurn ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ the HUD --

class _Hud extends StatelessWidget {
  const _Hud({
    required this.state,
    required this.session,
    required this.selfId,
    required this.myTurn,
    required this.chatOpen,
    required this.onToggleChat,
  });

  final LudoState state;
  final PlatformSession session;
  final String selfId;
  final bool myTurn;
  final bool chatOpen;
  final VoidCallback onToggleChat;

  @override
  Widget build(BuildContext context) {
    final String turnName = state.currentPlayerId.isEmpty
        ? 'Nobody'
        : state.currentPlayerId == selfId
            ? 'You'
            : session.room?.seatOf(state.currentPlayerId)?.username ?? 'Somebody';

    final String label;
    if (!state.isPlaying) {
      label = 'Setting up the board';
    } else if (myTurn && state.dice == null) {
      label = 'Your roll';
    } else if (myTurn) {
      label = 'Move a counter';
    } else {
      label = "$turnName's turn";
    }

    return GameHudBar(
      title: 'Ludo',
      headline: GameHeadline(
        label: label,
        detail: state.dice != null ? 'rolled ${state.dice}' : null,
        mine: myTurn,
      ),
      actions: <Widget>[
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
}
