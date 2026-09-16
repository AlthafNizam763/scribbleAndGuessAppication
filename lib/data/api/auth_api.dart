import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/player_profile.dart';

/// A signed-in session: the token to present, and who it belongs to.
class AuthSession {
  const AuthSession({required this.token, required this.profile});

  /// Builds a session from the backend's `{token, user}` payload.
  factory AuthSession.fromJson(Map<String, dynamic> json, {String? token}) {
    final Map<String, dynamic> user = asMap(json['user']);
    return AuthSession(
      token: token ?? asString(json['token']),
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

  bool get isValid => token.isNotEmpty && profile.id.isNotEmpty;
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
}
