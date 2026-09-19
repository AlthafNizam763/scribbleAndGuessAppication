import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/platform_room.dart';

/// REST client for the common multi-game lobby APIs.
class GamesApi {
  const GamesApi(this._client);
  final ApiClient _client;

  Future<Result<List<GameDefinition>>> catalogue() async {
    final Result<Map<String, dynamic>> response = await _client.get('/api/games');
    return response.map((Map<String, dynamic> data) {
      final List<GameDefinition> parsed = <GameDefinition>[];
      for (final Object? item in asList(data['items'])) {
        if (item is! Map) continue;
        final GameDefinition? definition = _definition(asMap(item));
        if (definition != null) parsed.add(definition);
      }
      // Never render an accidental sixth game from a malformed deployment.
      return parsed.length == GameCatalog.all.length ? parsed : GameCatalog.all;
    });
  }

  Future<Result<PlatformRoom>> quickMatch(GameDefinition game) => _roomPost(
        '/api/games/${game.gameId.wire}/quick-match', <String, dynamic>{},
      );

  Future<Result<PlatformRoom>> createPrivateRoom(GameDefinition game) =>
      _roomPost('/api/games/${game.gameId.wire}/rooms', <String, dynamic>{'isPrivate': true});

  Future<Result<PlatformRoom>> ready(GameDefinition game, String roomId) =>
      _roomPost('/api/games/${game.gameId.wire}/rooms/$roomId/ready', <String, dynamic>{'ready': true});

  /// Takes a seat in an existing platform room.
  ///
  /// Named by wire id rather than by [GameDefinition] because Quick Match can
  /// legitimately offer a room for a game this build does not have a
  /// definition for — the server sent the id and the route, and that is all a
  /// join needs. Every rule about whether the seat is available is the
  /// server's, and a refusal arrives as a [Failure] with a message for the
  /// player: the room filled, the game started, you are seated elsewhere.
  Future<Result<PlatformRoom>> joinRoom({
    required String gameWireId,
    required String roomId,
  }) => _roomPost('/api/games/$gameWireId/rooms/$roomId/join', <String, dynamic>{});

  /// Seats up to [count] Stupids in a waiting room. Owner only.
  ///
  /// Returns the room as it now stands, so the lobby redraws from what the
  /// server did rather than from what was asked for — an over-ask into a
  /// nearly full room fills the seats that exist and reports those.
  Future<Result<PlatformRoom>> addStupids(
    GameDefinition game,
    String roomId, {
    int count = 1,
    BotDifficulty difficulty = BotDifficulty.medium,
  }) => _roomPost(
    '/api/games/${game.gameId.wire}/rooms/$roomId/stupids',
    <String, dynamic>{'count': count, 'difficulty': difficulty.wire},
  );

  /// Removes every Stupid from a waiting room. Owner only.
  Future<Result<PlatformRoom>> clearStupids(
    GameDefinition game,
    String roomId,
  ) async {
    final Result<Map<String, dynamic>> response = await _client.delete(
      '/api/games/${game.gameId.wire}/rooms/$roomId/stupids',
    );
    return response.map(
      (Map<String, dynamic> data) => PlatformRoom.fromJson(asMap(data['room'])),
    );
  }

  Future<Result<PlatformRoom>> _roomPost(String path, Map<String, dynamic> body) async {
    final Result<Map<String, dynamic>> response = await _client.post(path, body: body);
    return response.map((Map<String, dynamic> data) => PlatformRoom.fromJson(asMap(data['room'])));
  }

  GameDefinition? _definition(Map<String, dynamic> json) {
    final GameId? id = GameId.fromWire(asString(json['gameId']));
    if (id == null) return null;
    final GameDefinition fallback = GameCatalog.byId(id);
    return GameDefinition(
      gameId: id,
      displayName: asString(json['displayName']).isEmpty ? fallback.displayName : asString(json['displayName']),
      description: asString(json['description']).isEmpty ? fallback.description : asString(json['description']),
      icon: asString(json['icon']).isEmpty ? fallback.icon : asString(json['icon']),
      banner: asString(json['banner']).isEmpty ? fallback.banner : asString(json['banner']),
      minPlayers: asInt(json['minPlayers'], fallback.minPlayers), maxPlayers: asInt(json['maxPlayers'], fallback.maxPlayers),
      supportsBots: asBool(json['supportsBots'], fallback.supportsBots), supportsVoice: asBool(json['supportsVoice'], fallback.supportsVoice),
      supportsTextChat: asBool(json['supportsTextChat'], fallback.supportsTextChat), route: asString(json['route']).isEmpty ? fallback.route : asString(json['route']),
      status: asString(json['status']) == 'coming_soon' ? GameStatus.comingSoon : GameStatus.live,
      version: asInt(json['version'], fallback.version), rules: fallback.rules, color: fallback.color,
    );
  }
}
