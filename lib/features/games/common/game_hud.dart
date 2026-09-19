import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The bar across the top of every landscape game.
///
/// Three slots — leave on the left, a headline in the middle, controls on the
/// right — because that is the arrangement a player's thumbs already expect
/// from a game held in landscape, and because the middle is the only place a
/// turn indicator can go without competing with either hand.
///
/// It floats over the table rather than pushing it down. A game that reserved
/// a strip for its chrome would be a game whose table shrank every time the
/// chrome grew.
class GameHudBar extends StatelessWidget {
  const GameHudBar({
    required this.title,
    this.headline,
    this.onLeave,
    this.actions = const <Widget>[],
    super.key,
  });

  /// The game's name. Small; it is orientation, not decoration.
  final String title;

  /// What is happening right now — whose turn, which phase, how long left.
  final Widget? headline;

  final VoidCallback? onLeave;

  /// Chat, voice, settings. Right-aligned, in reach of a right thumb.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          metrics.gutter,
          metrics.gutter * 0.6,
          metrics.gutter,
          0,
        ),
        child: Row(
          children: <Widget>[
            if (onLeave != null)
              GameIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Leave the table',
                onPressed: onLeave,
              ),
            SizedBox(width: metrics.gutter * 0.75),
            Text(
              title.toUpperCase(),
              style: text.labelMedium?.copyWith(
                color: skin.inkMuted,
                fontFamily: skin.display,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),

            // The headline takes whatever is left, so a long "Nervous Nancy is
            // choosing" does not push the controls off a narrow phone.
            Expanded(
              child: Center(
                child: headline ?? const SizedBox.shrink(),
              ),
            ),

            for (final Widget action in actions) ...<Widget>[
              action,
              SizedBox(width: metrics.gutter * 0.5),
            ],
          ],
        ),
      ),
    );
  }
}

/// A round control in the game's own colours.
///
/// Not [IconButton]: Material's default is 48×48 of mostly nothing with a grey
/// ripple, which on a dark table reads as a smudge. This one is visible
/// against a backdrop, has a rim, and keeps the 44-point touch target the
/// smaller visual circle would otherwise lose.
class GameIconButton extends StatelessWidget {
  const GameIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.badge,
    this.active = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// A small count — unread messages, players in voice.
  final int? badge;

  /// Draws it in the accent, for a control that is currently doing something.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final double side = 40 * metrics.scale;
    final bool enabled = onPressed != null;

    final Widget button = Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: active ? skin.accent : skin.surface.withValues(alpha: 0.86),
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? skin.accent : skin.edge,
              width: AppSpacing.border,
            ),
          ),
          child: Icon(
            icon,
            size: side * 0.5,
            color: active
                ? skin.accentInk
                : enabled
                    ? skin.ink
                    : skin.inkMuted,
          ),
        ),
      ),
    );

    if (badge == null || badge! <= 0) return button;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        button,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: skin.danger,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              badge! > 9 ? '9+' : '$badge',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: skin.ink,
                fontSize: 10 * metrics.scale,
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The "whose turn is it" strip in the middle of the HUD.
///
/// One line, because it is read in the half-second between looking up from a
/// hand and deciding what to do. A player who has to parse a sentence to learn
/// it is their turn has already lost the turn.
class GameHeadline extends StatelessWidget {
  const GameHeadline({
    required this.label,
    this.detail,
    this.urgent = false,
    this.mine = false,
    super.key,
  });

  final String label;
  final String? detail;

  /// Draws it in the danger colour — a countdown running out, a challenge.
  final bool urgent;

  /// Draws it in the accent: it is this player's move.
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final TextTheme text = Theme.of(context).textTheme;

    final Color tint = urgent
        ? skin.danger
        : mine
            ? skin.accent
            : skin.ink;

    return AnimatedContainer(
      duration: AppMotion.fast,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.gutter,
        vertical: metrics.gutter * 0.35,
      ),
      decoration: BoxDecoration(
        color: skin.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: mine || urgent ? tint : skin.edge,
          width: AppSpacing.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(
                color: tint,
                fontFamily: skin.display,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (detail != null) ...<Widget>[
            SizedBox(width: metrics.gutter * 0.5),
            Text(
              detail!,
              style: text.labelMedium?.copyWith(color: skin.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A countdown ring, driven by the server clock.
///
/// A ring rather than a number because it is read peripherally: a player
/// watching their own hand should register "nearly out of time" without
/// looking directly at it, and a shrinking arc does that where "7" does not.
class GameTimerRing extends StatelessWidget {
  const GameTimerRing({
    required this.remaining,
    required this.total,
    super.key,
  });

  final Duration remaining;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final double side = 38 * metrics.scale;

    final double fraction = total.inMilliseconds <= 0
        ? 0
        : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final int seconds = remaining.inSeconds.clamp(0, 999);
    final bool urgent = fraction <= 0.25;

    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: fraction,
              strokeWidth: 3 * metrics.scale,
              backgroundColor: skin.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                urgent ? skin.danger : skin.accent,
              ),
            ),
          ),
          Text(
            '$seconds',
            style: TextStyle(
              color: urgent ? skin.danger : skin.ink,
              fontFamily: skin.display,
              fontWeight: FontWeight.w800,
              fontSize: 13 * metrics.scale,
            ),
          ),
        ],
      ),
    );
  }
}
