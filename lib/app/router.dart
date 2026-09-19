import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/features/auth/login_screen.dart';
import 'package:scribble_guess/features/auth/register_screen.dart';
import 'package:scribble_guess/features/create_room/create_room_screen.dart';
import 'package:scribble_guess/features/error/error_screen.dart';
import 'package:scribble_guess/features/friends/friend_requests_screen.dart';
import 'package:scribble_guess/features/friends/friends_screen.dart';
import 'package:scribble_guess/features/friends/player_profile_screen.dart';
import 'package:scribble_guess/features/game/game_screen.dart';
import 'package:scribble_guess/features/game_hub/game_lobby_screen.dart';
import 'package:scribble_guess/features/games/platform_game_screen.dart';
import 'package:scribble_guess/features/home/home_screen.dart';
import 'package:scribble_guess/features/how_to_play/how_to_play_screen.dart';
import 'package:scribble_guess/features/join_room/join_room_screen.dart';
import 'package:scribble_guess/features/leaderboard/leaderboard_screen.dart';
import 'package:scribble_guess/features/lobby/lobby_screen.dart';
import 'package:scribble_guess/features/notifications/notifications_screen.dart';
import 'package:scribble_guess/features/practice/practice_screen.dart';
import 'package:scribble_guess/features/profile/edit_profile_screen.dart';
import 'package:scribble_guess/features/profile/profile_screen.dart';
import 'package:scribble_guess/features/progression/achievements_screen.dart';
import 'package:scribble_guess/features/replay/drawing_replay_screen.dart';
import 'package:scribble_guess/features/result/result_screen.dart';
import 'package:scribble_guess/features/rooms/public_rooms_screen.dart';
import 'package:scribble_guess/features/rooms/room_invitations_screen.dart';
import 'package:scribble_guess/features/settings/settings_screen.dart';
import 'package:scribble_guess/features/splash/splash_screen.dart';
import 'package:scribble_guess/features/tournaments/tournament_detail_screen.dart';
import 'package:scribble_guess/features/tournaments/tournaments_screen.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';

/// The navigator every route is pushed onto.
///
/// Held as an explicit key rather than left to go_router because one thing in
/// this app sits *above* the router and still has to open a dialog: the room
/// invitation listener in `app.dart`. It is mounted in `MaterialApp.builder`,
/// which runs outside the Navigator, so `showDialog(context: context)` there
/// would have nothing to push onto. The key is the way back in.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// The app's route table.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splashPath,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splashPath,
        name: AppRoutes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.loginPath,
        name: AppRoutes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.registerPath,
        name: AppRoutes.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.profilePath,
        name: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        // Declared as its own top-level route rather than as a child of
        // `/profile`, so the redirect below can name it directly — a child
        // route would be matched on the full path either way, and nesting it
        // would only add a parent this screen does not need.
        path: AppRoutes.editProfilePath,
        name: AppRoutes.editProfile,
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.homePath,
        name: AppRoutes.home,
        builder: (_, _) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.gameLobbyPath,
        name: AppRoutes.gameLobby,
        builder: (_, GoRouterState state) {
          final GameId? gameId = GameId.fromWire(state.pathParameters['gameId'] ?? '');
          return gameId == null
              ? const ErrorScreen()
              : GameLobbyScreen(
                  game: GameCatalog.byId(gameId),
                  // `?mode=stupid` carries the intent from a PLAY WITH STUPID
                  // tap. A query parameter rather than a path segment because
                  // it is a preference about this visit, not a different
                  // screen — and a deep link that omits it still lands
                  // somewhere sensible.
                  wantsStupids: state.uri.queryParameters['mode'] == 'stupid',
                );
        },
      ),
      GoRoute(
        path: AppRoutes.platformGamePath,
        name: AppRoutes.platformGame,
        builder: (_, GoRouterState state) {
          final GameId? gameId = GameId.fromWire(state.pathParameters['gameId'] ?? '');
          // An unknown id is a deep link from a newer build or a typo. The
          // error screen says so; a blank landscape table would not.
          return gameId == null
              ? const ErrorScreen()
              : PlatformGameScreen(gameId: gameId);
        },
      ),
      GoRoute(
        path: AppRoutes.createRoomPath,
        name: AppRoutes.createRoom,
        builder: (_, _) => const CreateRoomScreen(),
      ),
      GoRoute(
        path: AppRoutes.joinRoomPath,
        name: AppRoutes.joinRoom,
        builder: (_, _) => const JoinRoomScreen(),
      ),
      GoRoute(
        path: AppRoutes.lobbyPath,
        name: AppRoutes.lobby,
        builder: (_, _) => const LobbyScreen(),
      ),
      GoRoute(
        path: AppRoutes.gamePath,
        name: AppRoutes.game,
        builder: (_, _) => const GameScreen(),
      ),
      GoRoute(
        path: AppRoutes.resultPath,
        name: AppRoutes.result,
        builder: (_, _) => const ResultScreen(),
      ),
      GoRoute(
        path: AppRoutes.leaderboardPath,
        name: AppRoutes.leaderboard,
        builder: (_, _) => const LeaderboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.friendsPath,
        name: AppRoutes.friends,
        builder: (_, _) => const FriendsScreen(),
      ),
      GoRoute(
        // Declared as its own top-level route rather than as a child of
        // `/friends`, so it opens as a full screen from the home badge instead
        // of as a tab somebody has to find.
        path: AppRoutes.friendRequestsPath,
        name: AppRoutes.friendRequests,
        builder: (_, _) => const FriendRequestsScreen(),
      ),
      GoRoute(
        path: AppRoutes.playerProfilePath,
        name: AppRoutes.playerProfile,
        builder: (_, GoRouterState state) => PlayerProfileScreen(
          // A deep link with no id lands on a profile that cannot load and
          // shows its error state, which is the same thing a deleted account
          // produces — rather than throwing out of the builder.
          userId: state.pathParameters['userId'] ?? '',
        ),
      ),
      GoRoute(
        // Declared before the parameterised invitations route below it only
        // for readability; go_router matches on the full path, so the two
        // cannot shadow each other.
        path: AppRoutes.publicRoomsPath,
        name: AppRoutes.publicRooms,
        builder: (_, _) => const PublicRoomsScreen(),
      ),
      GoRoute(
        path: AppRoutes.roomInvitationsPath,
        name: AppRoutes.roomInvitations,
        builder: (_, _) => const RoomInvitationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notificationsPath,
        name: AppRoutes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.replayPath,
        name: AppRoutes.replay,
        builder: (_, GoRouterState state) => DrawingReplayScreen(
          gameId: state.pathParameters['gameId'] ?? '',
          // A deep link with a nonsense turn lands on the screen's error
          // state, which is the same thing a deleted match produces — rather
          // than throwing out of the builder.
          turnNumber:
              int.tryParse(state.pathParameters['turnNumber'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        // Takes an optional `?userId=`, so one screen serves both the local
        // player's trophy case and somebody else's badges. Absent means the
        // local player, which is how it is reached from the profile.
        path: AppRoutes.achievementsPath,
        name: AppRoutes.achievements,
        builder: (_, GoRouterState state) =>
            AchievementsScreen(userId: state.uri.queryParameters['userId']),
      ),
      GoRoute(
        path: AppRoutes.tournamentsPath,
        name: AppRoutes.tournaments,
        builder: (_, _) => const TournamentsScreen(),
      ),
      GoRoute(
        path: AppRoutes.tournamentDetailPath,
        name: AppRoutes.tournamentDetail,
        builder: (_, GoRouterState state) => TournamentDetailScreen(
          // A deep link with no id lands on a screen that cannot load and
          // shows its error state — the same thing a tournament that has since
          // been swept produces, rather than throwing out of the builder.
          tournamentId: state.pathParameters['tournamentId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.practicePath,
        name: AppRoutes.practice,
        builder: (_, _) => const PracticeScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsPath,
        name: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.howToPlayPath,
        name: AppRoutes.howToPlay,
        builder: (_, _) => const HowToPlayScreen(),
      ),
      GoRoute(
        path: AppRoutes.errorPath,
        name: AppRoutes.error,
        builder: (_, _) => const ErrorScreen(),
      ),
    ],
    // A bad deep link lands on the same dead-end screen as any other terminal
    // failure, rather than go_router's debug page.
    errorBuilder: (_, _) => const ErrorScreen(),
    redirect: (BuildContext context, GoRouterState state) {
      final String location = state.matchedLocation;

      // The splash screen decides for itself where to go — it is the screen
      // that resolves the session in the first place, so a guard that ran
      // before it had an answer would bounce every cold start to sign-in.
      if (location == AppRoutes.splashPath) return null;

      // Sign-in gate. Nothing but the two auth screens is reachable without a
      // session, which is what keeps game state off the screen of somebody who
      // has not authenticated. Checked before the profile rule below, because
      // a player with neither needs the session first: the profile screen
      // writes to `/api/users/me`, which requires a token.
      // Read from the service rather than through `isSignedInProvider`.
      //
      // That provider is derived from `authStateProvider`, a stream, so its
      // cached value only refreshes once the session event has been delivered
      // — a microtask *after* sign-in returns. This callback runs during the
      // `goNamed` that sign-in performs, which is inside that window, and a
      // stale `false` here would bounce a player who just signed in
      // successfully straight back to the gate. `currentUserId` is the same
      // session, read synchronously, and is already the fallback that
      // provider uses.
      final bool signedIn =
          ref.read(authServiceProvider).currentUserId != null;
      final bool onAuthScreen =
          location == AppRoutes.loginPath || location == AppRoutes.registerPath;
      if (!signedIn) {
        return onAuthScreen ? null : AppRoutes.loginPath;
      }

      // A signed-in player has no business back on the gate. Registration is
      // the exception: it doubles as the guest upgrade path, which is reached
      // *from* a session and must stay open.
      if (location == AppRoutes.loginPath) {
        return AppRoutes.homePath;
      }

      // A player with no profile has nothing to play as, so every route except
      // the editor itself funnels back to it.
      //
      // The *editor*, not the card: somebody who has never chosen a name needs
      // the form, and the card would show them a record of nothing with an
      // Edit button as the only way forward. The card is excluded from the
      // funnel too, so the editor's own back arrow has somewhere to land once
      // a profile exists.
      final bool hasProfile = ref.read(hasProfileProvider);
      if (!hasProfile &&
          location != AppRoutes.editProfilePath &&
          !onAuthScreen) {
        return AppRoutes.editProfilePath;
      }
      return null;
    },
  );

  ref.onDispose(router.dispose);
  return router;
});
