import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/repositories/impl/socket_chat_repository.dart';
import 'package:scribble_guess/repositories/impl/socket_drawing_repository.dart';
import 'package:scribble_guess/repositories/impl/socket_game_repository.dart';
import 'package:scribble_guess/repositories/impl/socket_room_repository.dart';
import 'package:scribble_guess/repositories/repositories.dart';
import 'package:scribble_guess/services/connectivity_service.dart';
import 'package:scribble_guess/services/local_leaderboard_repository.dart';
import 'package:scribble_guess/services/local_profile_repository.dart';
import 'package:scribble_guess/services/local_settings_repository.dart';
import 'package:scribble_guess/services/preferences_store.dart';
import 'package:scribble_guess/services/socket_service.dart';

/// Bootstrap values resolved in `main()` before the first frame.
///
/// Reading settings and the profile from disk is the one piece of async work
/// the whole app depends on, so it happens once at startup and is injected as
/// an override. Everything downstream is then synchronous, which keeps screens
/// free of `AsyncValue` plumbing for values that can never actually be absent.
final Provider<PreferencesStore> preferencesStoreProvider =
    Provider<PreferencesStore>(
  (Ref ref) => throw UnimplementedError(
    'preferencesStoreProvider must be overridden in main().',
  ),
);

/// The settings loaded at startup. Overridden in `main()`.
final Provider<AppSettings> bootstrapSettingsProvider = Provider<AppSettings>(
  (Ref ref) => throw UnimplementedError(
    'bootstrapSettingsProvider must be overridden in main().',
  ),
);

/// The profile loaded at startup, or `null` on a first run.
final Provider<PlayerProfile?> bootstrapProfileProvider =
    Provider<PlayerProfile?>(
  (Ref ref) => throw UnimplementedError(
    'bootstrapProfileProvider must be overridden in main().',
  ),
);

// ----------------------------------------------------------- local stores ---

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (Ref ref) => LocalSettingsRepository(ref.watch(preferencesStoreProvider)),
);

final Provider<LeaderboardRepository> leaderboardRepositoryProvider =
    Provider<LeaderboardRepository>(
  (Ref ref) => LocalLeaderboardRepository(ref.watch(preferencesStoreProvider)),
);

/// The profile store.
///
/// Local only. The server holds the authoritative copy of the name and avatar
/// — `AuthService.updateProfile` pushes changes to `PATCH /api/users/me` — and
/// this is the device's cache of it, so the first frame can render the right
/// name before any network call resolves.
final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>(
  (Ref ref) => LocalProfileRepository(ref.watch(preferencesStoreProvider)),
);

// --------------------------------------------------------- realtime layer ---

/// The game socket.
///
/// ## Why everything runs over one socket now
///
/// This app previously split its backend in two: Firestore was authoritative
/// for the game while a separate relay carried only the pencil, because
/// pushing dozens of stroke points a second through Firestore would have been
/// unusably slow and expensive.
///
/// The Node backend removes that split. It owns the whole game — rooms,
/// rounds, the word, the timer, scoring, chat and moderation — and the same
/// connection carries the strokes. One authority means there is no longer any
/// way for two sources of truth to disagree about whose turn it is (brief
/// section 71), and it is why the `Socket*Repository` implementations below
/// replace the Firebase ones wholesale.
///
/// Created once and kept for the life of the app: the socket survives moving
/// between lobby and game, and tearing it down between screens would drop the
/// board.
final Provider<RealtimeGateway> gatewayProvider = Provider<RealtimeGateway>(
  (Ref ref) {
    final SocketService service = SocketService()
      // A source, not a token: the session is established asynchronously at
      // startup, and a reconnect must present whatever is current then.
      ..setCredentials(
        tokenSource: () => ref.read(authServiceProvider).idToken(),
      );
    ref.onDispose(service.dispose);
    return service;
  },
);

/// Connection supervision: grace periods, retries and status.
final Provider<ConnectivityService> connectivityProvider =
    Provider<ConnectivityService>(
  (Ref ref) {
    final ConnectivityService service =
        ConnectivityService(gateway: ref.watch(gatewayProvider));
    ref.onDispose(service.dispose);
    return service;
  },
);

// ------------------------------------------------------ socket-backed data ---

final Provider<RoomRepository> roomRepositoryProvider = Provider<RoomRepository>(
  (Ref ref) {
    final RoomRepository repository =
        SocketRoomRepository(ref.watch(gatewayProvider));
    ref.onDispose(repository.dispose);
    return repository;
  },
);

final Provider<GameRepository> gameRepositoryProvider = Provider<GameRepository>(
  (Ref ref) {
    final GameRepository repository =
        SocketGameRepository(ref.watch(gatewayProvider));
    ref.onDispose(repository.dispose);
    return repository;
  },
);

final Provider<ChatRepository> chatRepositoryProvider = Provider<ChatRepository>(
  (Ref ref) {
    final ChatRepository repository =
        SocketChatRepository(ref.watch(gatewayProvider));
    ref.onDispose(repository.dispose);
    return repository;
  },
);

final Provider<DrawingRepository> drawingRepositoryProvider =
    Provider<DrawingRepository>(
  (Ref ref) {
    final DrawingRepository repository =
        SocketDrawingRepository(ref.watch(gatewayProvider));
    ref.onDispose(repository.dispose);
    return repository;
  },
);
