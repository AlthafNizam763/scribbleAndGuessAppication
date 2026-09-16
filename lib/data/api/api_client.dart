import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// The REST transport, and the only place in the app that knows about HTTP.
///
/// Everything above it works in [Result]s and [Failure]s, exactly as the
/// socket layer does, so a caller never has to care which transport answered.
/// Nothing throws out of here.
///
/// ## Why `http` rather than Dio
///
/// The brief suggests Dio. `http` is used instead because it is already in
/// this project's lockfile as a transitive dependency, so promoting it to a
/// direct dependency adds a name to `pubspec.yaml` and nothing to the build.
/// Dio would pull a new package tree in for features this client does not use:
/// there are five endpoints, no interceptor chain, no multipart, no download
/// progress. The pieces Dio is usually reached for — a base URL, a bearer
/// token, timeouts and typed errors — are the forty lines below.
///
/// ## What the backend guarantees
///
/// Every response is `{success: true, data}` or `{success: false, error}`
/// (brief section 49), so unwrapping is uniform and an error always carries a
/// code this app can map onto its own [AppErrorCode].
class ApiClient {
  /// Creates a client for [baseUrl].
  ///
  /// [tokenSource] is read on every request rather than captured once: the
  /// token is established asynchronously at startup and replaced on sign-out,
  /// and a captured copy would go stale.
  ApiClient({
    required String baseUrl,
    required Future<String?> Function() tokenSource,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 12),
  })  : _baseUrl = _normalizeBase(baseUrl),
        _tokenSource = tokenSource,
        _client = httpClient ?? http.Client(),
        _timeout = timeout;

  final String _baseUrl;
  final Future<String?> Function() _tokenSource;
  final http.Client _client;
  final Duration _timeout;

  bool _disposed = false;

  /// The origin this client talks to, without a trailing slash.
  String get baseUrl => _baseUrl;

  /// `GET path`, unwrapping the envelope.
  Future<Result<Map<String, dynamic>>> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) =>
      _send('GET', path, query: query, authenticated: authenticated);

  /// `POST path` with an optional JSON body.
  Future<Result<Map<String, dynamic>>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) =>
      _send('POST', path, body: body, authenticated: authenticated);

  /// `PATCH path` with a JSON body.
  Future<Result<Map<String, dynamic>>> patch(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) =>
      _send('PATCH', path, body: body, authenticated: authenticated);

  /// `DELETE path`.
  ///
  /// Carries no body. The two endpoints that use it — removing a friend and
  /// lifting a block — name their target in the path, and the actor is the
  /// bearer token, so there is nothing left to send.
  Future<Result<Map<String, dynamic>>> delete(
    String path, {
    bool authenticated = true,
  }) =>
      _send('DELETE', path, authenticated: authenticated);

  /// Releases the underlying connection pool.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Result<Map<String, dynamic>>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    if (_disposed) {
      return const Err<Map<String, dynamic>>(
        Failure(AppErrorCode.invalidAction, 'The API client was disposed.'),
      );
    }

    final Uri? uri = _resolve(path, query);
    if (uri == null) {
      return const Err<Map<String, dynamic>>(
        Failure(AppErrorCode.validation, 'That API address is not valid.'),
      );
    }

    final Map<String, String> headers = <String, String>{
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
    };

    if (authenticated) {
      final String? token = await _tokenSource();
      if (token != null && token.isNotEmpty) {
        headers['authorization'] = 'Bearer $token';
      }
    }

    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);

      final http.StreamedResponse streamed =
          await _client.send(request).timeout(_timeout);
      final http.Response response = await http.Response.fromStream(streamed);

      return _unwrap(response, method, path);
    } on TimeoutException {
      AppLogger.w('ApiClient: $method $path timed out');
      return const Err<Map<String, dynamic>>(Failure.timeout());
    } on Object catch (error, stackTrace) {
      // A socket exception, a DNS failure, a closed client: all of them are
      // "the network did not work", which is what the player needs to know.
      AppLogger.w('ApiClient: $method $path failed', error, stackTrace);
      return const Err<Map<String, dynamic>>(Failure.network());
    }
  }

  /// Decodes the response and maps a failure onto the app's vocabulary.
  Result<Map<String, dynamic>> _unwrap(
    http.Response response,
    String method,
    String path,
  ) {
    Map<String, dynamic> decoded;
    try {
      final Object? parsed = jsonDecode(utf8.decode(response.bodyBytes));
      decoded = parsed is Map ? asMap(parsed) : <String, dynamic>{};
    } on Object {
      // A body that is not JSON means something other than the API answered —
      // a proxy error page, most often.
      AppLogger.w('ApiClient: $method $path returned a non-JSON body');
      return const Err<Map<String, dynamic>>(Failure.server());
    }

    if (asBool(decoded['success'])) {
      final Object? data = decoded['data'];
      return Ok<Map<String, dynamic>>(data is Map ? asMap(data) : decoded);
    }

    final Object? rawError = decoded['error'];
    final Map<String, dynamic> error =
        rawError is Map ? asMap(rawError) : <String, dynamic>{};

    final Failure failure = Failure(
      _codeFor(asString(error['code']), response.statusCode),
      asString(error['message']).isNotEmpty
          ? asString(error['message'])
          : _messageFor(response.statusCode),
    );

    AppLogger.w(
      'ApiClient: $method $path -> ${response.statusCode} '
      '(${failure.code.name})',
    );
    return Err<Map<String, dynamic>>(failure);
  }

  /// Maps a server error code onto this app's [AppErrorCode].
  ///
  /// The server speaks the vocabulary from brief section 70; the app speaks
  /// the one in `failure.dart`. Translating here means every screen keeps
  /// showing the message it already had for a given situation.
  AppErrorCode _codeFor(String serverCode, int status) {
    return switch (serverCode) {
      'AUTH_ERROR' => AppErrorCode.invalidAction,
      'VALIDATION_ERROR' => AppErrorCode.validation,
      'ROOM_NOT_FOUND' => AppErrorCode.roomNotFound,
      'ROOM_FULL' => AppErrorCode.roomFull,
      'NOT_ROOM_MEMBER' => AppErrorCode.invalidAction,
      'NOT_ROOM_OWNER' => AppErrorCode.notHost,
      'GAME_ALREADY_STARTED' => AppErrorCode.gameInProgress,
      'GAME_NOT_STARTED' => AppErrorCode.invalidAction,
      'NOT_DRAWER' => AppErrorCode.notDrawer,
      'INVALID_ROOM_CODE' => AppErrorCode.invalidCode,
      'NAME_TAKEN' => AppErrorCode.nameTaken,
      'PLAYER_BANNED' => AppErrorCode.banned,
      'PLAYER_MUTED' || 'ALREADY_GUESSED' || 'ROUND_ENDED' || 'INVALID_WORD' =>
        AppErrorCode.invalidAction,
      'RATE_LIMITED' => AppErrorCode.invalidAction,
      'INTERNAL_ERROR' => AppErrorCode.serverError,
      _ => _codeForStatus(status),
    };
  }

  AppErrorCode _codeForStatus(int status) => switch (status) {
        400 || 422 => AppErrorCode.validation,
        401 || 403 => AppErrorCode.invalidAction,
        404 => AppErrorCode.roomNotFound,
        408 => AppErrorCode.timeout,
        _ => AppErrorCode.serverError,
      };

  String _messageFor(int status) => switch (status) {
        401 || 403 => 'You are not allowed to do that.',
        404 => 'That was not found.',
        429 => 'Slow down a moment.',
        _ => 'The server could not handle that.',
      };

  Uri? _resolve(String path, Map<String, String>? query) {
    final Uri? uri = Uri.tryParse('$_baseUrl$path');
    if (uri == null) return null;
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: <String, String>{
      ...uri.queryParameters,
      ...query,
    });
  }

  /// Trims a trailing slash so paths can always start with one.
  static String _normalizeBase(String value) {
    final String trimmed = value.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
