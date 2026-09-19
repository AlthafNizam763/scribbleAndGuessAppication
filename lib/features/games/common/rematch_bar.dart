import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// What happens after a result: play again, or go.
///
/// ## Why this is one widget for all three games
///
/// The rematch flow has nothing to do with the game that just finished. It is
/// the same offer, the same deadline, the same tally and the same three ways
/// out whether the last thing that happened was a queen of spades or a reactor
/// breach — so it is written once and dressed by whichever [GameSkin] is
/// installed above it.
///
/// ## The states it has to render
///
/// Four, and they are genuinely different:
///
///  1. **Nothing offered.** Two buttons: offer one, or leave.
///  2. **An offer is standing and this player has not answered.** Accept,
///     decline, and a countdown — because a deadline nobody can see is a
///     deadline that feels like a bug when it passes.
///  3. **Answered, waiting.** A tally of who else has, so the wait is legible.
///  4. **It failed.** The message the brief asks for, and a way out that does
///     not put them back in the room they are trying to leave.
///
/// A rematch that *succeeds* renders nothing at all: the room goes back to
/// playing, the session's match changes, and the result overlay it was drawn
/// under disappears on its own.
class RematchBar extends ConsumerStatefulWidget {
  const RematchBar({super.key});

  @override
  ConsumerState<RematchBar> createState() => _RematchBarState();
}

class _RematchBarState extends ConsumerState<RematchBar> {
  bool _busy = false;

  /// Redraws the countdown once a second.
  ///
  /// The deadline is a server timestamp; nothing here decides when it passes,
  /// and when it does the server closes the offer and says so. This only
  /// stops the number on screen being stale.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _leave() async {
    await ref.read(platformSessionProvider.notifier).leave();
    if (!mounted) return;
    context.goNamed(AppRoutes.home);
  }

  /// Leaves this room and goes straight back to the game's lobby.
  ///
  /// Distinct from "back to games": a player who wants another match of *this*
  /// game should not have to find it in the list again.
  Future<void> _findAnother() async {
    final PlatformSession session = ref.read(platformSessionProvider);
    final String? wire = session.gameId?.wire;

    await ref.read(platformSessionProvider.notifier).leave();
    if (!mounted) return;

    if (wire == null) {
      context.goNamed(AppRoutes.home);
      return;
    }
    context.goNamed(
      AppRoutes.gameLobby,
      pathParameters: <String, String>{'gameId': wire},
    );
  }

  @override
  Widget build(BuildContext context) {
    final PlatformSession session = ref.watch(platformSessionProvider);
    final String selfId = ref.watch(platformSelfIdProvider);
    final RematchOffer? offer = session.room?.rematch;
    final GameMetrics metrics = context.metrics;

    final Widget body;
    if (offer != null && offer.failed) {
      body = _Failed(onLeave: _leave, onFind: _findAnother, busy: _busy);
    } else if (offer != null && offer.open && offer.awaits(selfId)) {
      body = _Answer(
        offer: offer,
        room: session.room,
        busy: _busy,
        onAccept: () => _run(() => ref
            .read(platformSessionProvider.notifier)
            .respondRematch(accept: true)),
        onDecline: () => _run(() => ref
            .read(platformSessionProvider.notifier)
            .respondRematch(accept: false)),
      );
    } else if (offer != null && offer.open) {
      body = _Waiting(offer: offer, room: session.room, onLeave: _leave);
    } else {
      body = _Idle(
        busy: _busy,
        onRematch: () => _run(
          () => ref.read(platformSessionProvider.notifier).requestRematch(),
        ),
        onFind: _findAnother,
        onLeave: _leave,
      );
    }

    return AnimatedSize(
      duration: AppMotion.normal,
      curve: Curves.easeOut,
      child: Padding(
        padding: EdgeInsets.only(top: metrics.gutter * 0.5),
        child: body,
      ),
    );
  }
}

/// Nothing offered yet.
class _Idle extends StatelessWidget {
  const _Idle({
    required this.busy,
    required this.onRematch,
    required this.onFind,
    required this.onLeave,
  });

  final bool busy;
  final VoidCallback onRematch;
  final VoidCallback onFind;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final GameMetrics metrics = context.metrics;

    return Wrap(
      spacing: metrics.gutter * 0.6,
      runSpacing: metrics.gutter * 0.5,
      alignment: WrapAlignment.center,
      children: <Widget>[
        _SkinButton(
          label: 'Rematch',
          icon: Icons.replay_rounded,
          primary: true,
          onPressed: busy ? null : onRematch,
        ),
        _SkinButton(
          label: 'Find new game',
          icon: Icons.search_rounded,
          onPressed: busy ? null : onFind,
        ),
        _SkinButton(
          label: 'Back to games',
          icon: Icons.grid_view_rounded,
          onPressed: busy ? null : onLeave,
        ),
      ],
    );
  }
}

/// Somebody asked, and this player has not answered.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.offer,
    required this.room,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final RematchOffer offer;
  final PlatformRoom? room;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final String asker = room?.seatOf(offer.requestedBy)?.username ?? 'Somebody';
    final int seconds = _secondsLeft(offer);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$asker wants a rematch',
          style: text.titleSmall?.copyWith(
            color: skin.ink,
            fontFamily: skin.display,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: metrics.gutter * 0.3),
        Text(
          '${seconds}s to answer',
          style: text.labelMedium?.copyWith(
            color: seconds <= 5 ? skin.danger : skin.inkMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: metrics.gutter * 0.7),
        Wrap(
          spacing: metrics.gutter * 0.6,
          alignment: WrapAlignment.center,
          children: <Widget>[
            _SkinButton(
              label: "I'm in",
              icon: Icons.check_rounded,
              primary: true,
              onPressed: busy ? null : onAccept,
            ),
            _SkinButton(
              label: 'No thanks',
              icon: Icons.close_rounded,
              onPressed: busy ? null : onDecline,
            ),
          ],
        ),
      ],
    );
  }
}

/// Answered; waiting on the rest of the table.
class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.offer,
    required this.room,
    required this.onLeave,
  });

  final RematchOffer offer;
  final PlatformRoom? room;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    // Only the people still being waited on. A tally of "3 of 5" tells a
    // player nothing about whether it is worth waiting; a list of names does.
    final List<String> pending = <String>[
      for (final PlatformSeat seat in room?.seats ?? const <PlatformSeat>[])
        if (!seat.isBot && offer.awaits(seat.playerId)) seat.username,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 14 * metrics.scale,
              height: 14 * metrics.scale,
              child: CircularProgressIndicator(strokeWidth: 2, color: skin.accent),
            ),
            SizedBox(width: metrics.gutter * 0.5),
            Text(
              '${offer.accepted.length} in · ${_secondsLeft(offer)}s left',
              style: text.labelLarge?.copyWith(color: skin.ink),
            ),
          ],
        ),
        if (pending.isNotEmpty) ...<Widget>[
          SizedBox(height: metrics.gutter * 0.3),
          Text(
            'Waiting on ${pending.join(', ')}',
            textAlign: TextAlign.center,
            style: text.labelSmall?.copyWith(color: skin.inkMuted),
          ),
        ],
        SizedBox(height: metrics.gutter * 0.5),
        TextButton(
          onPressed: onLeave,
          child: Text('Leave anyway', style: TextStyle(color: skin.inkMuted)),
        ),
      ],
    );
  }
}

/// Not enough people wanted another round.
class _Failed extends StatelessWidget {
  const _Failed({
    required this.onLeave,
    required this.onFind,
    required this.busy,
  });

  final VoidCallback onLeave;
  final VoidCallback onFind;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Not enough players for rematch',
          style: text.titleSmall?.copyWith(
            color: skin.danger,
            fontFamily: skin.display,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: metrics.gutter * 0.6),
        // Both ways out, because the one thing this must never do is leave
        // somebody stuck in a room that is not going to play again.
        Wrap(
          spacing: metrics.gutter * 0.6,
          alignment: WrapAlignment.center,
          children: <Widget>[
            _SkinButton(
              label: 'Find new game',
              icon: Icons.search_rounded,
              primary: true,
              onPressed: busy ? null : onFind,
            ),
            _SkinButton(
              label: 'Back to games',
              icon: Icons.grid_view_rounded,
              onPressed: busy ? null : onLeave,
            ),
          ],
        ),
      ],
    );
  }
}

int _secondsLeft(RematchOffer offer) {
  final int remaining = offer.deadlineAtMs - DateTime.now().millisecondsSinceEpoch;
  return (remaining / 1000).ceil().clamp(0, 999);
}

/// A button in the game's own colours.
///
/// Not [AppButton]: that one is built against the app palette, and these sit
/// on a result card over a dark table where the app's surfaces would be
/// invisible.
class _SkinButton extends StatelessWidget {
  const _SkinButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;
    final bool enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.gutter,
            vertical: metrics.gutter * 0.55,
          ),
          decoration: BoxDecoration(
            color: primary ? skin.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(
              color: primary ? skin.accent : skin.edge,
              width: AppSpacing.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 15 * metrics.scale,
                color: primary ? skin.accentInk : skin.ink,
              ),
              SizedBox(width: metrics.gutter * 0.4),
              Text(
                label,
                style: text.labelLarge?.copyWith(
                  color: primary ? skin.accentInk : skin.ink,
                  fontFamily: skin.display,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
