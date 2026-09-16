import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/models/auto_tournament.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The pieces both tournament screens draw.
///
/// ## Why the AI badge is a widget and not a string
///
/// Because it has to be impossible to render an AI player as a person by
/// accident. Every place an entrant's name appears goes through
/// [TournamentPlayerLine], which reads `isBot` from the server's own payload
/// and draws the badge itself. A screen would have to deliberately not use it
/// to get the misleading version.
///
/// ## The visual language
///
/// The app's sketchbook style: off-white paper, hand-drawn dark borders, flat
/// fills, one accent colour at a time. No glassmorphism, no neon, no elevation
/// stacks — a tournament card is a card on the same paper as everything else.

/// The small status pill on a tournament card.
class TournamentStatusChip extends StatelessWidget {
  /// Creates the chip.
  const TournamentStatusChip({required this.status, super.key});

  /// What to describe.
  final AutoTournamentStatus status;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    // One colour at a time, and only where the state changes what the player
    // should do next. Registration and check-in are calls to action; running
    // and completed are information, and information does not get a colour.
    final (Color ink, String label) = switch (status) {
      AutoTournamentStatus.registration => (
          colors.success,
          context.l10n.tournamentStatusRegistration,
        ),
      AutoTournamentStatus.checkIn => (
          colors.warning,
          context.l10n.tournamentStatusCheckIn,
        ),
      AutoTournamentStatus.running => (
          colors.info,
          context.l10n.tournamentStatusRunning,
        ),
      AutoTournamentStatus.upcoming => (
          colors.inkSoft,
          context.l10n.tournamentStatusUpcoming,
        ),
      AutoTournamentStatus.completed => (
          colors.inkSoft,
          context.l10n.tournamentStatusCompleted,
        ),
      AutoTournamentStatus.cancelled => (
          colors.inkFaint,
          context.l10n.tournamentStatusCancelled,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: ink, width: AppSpacing.border - 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: ink, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A countdown to a server deadline.
///
/// ## Why it ticks locally rather than polling
///
/// The deadline is an absolute timestamp on the server clock, so counting down
/// to it needs no network at all — and asking the server every second for a
/// number the client can compute would be the worst possible use of a socket
/// connection. When the deadline passes, [onElapsed] fires once so the screen
/// can re-read the thing that has presumably just changed.
class TournamentCountdown extends StatefulWidget {
  /// Creates a countdown.
  const TournamentCountdown({
    required this.label,
    required this.deadlineMs,
    this.onElapsed,
    super.key,
  });

  /// What the countdown is to, shown before the clock.
  final String label;

  /// The moment, in milliseconds since epoch.
  final int deadlineMs;

  /// Called once, when the deadline passes.
  final VoidCallback? onElapsed;

  @override
  State<TournamentCountdown> createState() => _TournamentCountdownState();
}

class _TournamentCountdownState extends State<TournamentCountdown> {
  Timer? _ticker;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});

      if (!_fired && _remaining <= Duration.zero) {
        _fired = true;
        widget.onElapsed?.call();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration get _remaining {
    final int ms =
        widget.deadlineMs - DateTime.now().millisecondsSinceEpoch;
    return ms <= 0 ? Duration.zero : Duration(milliseconds: ms);
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final Duration left = _remaining;

    String two(int value) => value.toString().padLeft(2, '0');
    final String clock = left.inHours > 0
        ? '${left.inHours}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}'
        : '${two(left.inMinutes)}:${two(left.inSeconds % 60)}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.schedule, size: 15, color: colors.inkSoft),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '${widget.label} $clock',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: left.inSeconds <= 30 ? colors.warning : colors.inkSoft,
                fontWeight:
                    left.inSeconds <= 30 ? FontWeight.w700 : FontWeight.w400,
              ),
        ),
      ],
    );
  }
}

/// How full a tournament is, split by who the players actually are.
///
/// Never a single total. "3 / 4" on a tournament that is one person and two
/// robots would be true and misleading at the same time, which is exactly what
/// the product forbids — so the human count leads and the AI count sits beside
/// it in its own colour.
class TournamentPlayerCounts extends StatelessWidget {
  /// Creates the counts.
  const TournamentPlayerCounts({required this.tournament, super.key});

  /// What to describe.
  final AutoTournament tournament;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.person_outline, size: 15, color: colors.inkSoft),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${tournament.humanPlayerCount} '
              '${context.l10n.tournamentHumanPlayers}',
              style: text.bodySmall?.copyWith(color: colors.ink),
            ),
          ],
        ),
        if (tournament.botPlayerCount > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('🤖', style: text.bodySmall),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${tournament.botPlayerCount} '
                '${context.l10n.tournamentAiPlayers}',
                style: text.bodySmall?.copyWith(color: colors.accentPurple),
              ),
            ],
          ),
        Text(
          '${tournament.totalPlayers} / ${tournament.minPlayers}'
          '–${tournament.maxPlayers}',
          style: text.bodySmall?.copyWith(color: colors.inkFaint),
        ),
      ],
    );
  }
}

/// One entrant: avatar, name, and the AI badge where one is due.
///
/// Every list of participants in the app goes through this, which is what
/// makes "do not show AI bots as real humans" true by construction rather than
/// by each screen remembering.
class TournamentPlayerLine extends StatelessWidget {
  /// Creates a line.
  const TournamentPlayerLine({
    required this.player,
    this.trailing,
    this.dense = false,
    super.key,
  });

  /// Who to draw.
  final TournamentParticipant player;

  /// Anything to put on the right — a seed, a score, a placement.
  final Widget? trailing;

  /// Tighter spacing, for a bracket cell.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    final double size = dense ? 24 : 32;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: dense ? 2 : AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          if (player.isBot)
            // A drawn glyph rather than a player avatar. An AI with a normal
            // avatar reads as a person at a glance, which is the exact glance
            // this feature has to survive.
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.paperShade,
                border: Border.all(color: colors.ink, width: AppSpacing.border - 0.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text('🤖', style: TextStyle(fontSize: size * 0.5)),
            )
          else
            PlayerAvatar(
              avatarId: player.avatarId,
              colorIndex: player.avatarColorIndex,
              size: size,
              dimmed: player.isEliminated,
            ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  player.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: (dense ? text.bodySmall : text.bodyMedium)?.copyWith(
                    color: player.isEliminated ? colors.inkFaint : colors.ink,
                    // The reader's own row, marked the way every other list in
                    // the app marks it.
                    fontWeight:
                        player.isSelf ? FontWeight.w700 : FontWeight.w400,
                    decoration:
                        player.isEliminated ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (player.isBot && !dense)
                  Text(
                    player.botDifficulty == null
                        ? context.l10n.tournamentAiPlayer
                        : '${context.l10n.tournamentAiPlayer} · '
                            '${player.botDifficulty!.label}',
                    style: text.bodySmall?.copyWith(color: colors.accentPurple),
                  ),
              ],
            ),
          ),
          if (player.isWinner) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.emoji_events, size: 18, color: colors.accentYellow),
          ],
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A simple hand-drawn trophy, for the empty and finished states.
///
/// A painted shape rather than an image asset: it has to tint with the theme,
/// and it is two dozen lines against another file in the bundle.
class TrophyMark extends StatelessWidget {
  /// Creates the mark.
  const TrophyMark({this.size = 48, this.color, super.key});

  /// Width and height.
  final double size;

  /// Ink colour. Defaults to the soft ink.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TrophyPainter(color ?? context.sketch.inkSoft),
    );
  }
}

class _TrophyPainter extends CustomPainter {
  const _TrophyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;

    // The cup.
    final Path cup = Path()
      ..moveTo(w * 0.3, h * 0.16)
      ..lineTo(w * 0.7, h * 0.16)
      ..lineTo(w * 0.66, h * 0.48)
      ..quadraticBezierTo(w * 0.5, h * 0.62, w * 0.34, h * 0.48)
      ..close();
    canvas.drawPath(cup, pen);

    // The handles.
    canvas.drawArc(
      Rect.fromLTWH(w * 0.14, h * 0.18, w * 0.2, h * 0.24),
      0.4,
      2.6,
      false,
      pen,
    );
    canvas.drawArc(
      Rect.fromLTWH(w * 0.66, h * 0.18, w * 0.2, h * 0.24),
      -0.4 - 2.6,
      2.6,
      false,
      pen,
    );

    // Stem and base.
    canvas.drawLine(Offset(w * 0.5, h * 0.6), Offset(w * 0.5, h * 0.76), pen);
    canvas.drawLine(Offset(w * 0.32, h * 0.82), Offset(w * 0.68, h * 0.82), pen);
    canvas.drawLine(Offset(w * 0.38, h * 0.76), Offset(w * 0.62, h * 0.76), pen);
    canvas.drawLine(Offset(w * 0.38, h * 0.76), Offset(w * 0.32, h * 0.82), pen);
    canvas.drawLine(Offset(w * 0.62, h * 0.76), Offset(w * 0.68, h * 0.82), pen);
  }

  @override
  bool shouldRepaint(_TrophyPainter oldDelegate) => oldDelegate.color != color;
}
