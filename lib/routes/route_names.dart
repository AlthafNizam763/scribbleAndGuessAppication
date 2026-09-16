/// Every navigable destination, as a name/path pair.
///
/// Screens navigate by name (`context.goNamed(AppRoutes.lobby)`) so the paths
/// stay an implementation detail of the router.
abstract final class AppRoutes {
  /// Decides where the player belongs and redirects; never stays on screen.
  static const String splash = 'splash';
  static const String splashPath = '/';

  /// Name and avatar. Also the first stop when no profile exists yet.
  static const String profile = 'profile';
  static const String profilePath = '/profile';

  /// The main menu.
  static const String home = 'home';
  static const String homePath = '/home';

  /// Room rules before hosting.
  static const String createRoom = 'createRoom';
  static const String createRoomPath = '/create';

  /// Room code entry.
  static const String joinRoom = 'joinRoom';
  static const String joinRoomPath = '/join';

  /// The waiting room.
  static const String lobby = 'lobby';
  static const String lobbyPath = '/lobby';

  /// Canvas, chat and scoreboard.
  static const String game = 'game';
  static const String gamePath = '/game';

  /// Round and final standings.
  static const String result = 'result';
  static const String resultPath = '/result';

  /// World, friends and locality rankings.
  static const String leaderboard = 'leaderboard';
  static const String leaderboardPath = '/leaderboard';

  /// Friends, requests and blocked players.
  static const String friends = 'friends';
  static const String friendsPath = '/friends';

  /// Incoming and outgoing friend requests.
  static const String friendRequests = 'friendRequests';
  static const String friendRequestsPath = '/friends/requests';

  /// Another player's profile.
  ///
  /// The only parameterised route in the app. The id comes from a leaderboard
  /// row, a search result or a request, and is the server-issued player id —
  /// the same one every room seat and score is keyed by.
  static const String playerProfile = 'playerProfile';
  static const String playerProfilePath = '/player/:userId';

  /// Open public rooms waiting for players.
  static const String publicRooms = 'publicRooms';
  static const String publicRoomsPath = '/rooms';

  /// Invitations to other people's rooms.
  ///
  /// Declared as its own top-level route rather than as a child of /rooms,
  /// because it is reached from the home badge and from a notification, not by
  /// browsing — the same argument the friend requests route makes.
  static const String roomInvitations = 'roomInvitations';
  static const String roomInvitationsPath = '/rooms/invitations';

  /// Plays back one finished turn's drawing.
  ///
  /// Parameterised by game and turn, both of which the result screen holds —
  /// nothing in the protocol ever puts a round document id on the wire, so the
  /// pair is what a client can actually name.
  static const String replay = 'replay';
  static const String replayPath = '/replay/:gameId/:turnNumber';

  /// The trophy case and XP bar.
  ///
  /// Reached from the profile and from an unlocked-achievement notification.
  static const String achievements = 'achievements';
  static const String achievementsPath = '/achievements';

  /// The notification centre.
  ///
  /// Reached from the bell in the home app bar and from a tapped in-app
  /// banner. A top-level route rather than a child of anything, for the same
  /// reason the friend requests and invitations routes are: it is a
  /// destination, not a step in a flow.
  static const String notifications = 'notifications';
  static const String notificationsPath = '/notifications';

  /// Scheduled events and their boards.
  ///
  /// A top-level route: a tournament is a destination somebody goes to, not a
  /// step inside the play flow.
  static const String tournaments = 'tournaments';
  static const String tournamentsPath = '/tournaments';

  /// One tournament: its roster, its rules and its bracket.
  ///
  /// A pushed route rather than an expanding card, unlike the points events
  /// beside it. A knockout has a roster, a countdown, a set of rules and a
  /// bracket that grows to four rounds — more than fits under a list row, and
  /// it is also the screen a player sits on while waiting to be called to a
  /// match.
  static const String tournamentDetail = 'tournamentDetail';
  static const String tournamentDetailPath = '/tournaments/:tournamentId';

  /// Solo practice: a canvas, a word and a clock, with no room and no server.
  ///
  /// A top-level route with no parameters, because a practice turn has no
  /// state worth restoring: leaving abandons it, and arriving starts a new one.
  static const String practice = 'practice';
  static const String practicePath = '/practice';

  /// App preferences.
  static const String settings = 'settings';
  static const String settingsPath = '/settings';

  /// The rules of the game.
  static const String howToPlay = 'howToPlay';
  static const String howToPlayPath = '/how-to-play';

  /// Terminal failures that need an explanation and a way out.
  static const String error = 'error';
  static const String errorPath = '/error';
}
