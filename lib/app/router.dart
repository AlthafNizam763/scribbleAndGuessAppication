import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/features/create_room/create_room_screen.dart';
import 'package:scribble_guess/features/error/error_screen.dart';
import 'package:scribble_guess/features/friends/friend_requests_screen.dart';
import 'package:scribble_guess/features/friends/friends_screen.dart';
import 'package:scribble_guess/features/friends/player_profile_screen.dart';
import 'package:scribble_guess/features/game/game_screen.dart';
import 'package:scribble_guess/features/home/home_screen.dart';
import 'package:scribble_guess/features/how_to_play/how_to_play_screen.dart';
import 'package:scribble_guess/features/join_room/join_room_screen.dart';
import 'package:scribble_guess/features/leaderboard/leaderboard_screen.dart';
import 'package:scribble_guess/features/lobby/lobby_screen.dart';
import 'package:scribble_guess/features/notifications/notifications_screen.dart';
import 'package:scribble_guess/features/practice/practice_screen.dart';
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
        path: AppRoutes.profilePath,
        name: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.homePath,
        name: AppRoutes.home,
        builder: (_, _) => const HomeScreen(),
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
      // A player with no profile has nothing to play as, so every route
      // except the profile screen itself funnels back to it.
      final bool hasProfile = ref.read(hasProfileProvider);
      final String location = state.matchedLocation;
      final bool exempt = location == AppRoutes.profilePath ||
          location == AppRoutes.splashPath;
      if (!hasProfile && !exempt) {
        return AppRoutes.profilePath;
      }
      return null;
    },
  );

  ref.onDispose(router.dispose);
  return router;
});
