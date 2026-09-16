import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/data/api/auth_api.dart';
import 'package:scribble_guess/data/api/health_api.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/settings_provider.dart';
import 'package:scribble_guess/services/auth_service.dart';
import 'package:scribble_guess/services/secure_token_store.dart';

/// Authentication state (§6).
///
/// The player id is the single most load-bearing value in the app: the server
/// keys every room seat, score and drawer check by it. So it is exposed here
/// once, from the session the *server* issued, and never derived from anything
/// the client made up.

/// The REST transport.
///
/// Kept for the life of the app so the connection pool is reused, and rebuilt
/// only if [apiBaseUrlProvider] changes — which happens when the player edits
/// the server address in settings. Rebuilding then is the point: the client
/// must not keep talking to the old origin while the socket moves to the new
/// one. The token source is read lazily on every request, because the session
/// is established asynchronously after the first frame.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  final ApiClient client = ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    tokenSource: () => ref.read(authServiceProvider).idToken(),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// The auth endpoints.
final Provider<AuthApi> authApiProvider = Provider<AuthApi>(
  (Ref ref) => AuthApi(ref.watch(apiClientProvider)),
);

/// `GET /api/health`, for diagnosing a failure after it has happened.
///
/// Shares [apiClientProvider], so it always asks whichever REST origin the
/// rest of the app is using. Never used to decide whether the game can start —
/// that is the socket's job, and this endpoint is on a different host.
final Provider<HealthApi> healthApiProvider = Provider<HealthApi>(
  (Ref ref) => HealthApi(ref.watch(apiClientProvider)),
);

/// Keystore-backed storage for the session token.
///
/// The JWT is a bearer credential, so it does not sit in `SharedPreferences`
/// alongside the theme choice. A token written by an older build is migrated
/// out of preferences on first read.
final Provider<SecureTokenStore> secureTokenStoreProvider =
    Provider<SecureTokenStore>(
  (Ref ref) => SecureTokenStore(fallback: ref.watch(preferencesStoreProvider)),
);

/// The session.
final Provider<AuthService> authServiceProvider = Provider<AuthService>((
  Ref ref,
) {
  final AuthService service = AuthService(
    api: ref.watch(authApiProvider),
    store: ref.watch(preferencesStoreProvider),
    tokens: ref.watch(secureTokenStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// The signed-in player, or null before the session resolves.
///
/// Emits on sign-in and sign-out, so anything watching it rebuilds when the
/// identity genuinely changes.
final StreamProvider<PlayerProfile?> authStateProvider =
    StreamProvider<PlayerProfile?>(
  (Ref ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// The signed-in player's id, or an empty string before sign-in completes.
///
/// Deliberately a plain [String] rather than an `AsyncValue`: by the time any
/// screen reads it the splash step has already ensured a session exists, and
/// making every consumer unwrap an async value for something that is
/// effectively always present would be noise.
final Provider<String> currentUserIdProvider = Provider<String>((Ref ref) {
  final AsyncValue<PlayerProfile?> auth = ref.watch(authStateProvider);
  return auth.valueOrNull?.id ??
      ref.watch(authServiceProvider).currentUserId ??
      '';
});

/// Whether a session exists.
final Provider<bool> isSignedInProvider = Provider<bool>(
  (Ref ref) => ref.watch(currentUserIdProvider).isNotEmpty,
);

/// Whether the session is a guest rather than a linked account.
final Provider<bool> isAnonymousProvider = Provider<bool>((Ref ref) {
  ref.watch(authStateProvider);
  return ref.watch(authServiceProvider).isAnonymous;
});
