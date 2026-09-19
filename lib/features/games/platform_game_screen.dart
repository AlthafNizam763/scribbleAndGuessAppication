import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/features/games/bluff_bar/bluff_bar_game_screen.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/features/games/kazhutha/kazhutha_game_screen.dart';
import 'package:scribble_guess/features/games/ludo/ludo_game_screen.dart';
import 'package:scribble_guess/features/games/space_mystery/space_mystery_game_screen.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The front door to a match, for whichever platform game is being played.
///
/// ## What this is for
///
/// Three things, none of which belong in a game screen:
///
/// 1. **Picking the game.** One route serves all of them, because everything
///    that differs is inside the screen it dispatches to.
/// 2. **Guarding the entrance.** A player can reach this route with no session
///    behind it — a deep link, a cold start on a restored route, a rebuild
///    after the app was killed in the background. None of the game screens
///    should have to cope with having no room, so none of them are built until
///    there is one.
/// 3. **Waiting for the deal.** Between the last player readying up and the
///    first projection arriving there is a real gap, and a table drawn from an
///    empty state during it would flash an empty hand.
class PlatformGameScreen extends ConsumerWidget {
  const PlatformGameScreen({required this.gameId, super.key});

  final GameId gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlatformSession session = ref.watch(platformSessionProvider);

    // No room at all. Not an error — it is what a deep link into a match that
    // has ended looks like — so it offers the way back rather than an alarm.
    if (session.room == null) {
      return _Waiting(
        gameId: gameId,
        headline: 'No game in progress',
        detail: 'Start one from the lobby and this is where you will land.',
        showExit: true,
      );
    }

    if (!session.hasMatch) {
      return _Waiting(
        gameId: gameId,
        headline: 'Dealing',
        detail: 'Waiting for the server to start the match.',
        showExit: false,
      );
    }

    return switch (gameId) {
      GameId.kazhutha => const KazhuthaGameScreen(),
      GameId.bluffBar => const BluffBarGameScreen(),
      GameId.spaceMystery => const SpaceMysteryGameScreen(),
      GameId.ludo => const LudoGameScreen(),
      // Scribble & Guess has its own mature room and game services and never
      // travels through the platform layer at all — see the catalogue. Landing
      // here means a deep link went astray rather than a missing screen.
      GameId.scribbleGuess => _Waiting(
          gameId: gameId,
          headline: 'Scribble & Guess is played elsewhere',
          detail: 'Open it from the games list.',
          showExit: true,
        ),
    };
  }
}

/// The landscape holding screen, in the game's own colours.
///
/// Dressed rather than a bare spinner: this is the first thing a player sees
/// after pressing start, and a grey circle on white would undo the atmosphere
/// the table is about to establish.
class _Waiting extends ConsumerWidget {
  const _Waiting({
    required this.gameId,
    required this.headline,
    required this.detail,
    required this.showExit,
  });

  final GameId gameId;
  final String headline;
  final String detail;
  final bool showExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameSkin skin = GameSkin.of(gameId);

    return LandscapeGameScaffold(
      skin: skin,
      connection: ref.watch(platformSessionProvider).connection,
      table: Builder(
        builder: (BuildContext context) {
          final TextTheme text = Theme.of(context).textTheme;

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (!showExit)
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: skin.accent,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: text.titleLarge?.copyWith(
                      color: skin.ink,
                      fontFamily: skin.display,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: skin.inkMuted),
                  ),
                  if (showExit) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: 'Back to games',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => context.goNamed(AppRoutes.home),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
