import 'dart:async';

import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/constants/storage_keys.dart';
import 'package:scribble_guess/core/errors/app_exception.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/auth_api.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/services/preferences_store.dart';
import 'package:scribble_guess/services/secure_token_store.dart';

/// The session: who this device is signed in as, and the token that proves it.
///
/// ## What changed, and why the shape did not
///
/// This used to wrap `FirebaseAuth` and hand out anonymous uids. It now talks
/// to the game backend's `POST /api/auth/guest`. The method names are
/// unchanged — `ensureSignedIn`, `currentUserId`, `authStateChanges`,
/// `signOut` — because the splash screen, the auth providers and the profile
/// notifier are all written against them and there is no reason to churn
/// working screens over a change of transport.
///
/// ## Guests are real accounts
///
/// A guest is not a local pretend identity. It is a row in the backend's
/// `users` collection with a real id, and that id is what rooms, scores and
/// the leaderboard are keyed by. The token is kept in the platform keystore
/// (see [SecureTokenStore]) so a returning player keeps their history rather
/// than becoming a new stranger every launch.
///
/// ## Failure is not fatal
///
/// Everything returns a [Result] or logs and degrades. A player who opens the
/// app on a dead network should see the game's own "no connection" copy, not
/// a crash — the splash screen retries.
class AuthService {
  /// Creates a service backed by [api].
  ///
  /// The token goes to [tokens], which is the platform keystore; [store] holds
  /// only the cached profile this falls back to when signing in before the
  /// player has picked a name.
  AuthService({
    required AuthApi api,
    required PreferencesStore store,
    required SecureTokenStore tokens,
  })  : _api = api,
        _store = store,
        _tokens = tokens;

  final AuthApi _api;
  final PreferencesStore _store;
  final SecureTokenStore _tokens;

  final StreamController<PlayerProfile?> _sessionController =
      StreamController<PlayerProfile?>.broadcast();

  AuthSession? _session;
  Future<Result<AuthSession>>? _inFlight;
  bool _disposed = false;

  /// The signed-in player's id, or null before a session exists.
  String? get currentUserId {
    final String id = _session?.profile.id ?? '';
    return id.isEmpty ? null : id;
  }

  /// The signed-in player's identity, or null.
  PlayerProfile? get currentProfile => _session?.profile;

  /// Whether this session is a guest rather than a linked account.
  ///
  /// Read from the provider the *server* reports on every auth response, so a
  /// session resumed from a stored token reports what the account actually is
  /// rather than what this device last assumed. No session is treated as a
  /// guest, since every affordance this turns on is an offer to sign up.
  bool get isAnonymous => _session?.isGuest ?? true;

  /// Emits on sign-in and sign-out, replaying the current value first.
  ///
  /// Mirrors the shape of Firebase's `authStateChanges`, so the providers that
  /// watch it did not have to change.
  Stream<PlayerProfile?> authStateChanges() async* {
    yield _session?.profile;
    yield* _sessionController.stream;
  }

  /// The bearer token, or null when there is no session.
  ///
  /// Read live rather than captured by callers: the socket asks for it on
  /// every (re)connect, and a copy taken at startup would be the wrong one
  /// after a sign-out and back in.
  Future<String?> idToken({bool forceRefresh = false}) async {
    final String? token = _session?.token;
    if (token != null && token.isNotEmpty) return token;
    return _tokens.read();
  }

  /// Guarantees a session exists, creating a guest account if needed.
  ///
  /// Three paths, in order of preference: the session already in memory; a
  /// stored token, revalidated against the server; a brand-new guest account.
  /// The middle one is what makes a returning player keep their score.
  ///
  /// Concurrent calls share one attempt — the splash screen and `main()` both
  /// call this, and two guest accounts for one launch would be a real bug.
  Future<Result<AuthSession>> ensureSession({PlayerProfile? profile}) {
    if (_disposed) {
      return Future<Result<AuthSession>>.value(
        const Err<AuthSession>(
          Failure(AppErrorCode.invalidAction, 'The auth service was disposed.'),
        ),
      );
    }

    final AuthSession? existing = _session;
    if (existing != null && existing.isValid) {
      return Future<Result<AuthSession>>.value(Ok<AuthSession>(existing));
    }

    return _inFlight ??= _establish(profile).whenComplete(() {
      _inFlight = null;
    });
  }

  /// Establishes a session, throwing on failure.
  ///
  /// Kept for the call sites that predate [ensureSession] and simply want to
  /// await "a session exists" — the splash screen and `main()`.
  Future<PlayerProfile> ensureSignedIn({PlayerProfile? profile}) async {
    final Result<AuthSession> result = await ensureSession(profile: profile);
    return switch (result) {
      Ok<AuthSession>(:final AuthSession value) => value.profile,
      Err<AuthSession>(:final Failure failure) =>
        throw AppException(failure),
    };
  }

  /// Resumes a stored session, without creating an account if there is none.
  ///
  /// This is what the splash screen calls now that sign-in is a gate. The
  /// distinction from [ensureSession] is the whole point: that method's job is
  /// "there must be a session, invent one if necessary", which is exactly what
  /// a login screen must *not* do — a device arriving with no stored token has
  /// a person to ask, not a guest account to mint behind their back.
  ///
  /// Returns the resumed session, or null when the player must sign in.
  /// Throws nothing: a network failure is reported through [offline] so the
  /// splash can offer a retry rather than dumping somebody at a login form
  /// they cannot complete.
  Future<({AuthSession? session, bool offline})> resumeSession() async {
    final AuthSession? existing = _session;
    if (existing != null && existing.isValid) {
      return (session: existing, offline: false);
    }

    final String? stored = await _tokens.read();
    if (stored == null || stored.isEmpty) {
      return (session: null, offline: false);
    }

    final Result<AuthSession> revalidated = await _api.session(stored);

    if (revalidated case Ok<AuthSession>(:final AuthSession value)) {
      _adopt(value);
      AppLogger.i('AuthService: resumed session for ${value.profile.id}');
      unawaited(_reconcile(value, null));
      return (session: value, offline: false);
    }

    if (revalidated case Err<AuthSession>(:final Failure failure)) {
      // A network failure is temporary and must not cost the player their
      // account, nor push them to a login form that cannot reach the server.
      if (failure.code == AppErrorCode.network ||
          failure.code == AppErrorCode.timeout) {
        AppLogger.w('AuthService: could not reach the server to resume');
        return (session: null, offline: true);
      }
      AppLogger.w('AuthService: stored token rejected; sign-in required');
      await _tokens.delete();
    }

    return (session: null, offline: false);
  }

  /// Signs in with an email and password.
  Future<Result<AuthSession>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final Result<AuthSession> result =
        await _api.login(email: email, password: password);
    return _keep(result, 'signed in as');
  }

  /// Registers an email account, upgrading this device's guest if it has one.
  ///
  /// [username] names a brand-new account. On the upgrade path the server
  /// keeps the name the guest already chose and ignores it.
  Future<Result<AuthSession>> registerWithEmail({
    required String email,
    required String password,
    String? username,
    int? avatarId,
    int? avatarColorIndex,
  }) async {
    final Result<AuthSession> result = await _api.register(
      email: email,
      password: password,
      username: username,
      avatarId: avatarId,
      avatarColorIndex: avatarColorIndex,
    );
    return _keep(result, 'registered');
  }

  /// Creates a guest account and adopts it.
  ///
  /// The explicit form of what [ensureSession] used to do implicitly at
  /// launch: now it happens only when somebody taps "Continue as guest".
  Future<Result<AuthSession>> continueAsGuest({PlayerProfile? profile}) =>
      ensureSession(profile: profile);

  /// Stores and adopts a session from a successful auth call.
  Future<Result<AuthSession>> _keep(
    Result<AuthSession> result,
    String verb,
  ) async {
    if (result case Ok<AuthSession>(:final AuthSession value)) {
      await _tokens.write(value.token);
      _adopt(value);
      AppLogger.i('AuthService: $verb ${value.profile.id}');
    }
    return result;
  }

  /// Replaces the local session's profile after a rename or restyle.
  ///
  /// The server is told too, so other players see the new name; a failure to
  /// reach it is logged rather than blocking the local change, since the name
  /// is re-sent on the next socket handshake anyway.
  Future<Result<PlayerProfile>> updateProfile(PlayerProfile profile) async {
    final AuthSession? session = _session;
    if (session == null) {
      return const Err<PlayerProfile>(
        Failure(AppErrorCode.invalidAction, 'Not signed in.'),
      );
    }

    final Result<PlayerProfile> result = await _api.updateProfile(profile);

    if (result case Ok<PlayerProfile>(:final PlayerProfile value)) {
      _adopt(AuthSession(token: session.token, profile: value));
      return Ok<PlayerProfile>(value);
    }

    AppLogger.w('AuthService: could not push the profile to the server');
    return result;
  }

  /// Forgets the session on this device.
  ///
  /// The token goes first and is awaited: everything after it is best-effort
  /// tidying, and a failure part-way through must still leave a device that
  /// cannot authenticate. The other order would clear the *cache* and keep the
  /// credential, which is the wrong half.
  ///
  /// The cached profile goes too. It is what the sign-in screen falls back to
  /// when minting a guest, so leaving it behind would offer the next person to
  /// pick up this phone the last person's name and face.
  Future<void> signOut() async {
    await _tokens.delete();
    await _store.clearAll();

    _session = null;
    if (!_sessionController.isClosed) _sessionController.add(null);
  }

  /// Deletes this account on the server, then signs out.
  ///
  /// Irreversible, and ordered deliberately: the server call is awaited and
  /// its failure is returned *before* anything local is cleared. Clearing
  /// first would leave a player signed out of an account that still exists,
  /// with no session left to retry the deletion with.
  ///
  /// On success the local teardown is unconditional. The account is gone, so
  /// the token, the cached profile and the session stream are all describing
  /// something that no longer exists, and the redirect guard needs the stream
  /// to say so before it will let go of the authenticated screens.
  Future<Result<void>> deleteAccount() async {
    final Result<void> result = await _api.deleteAccount();
    if (result case Err<void>()) return result;

    await signOut();
    return const Ok<void>(null);
  }

  /// Closes the session stream.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_sessionController.close());
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Result<AuthSession>> _establish(PlayerProfile? profile) async {
    final String? stored = await _tokens.read();

    if (stored != null && stored.isNotEmpty) {
      final Result<AuthSession> revalidated = await _api.session(stored);

      if (revalidated case Ok<AuthSession>(:final AuthSession value)) {
        _adopt(value);
        AppLogger.i('AuthService: resumed session for ${value.profile.id}');
        // Not awaited: a returning player should reach the menu at the speed
        // of the session check, not of a repair that only sometimes runs.
        unawaited(_reconcile(value, profile));
        return Ok<AuthSession>(value);
      }

      if (revalidated case Err<AuthSession>(:final Failure failure)) {
        // A network failure is temporary and must not cost the player their
        // account: only a token the *server* rejected is discarded.
        if (failure.code == AppErrorCode.network ||
            failure.code == AppErrorCode.timeout) {
          AppLogger.w('AuthService: could not reach the server to resume');
          return Err<AuthSession>(failure);
        }
        AppLogger.w('AuthService: stored token rejected; creating a new guest');
        await _tokens.delete();
      }
    }

    final PlayerProfile identity = profile ?? _fallbackProfile();
    final Result<AuthSession> created = await _api.guest(identity);

    if (created case Ok<AuthSession>(:final AuthSession value)) {
      await _tokens.write(value.token);
      _adopt(value);
      AppLogger.i('AuthService: signed in as guest ${value.profile.id}');
    }

    return created;
  }

  void _adopt(AuthSession session) {
    _session = session;
    if (!_sessionController.isClosed) _sessionController.add(session.profile);
  }

  /// Re-pushes this device's name and avatar when the server's have drifted.
  ///
  /// The device is the authority on display data — the player chose it on the
  /// profile screen — and the user row is a mirror of it. That mirror can be
  /// wrong: the account is created under [_placeholderName] at launch, before
  /// the profile screen has been shown, and the `PATCH` that corrects it is
  /// deliberately fire-and-forget so that a rename never appears to fail on a
  /// slow network. When that push is lost, nothing used to notice, and the
  /// player was called "Player" in every lobby from then on. This notices.
  ///
  /// [supplied] is the profile a caller asked to sign in as, falling back to
  /// the one saved on this device. A profile with no real name is never
  /// pushed: a device that has not finished the first run has nothing to
  /// correct the server with, and overwriting a good row with a placeholder
  /// would be the very bug this repairs.
  Future<void> _reconcile(AuthSession session, PlayerProfile? supplied) async {
    final PlayerProfile? desired = _named(supplied) ?? _named(_savedProfile());
    if (desired == null) return;

    final PlayerProfile server = session.profile;
    if (desired.name == server.name &&
        desired.avatarId == server.avatarId &&
        desired.avatarColorIndex == server.avatarColorIndex) {
      return;
    }

    AppLogger.i('AuthService: the server profile is stale; re-pushing ours');
    await updateProfile(desired.copyWith(id: server.id));
  }

  /// The profile saved on this device, or null if there is none.
  PlayerProfile? _savedProfile() {
    final Map<String, dynamic>? stored =
        _store.readObject(StorageKeys.profile);
    return stored == null ? null : PlayerProfile.fromJson(stored);
  }

  /// [profile] if the player has actually named themselves, else null.
  PlayerProfile? _named(PlayerProfile? profile) {
    if (profile == null) return null;
    return profile.name.trim().length >= AppConstants.minNameLength
        ? profile
        : null;
  }

  /// A placeholder identity for signing in before the player picks a name.
  ///
  /// The first-run profile screen renames them immediately; this exists so the
  /// session — and therefore the id everything else keys off — is available
  /// from the very first frame. Anything that survives on the server under
  /// this name is a rename that never landed, which is what [_reconcile] and
  /// the server's handshake sync between them put right.
  PlayerProfile _fallbackProfile() =>
      _named(_savedProfile()) ?? const PlayerProfile(name: _placeholderName);

  /// The name a brand-new account is created under.
  static const String _placeholderName = 'Player';
}
