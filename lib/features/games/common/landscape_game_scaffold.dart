import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The frame every landscape game is played inside.
///
/// ## Landscape is a lock, not a preference
///
/// [SystemChrome.setPreferredOrientations] is applied on the way in and undone
/// on the way out, so the rest of the app — which is portrait-shaped and has
/// no business being sideways — is unaffected. Undoing it is in `dispose`
/// rather than in a back handler because there are several ways off a game
/// screen (back, a pop from the router, a result screen replacing this one)
/// and only one of them is a button.
///
/// The orientation is restored to *unrestricted* rather than to portrait: the
/// app never locked it in the first place, and pinning it on the way out would
/// leave a tablet unable to rotate after its first match.
///
/// ## Why not just design for portrait and rotate
///
/// Because a card table, a bar and a ship's deck are all wider than they are
/// tall, and a portrait layout turned sideways is a column of things in a row.
/// Everything below assumes width is the abundant axis: seats fan across the
/// top, the player's own hand spans the bottom, and the panels that would be
/// full-screen sheets in portrait are overlays that leave the table visible —
/// because a chat panel that hides the game is a chat panel nobody opens
/// during a turn.
///
/// ## Scaling
///
/// Everything is laid out against [GameMetrics], derived once per build from
/// the shortest side. A phone at 360×800 rotated and a tablet at 1280×800 are
/// the same layout at two sizes rather than two layouts — which is what keeps
/// a 20:9 phone and a 4:3 tablet from needing separate code.
class LandscapeGameScaffold extends StatefulWidget {
  const LandscapeGameScaffold({
    required this.skin,
    required this.table,
    this.hud,
    this.overlay,
    this.connection = ConnectionStatus.connected,
    this.onLeave,
    this.leaveMessage,
    super.key,
  });

  /// The game being played. Installs [GameSkinScope] for everything below.
  final GameSkin skin;

  /// The game itself: the table, the ship, whatever is being played on.
  ///
  /// Laid out to fill, behind the HUD, so a table can bleed to the edges of
  /// the screen and the HUD can float on top of it.
  final Widget table;

  /// The persistent furniture: timers, scores, buttons. Drawn over [table].
  final Widget? hud;

  /// A full-bleed layer above everything — a result card, a role reveal, a
  /// meeting. Ignores safe areas, because a takeover should take over.
  final Widget? overlay;

  /// Drives the reconnect curtain. The game keeps running underneath it.
  final ConnectionStatus connection;

  /// Called when the player confirms they want out. Null hides the control.
  final VoidCallback? onLeave;

  /// What the confirmation asks. Games phrase this differently, because
  /// leaving a card game and abandoning a crew are not the same act.
  final String? leaveMessage;

  @override
  State<LandscapeGameScaffold> createState() => _LandscapeGameScaffoldState();
}

class _LandscapeGameScaffoldState extends State<LandscapeGameScaffold> {
  @override
  void initState() {
    super.initState();
    unawaitedOrientation(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Back to unrestricted, not to portrait: see the class comment.
    unawaitedOrientation(DeviceOrientation.values);
    super.dispose();
  }

  /// Applies an orientation preference without awaiting it.
  ///
  /// The future completes when the platform has acknowledged the change, which
  /// is of no interest to either call site — and awaiting it in `dispose` is
  /// not allowed anyway.
  void unawaitedOrientation(List<DeviceOrientation> orientations) {
    SystemChrome.setPreferredOrientations(orientations);
  }

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = widget.skin;

    return GameSkinScope(
      skin: skin,
      child: Scaffold(
        backgroundColor: skin.backdrop.last,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final GameMetrics metrics = GameMetrics.of(constraints);

            return GameMetricsScope(
              metrics: metrics,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // The room the table stands in. Its own layer so a table can
                  // be translucent over it without compositing against black.
                  _Backdrop(skin: skin),

                  // The game. Inside a SafeArea because a notch on a rotated
                  // phone sits over exactly the side of the table where a
                  // player's own hand goes.
                  SafeArea(child: widget.table),

                  if (widget.hud != null) SafeArea(child: widget.hud!),

                  if (widget.overlay != null) widget.overlay!,

                  // Above everything, including a takeover: a player who has
                  // lost the server needs to know before they try to act on
                  // whatever the takeover is asking them.
                  _ConnectionCurtain(status: widget.connection, skin: skin),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The lit room behind the table.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.skin});

  final GameSkin skin;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          // High and slightly back, like a fixture over a table rather than a
          // spotlight in front of one.
          center: const Alignment(0, -0.55),
          radius: 1.15,
          colors: <Color>[skin.backdrop.first, skin.backdrop.last],
          stops: const <double>[0, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.5),
            radius: 0.72,
            colors: <Color>[
              // A wash of the game's own light, strong enough to read as a
              // source and weak enough that text over it stays legible.
              skin.glow.withValues(alpha: 0.13),
              skin.glow.withValues(alpha: 0),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Says the connection is gone, without taking the game away.
///
/// A scrim rather than a replacement screen, and that is the whole point: the
/// server is still running the match, the player is still in it, and a
/// reconnect that lands two seconds later should find them where they were.
/// Throwing them back to the lobby for a dropped packet loses a match nobody
/// had to lose.
class _ConnectionCurtain extends StatelessWidget {
  const _ConnectionCurtain({required this.status, required this.skin});

  final ConnectionStatus status;
  final GameSkin skin;

  @override
  Widget build(BuildContext context) {
    final (String headline, String detail, bool spinning) = switch (status) {
      ConnectionStatus.connected || ConnectionStatus.idle =>
        ('', '', false),
      ConnectionStatus.connecting => ('Connecting', 'Finding the table.', true),
      ConnectionStatus.reconnecting =>
        ('Connection lost', 'Reconnecting — your seat is being held.', true),
      ConnectionStatus.disconnected =>
        ('Disconnected', 'You have left the table.', false),
      ConnectionStatus.failed =>
        ('Cannot reach the server', 'Check your connection and try again.', false),
    };

    if (headline.isEmpty) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        // Not interactive: there is nothing to press and nothing to decide.
        // Blocking taps would also block the game underneath from receiving a
        // gesture that will be perfectly valid a moment from now.
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.62),
          child: Center(
            child: _CurtainCard(
              headline: headline,
              detail: detail,
              spinning: spinning,
              skin: skin,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurtainCard extends StatelessWidget {
  const _CurtainCard({
    required this.headline,
    required this.detail,
    required this.spinning,
    required this.skin,
  });

  final String headline;
  final String detail;
  final bool spinning;
  final GameSkin skin;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: skin.edge, width: AppSpacing.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (spinning)
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: skin.accent),
            )
          else
            Icon(Icons.cloud_off_rounded, color: skin.danger, size: 28),
          const SizedBox(height: AppSpacing.md),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(
              color: skin.ink,
              fontFamily: skin.display,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: skin.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Every size a landscape game lays itself out against.
///
/// ## Why one object and not a pile of `MediaQuery` reads
///
/// Because the three games need the same handful of numbers, and each of them
/// needs them in twenty places. Deriving them once and passing them down means
/// a card is 1.42 × the seat radius everywhere rather than in most places, and
/// it means the phone and the tablet differ by one number rather than by a
/// scatter of conditionals.
///
/// All of it is driven off the **shortest side**, which in landscape is the
/// height. Scaling off width would make a 20:9 phone lay out its table as if
/// it were a tablet, and everything would fall off the bottom.
@immutable
class GameMetrics {
  const GameMetrics({
    required this.size,
    required this.scale,
    required this.gutter,
    required this.seatRadius,
    required this.cardHeight,
  });

  factory GameMetrics.of(BoxConstraints constraints) {
    final Size size = Size(constraints.maxWidth, constraints.maxHeight);
    final double shortest = size.shortestSide;

    // 360 is a rotated small phone. Everything is expressed as a multiple of
    // that, clamped so a large tablet does not render a deck of playing cards
    // the size of real ones.
    final double scale = (shortest / 360).clamp(0.85, 1.65);

    return GameMetrics(
      size: size,
      scale: scale,
      gutter: 12 * scale,
      seatRadius: 26 * scale,
      // Tall enough to read a rank and a suit at arm's length on a phone.
      cardHeight: 84 * scale,
    );
  }

  /// The box the game was given, safe areas not yet removed.
  final Size size;

  /// Multiply any fixed dimension by this.
  final double scale;

  /// The standard breathing room between the edge and anything in the HUD.
  final double gutter;

  /// Radius of an opponent's avatar around the table.
  final double seatRadius;

  /// Height of one playing card in the local player's hand.
  final double cardHeight;

  /// Cards are the standard poker ratio, which is what makes them read as
  /// cards rather than as rectangles with numbers on.
  double get cardWidth => cardHeight * 0.68;

  /// Whether there is enough width to keep a side panel open beside the table
  /// rather than floating it over the top.
  bool get hasRoomForPanel => size.width >= 900;
}

/// Reads the metrics the enclosing [LandscapeGameScaffold] derived.
class GameMetricsScope extends InheritedWidget {
  const GameMetricsScope({
    required this.metrics,
    required super.child,
    super.key,
  });

  final GameMetrics metrics;

  static GameMetrics of(BuildContext context) {
    final GameMetricsScope? scope =
        context.dependOnInheritedWidgetOfExactType<GameMetricsScope>();
    assert(scope != null, 'No GameMetricsScope above this widget.');
    return scope!.metrics;
  }

  @override
  bool updateShouldNotify(GameMetricsScope oldWidget) =>
      oldWidget.metrics.size != metrics.size;
}

/// Shorthand for reading the current metrics.
extension GameMetricsX on BuildContext {
  GameMetrics get metrics => GameMetricsScope.of(this);
}
