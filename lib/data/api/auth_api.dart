import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/user_preferences.dart';

/// How a session was established.
///
/// The server is the authority: it is on every auth response and on
/// `GET /api/auth/session`, so a resumed session reports what the account
/// actually is rather than what this device last assumed.
enum AuthProvider {
  guest,
  google,
  apple,
  email;

  static AuthProvider fromWire(String value) => switch (value) {
        'email' => AuthProvider.email,
        'google' => AuthProvider.google,
        'apple' => AuthProvider.apple,
        // An unknown provider from a newer server is treated as a guest: the
        // conservative reading, since every "you are playing as a guest"
        // affordance it turns on is an offer to secure the account.
        _ => AuthProvider.guest,
      };
}

/// A signed-in session: the token to present, and who it belongs to.
class AuthSession {
  const AuthSession({
    required this.token,
    required this.profile,
    this.provider = AuthProvider.guest,
  });

  /// Builds a session from the backend's `{token, user}` payload.
  factory AuthSession.fromJson(Map<String, dynamic> json, {String? token}) {
    final Map<String, dynamic> user = asMap(json['user']);
    return AuthSession(
      token: token ?? asString(json['token']),
      provider: AuthProvider.fromWire(asString(user['provider'])),
      profile: PlayerProfile(
        id: asString(user['id']),
        name: asString(user['username']),
        avatarId: asInt(user['avatarId']),
        avatarColorIndex: asInt(user['avatarColorIndex']),
      ),
    );
  }

  /// The JWT presented as a bearer token and on the socket handshake.
  final String token;

  /// The identity the server assigned. The id is authoritative.
  final PlayerProfile profile;

  /// How this session was established.
  final AuthProvider provider;

  bool get isValid => token.isNotEmpty && profile.id.isNotEmpty;

  /// Whether this is a guest rather than an account with credentials.
  bool get isGuest => provider == AuthProvider.guest;
}

/// The `/api/auth` and `/api/users` endpoints.
///
/// ## The id comes from here, and nowhere else
///
/// Before this existed the player id was a Firebase uid; now it is the `_id`
/// of a row in the backend's `users` collection. Either way the rule is the
/// same and it is the important one: the id is whatever the server says it is.
/// The client never mints one, because rooms, scores and drawer identity are
/// all keyed by it server-side, and a locally invented value would simply not
/// match anything.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  /// Creates a guest account and returns its session.
  ///
  /// Unauthenticated by definition — this is the call that produces the token
  /// everything else presents.
  Future<Result<AuthSession>> guest(PlayerProfile profile) async {
    final Result<Map<String, dynamic>> response = await _client.post(
      '/api/auth/guest',
      authenticated: false,
      body: <String, dynamic>{
        'username': profile.name,
        'avatarId': profile.avatarId,
        'avatarColorIndex': profile.avatarColorIndex,
      },
    );

    return response.fold<Result<AuthSession>>(
      (Map<String, dynamic> data) {
        final AuthSession session = AuthSession.fromJson(data);
        return session.isValid
            ? Ok<AuthSession>(session)
            : const Err<AuthSession>(Failure.server());
      },
      Err<AuthSession>.new,
    );
  }

  /// Signs in with an email and password.
  ///
  /// Unauthenticated: this is the call that *produces* a token, so sending
  /// the stale one a signed-out device may still be holding would be noise.
  Future<Result<AuthSession>> login({
    required String email,
    required String password,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.post(
      '/api/auth/login',
      authenticated: false,
      body: <String, dynamic>{'email': email, 'password': password},
    );

    return _session(response);
  }

  /// Registers an email account, or upgrades the caller's guest account.
  ///
  /// Authenticated *deliberately*: if this device is already playing as a
  /// guest, sending that token is what tells the server to upgrade the
  /// existing row instead of creating a second one, so the player keeps every
  /// score, friend and achievement they earned before signing up. With no
  /// stored token the header is simply absent and a new account is created.
  ///
  /// [username] is what a brand-new account is named; on the upgrade path the
  /// server ignores it and keeps the name the guest already chose.
  Future<Result<AuthSession>> register({
    required String email,
    required String password,
    String? username,
    int? avatarId,
    int? avatarColorIndex,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.post(
      '/api/auth/register',
      body: <String, dynamic>{
        'email': email,
        'password': password,
        'username': ?username,
        'avatarId': ?avatarId,
        'avatarColorIndex': ?avatarColorIndex,
      },
    );

    return _session(response);
  }

  /// Turns a `{token, user}` payload into a session, or a server failure.
  Result<AuthSession> _session(Result<Map<String, dynamic>> response) =>
      response.fold<Result<AuthSession>>(
        (Map<String, dynamic> data) {
          final AuthSession session = AuthSession.fromJson(data);
          return session.isValid
              ? Ok<AuthSession>(session)
              : const Err<AuthSession>(Failure.server());
        },
        Err<AuthSession>.new,
      );

  /// Confirms a stored token still works, and refreshes the profile with it.
  ///
  /// Called at startup so a returning player skips straight to the menu, and
  /// so a token that has expired or been revoked is discovered here rather
  /// than when they try to create a room.
  Future<Result<AuthSession>> session(String token) async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/auth/session');

    return response.fold<Result<AuthSession>>(
      (Map<String, dynamic> data) {
        final AuthSession session = AuthSession.fromJson(data, token: token);
        return session.isValid
            ? Ok<AuthSession>(session)
            : const Err<AuthSession>(Failure.server());
      },
      Err<AuthSession>.new,
    );
  }

  /// Pushes a renamed or restyled profile to the server.
  ///
  /// Only the name and avatar travel: the endpoint refuses anything else, so
  /// there is nothing to be gained by sending a score (brief section 8).
  Future<Result<PlayerProfile>> updateProfile(PlayerProfile profile) async {
    final Result<Map<String, dynamic>> response = await _client.patch(
      '/api/users/me',
      body: <String, dynamic>{
        'username': profile.name,
        'avatarId': profile.avatarId,
        'avatarColorIndex': profile.avatarColorIndex,
      },
    );

    return response.fold<Result<PlayerProfile>>(
      (Map<String, dynamic> data) {
        final Map<String, dynamic> user = asMap(data['user']);
        return Ok<PlayerProfile>(
          PlayerProfile(
            id: asString(user['id']),
            name: asString(user['username']),
            avatarId: asInt(user['avatarId']),
            avatarColorIndex: asInt(user['avatarColorIndex']),
          ),
        );
      },
      Err<PlayerProfile>.new,
    );
  }

  /// The signed-in player's profile and lifetime statistics.
  Future<Result<Map<String, dynamic>>> me() async {
    final Result<Map<String, dynamic>> response =
        await _client.get('/api/users/me');
    return response.fold<Result<Map<String, dynamic>>>(
      (Map<String, dynamic> data) =>
          Ok<Map<String, dynamic>>(asMap(data['user'])),
      Err<Map<String, dynamic>>.new,
    );
  }

  /// The account's notification and privacy switches.
  Future<Result<UserPreferences>> preferences() async {
    final Result<Map<String, dynamic>> response = await me();
    return response.map(
      (Map<String, dynamic> user) =>
          UserPreferences.fromJson(asMap(user['preferences'])),
    );
  }

  /// Writes the switches named in [patch], leaving the rest alone.
  ///
  /// Sends only what changed rather than the whole set, so two devices
  /// toggling different switches cannot overwrite one another. The server
  /// returns the full profile, and the switches come back from that — never
  /// from what was optimistically sent.
  Future<Result<UserPreferences>> updatePreferences(
    Map<String, bool> patch,
  ) async {
    final Result<Map<String, dynamic>> response = await _client.patch(
      '/api/users/me/preferences',
      body: patch,
    );

    return response.map(
      (Map<String, dynamic> data) =>
          UserPreferences.fromJson(asMap(asMap(data['user'])['preferences'])),
    );
  }

  /// Deletes the signed-in account, permanently.
  ///
  /// There is no parameter naming a user: the session decides whose account
  /// goes, so there is no shape of this call that deletes somebody else's.
  ///
  /// Returns only whether the server agreed. The caller is responsible for
  /// everything after that — dropping the socket, forgetting the token and the
  /// cached profile, and getting off every authenticated screen — because the
  /// account is gone the moment this returns and every one of those is now
  /// holding a credential for something that does not exist.
  Future<Result<void>> deleteAccount() async {
    final Result<Map<String, dynamic>> response =
        await _client.delete('/api/users/me');
    return response.map((_) {});
  }
}
