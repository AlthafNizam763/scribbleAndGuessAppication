import 'package:flutter/material.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/games/space_mystery_state.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The card that tells a player which side they are on.
///
/// ## Why it is a takeover, and why it has to be dismissed
///
/// It is the one piece of information in the match that only this player has,
/// and the whole game proceeds from it. It covers the screen so it cannot be
/// missed, and it waits for a deliberate tap rather than timing out — because
/// a player whose phone was face down for three seconds must not end up
/// walking around a ship without knowing whether they are the traitor.
///
/// It also means the reveal is in the player's control, which matters when
/// somebody is playing next to somebody else.
///
/// ## Shown once
///
/// Roles do not change, so there is nothing to re-reveal. A player who wants
/// reminding has it in the HUD, small, for the rest of the match.
class RoleReveal extends StatefulWidget {
  const RoleReveal({
    required this.self,
    required this.room,
    required this.onDismissed,
    super.key,
  });

  final SpaceSelf self;
  final PlatformRoom? room;
  final VoidCallback onDismissed;

  @override
  State<RoleReveal> createState() => _RoleRevealState();
}

class _RoleRevealState extends State<RoleReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

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

    final bool traitor = widget.self.isTraitor;
    final Color tone = traitor ? skin.danger : skin.accent;

    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onDismissed,
        child: ColoredBox(
          color: skin.backdrop.last.withValues(alpha: 0.96),
          child: FadeTransition(
            opacity: _entrance,
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(metrics.gutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.7, end: 1).animate(
                        CurvedAnimation(
                          parent: _entrance,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: Container(
                        padding: EdgeInsets.all(metrics.gutter * 1.2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tone.withValues(alpha: 0.16),
                          border: Border.all(color: tone, width: 2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: tone.withValues(alpha: 0.4),
                              blurRadius: 30 * metrics.scale,
                            ),
                          ],
                        ),
                        child: Icon(
                          traitor
                              ? Icons.visibility_off_rounded
                              : Icons.handyman_rounded,
                          size: 44 * metrics.scale,
                          color: tone,
                        ),
                      ),
                    ),

                    SizedBox(height: metrics.gutter),
                    Text(
                      traitor ? 'TRAITOR' : 'CREW',
                      style: text.headlineMedium?.copyWith(
                        color: tone,
                        fontFamily: skin.display,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),

                    SizedBox(height: metrics.gutter * 0.6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Column(
                        children: <Widget>[
                          for (final String line in traitor
                              ? const <String>[
                                  'Sabotage the ship.',
                                  'Avoid suspicion.',
                                  'Thin out the crew.',
                                ]
                              : const <String>[
                                  'Finish the repairs.',
                                  'Work out who is not helping.',
                                  'Vote carefully.',
                                ])
                            Padding(
                              padding: EdgeInsets.only(bottom: metrics.gutter * 0.25),
                              child: Text(
                                line,
                                textAlign: TextAlign.center,
                                style: text.bodyLarge?.copyWith(color: skin.ink),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // The one fact a traitor is handed rather than working out.
                    if (traitor && widget.self.allies.isNotEmpty) ...<Widget>[
                      SizedBox(height: metrics.gutter),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.gutter,
                          vertical: metrics.gutter * 0.5,
                        ),
                        decoration: BoxDecoration(
                          color: skin.surface,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
                          border: Border.all(color: skin.danger),
                        ),
                        child: Column(
                          children: <Widget>[
                            Text(
                              'WORKING WITH',
                              style: text.labelSmall?.copyWith(
                                color: skin.inkMuted,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                            SizedBox(height: metrics.gutter * 0.25),
                            Text(
                              widget.self.allies
                                  .map((String id) =>
                                      widget.room?.seatOf(id)?.username ?? 'somebody')
                                  .join(', '),
                              style: text.bodyMedium?.copyWith(
                                color: skin.danger,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: metrics.gutter * 1.6),
                    Text(
                      'Tap anywhere to begin',
                      style: text.labelMedium?.copyWith(color: skin.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
