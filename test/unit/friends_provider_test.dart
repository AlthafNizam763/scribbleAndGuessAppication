import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/friends_provider.dart';

import '../support/fake_gateway.dart';

/// The friends providers, wired the way the app wires them.
///
/// These are the tests that catch the mistakes the model tests cannot. A
/// provider graph that loads the right lists but contains a cycle compiles,
/// analyses clean and only fails when somebody opens the screen; likewise a
/// notifier that forgets to refresh after an action is invisible until a
/// player accepts a request and watches it stay put.
void main() {
  /// A client that answers each path from [routes] and records what was asked.
  ({ApiClient client, List<String> calls}) fakeApi(
    Map<String, Object> routes, {
    void Function(String method, String path)? onCall,
  }) {
    final List<String> calls = <String>[];

    final MockClient http0 = MockClient((http.Request request) async {
      final String path = request.url.path;
      calls.add('${request.method} $path');
      onCall?.call(request.method, path);

      final Object? body = routes[path];
      if (body == null) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'success': false,
            'error': <String, dynamic>{'code': 'NOT_FOUND', 'message': 'nope'},
          }),
          404,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }

      return http.Response(
        jsonEncode(<String, dynamic>{'success': true, 'data': body}),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    return (
      client: ApiClient(
        baseUrl: 'https://example.test',
        tokenSource: () async => 'token',
        httpClient: http0,
      ),
      calls: calls,
    );
  }

  /// An empty page, as every list endpoint answers when there is nothing.
  Map<String, dynamic> emptyPage() => <String, dynamic>{
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': 1,
        'hasMore': false,
      };

  Map<String, Object> routes({
    List<Map<String, dynamic>>? friends,
    List<Map<String, dynamic>>? incoming,
  }) =>
      <String, Object>{
        '/api/friends': <String, dynamic>{
          ...emptyPage(),
          'items': friends ?? <Map<String, dynamic>>[],
          'total': friends?.length ?? 0,
        },
        '/api/friends/requests/incoming': <String, dynamic>{
          ...emptyPage(),
          'items': incoming ?? <Map<String, dynamic>>[],
          'total': incoming?.length ?? 0,
        },
        '/api/friends/requests/outgoing': emptyPage(),
        '/api/blocks': emptyPage(),
      };

  ProviderContainer harness({
    required Map<String, Object> apiRoutes,
    required FakeGateway gateway,
    List<String>? calls,
  }) {
    final ({ApiClient client, List<String> calls}) api = fakeApi(apiRoutes);
    calls?.addAll(api.calls);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(api.client),
        gatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('builds without a dependency cycle and loads every list', () async {
    // The cycle check is the point: `friendsProvider` listens to
    // `friendEventsProvider`, so anything that made the events provider read
    // the notifier back would throw here rather than on a player's screen.
    final FakeGateway gateway = FakeGateway();
    addTearDown(gateway.dispose);

    final ProviderContainer container = harness(
      apiRoutes: routes(
        friends: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'f1',
            'username': 'Ada',
            'totalScore': 300,
            'gamesPlayed': 4,
            'gamesWon': 2,
            'winRate': 50.0,
            'friendsSinceMs': 1000,
          },
        ],
        incoming: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'r1',
            'status': 'pending',
            'user': <String, dynamic>{'id': 'u9', 'username': 'Grace'},
          },
        ],
      ),
      gateway: gateway,
    );

    final FriendsState state = await container.read(friendsProvider.future);

    expect(state.friends.single.card.name, 'Ada');
    expect(state.incoming.single.user.name, 'Grace');
    expect(state.outgoing, isEmpty);
    expect(state.blocked, isEmpty);
  });

  test('exposes the pending count for the home badge', () async {
    final FakeGateway gateway = FakeGateway();
    addTearDown(gateway.dispose);

    final ProviderContainer container = harness(
      apiRoutes: routes(
        incoming: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'r1', 'user': <String, dynamic>{'id': 'a'}},
          <String, dynamic>{'id': 'r2', 'user': <String, dynamic>{'id': 'b'}},
        ],
      ),
      gateway: gateway,
    );

    await container.read(friendsProvider.future);

    expect(container.read(pendingRequestCountProvider), 2);
  });

  test('reports no pending requests while the lists are still loading', () {
    // A badge that guesses is worse than no badge.
    final FakeGateway gateway = FakeGateway();
    addTearDown(gateway.dispose);

    final ProviderContainer container =
        harness(apiRoutes: routes(), gateway: gateway);

    expect(container.read(pendingRequestCountProvider), 0);
  });

  test('survives a blocks read that failed', () async {
    // Only the friends list is load-bearing. A blocks endpoint that answered
    // 404 must leave that tab empty, not take down a screen somebody opened to
    // answer a request.
    final FakeGateway gateway = FakeGateway();
    addTearDown(gateway.dispose);

    final Map<String, Object> partial = routes()..remove('/api/blocks');

    final ProviderContainer container =
        harness(apiRoutes: partial, gateway: gateway);

    final FriendsState state = await container.read(friendsProvider.future);
    expect(state.blocked, isEmpty);
  });

  test('fails when the friends list itself cannot be read', () async {
    final FakeGateway gateway = FakeGateway();
    addTearDown(gateway.dispose);

    final Map<String, Object> partial = routes()..remove('/api/friends');

    final ProviderContainer container =
        harness(apiRoutes: partial, gateway: gateway);

    await expectLater(
      container.read(friendsProvider.future),
      throwsA(anything),
    );
  });

  test('re-reads the lists when a friend event arrives', () async {
    final FakeGateway gateway = FakeGateway();
    addTearDown(gateway.dispose);

    final List<String> calls = <String>[];
    final ({ApiClient client, List<String> calls}) api = fakeApi(routes());
    calls.addAll(api.calls);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(api.client),
        gatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await container.read(friendsProvider.future);
    final int afterFirstLoad = api.calls.length;

    gateway.push(
      SocketEvents.serverFriendRequestReceived,
      <String, dynamic>{'requestId': 'r1'},
    );

    // The push is delivered asynchronously and the refresh it triggers makes
    // four more reads, so a couple of turns of the event loop are needed.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      api.calls.length,
      greaterThan(afterFirstLoad),
      reason: 'a friend push should have marked the lists stale',
    );
  });

  test('ignores socket traffic that is not a friend event', () async {
    final FakeGateway gateway = FakeGateway();
    addTearDown(gateway.dispose);

    final ({ApiClient client, List<String> calls}) api = fakeApi(routes());

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(api.client),
        gatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await container.read(friendsProvider.future);
    final int afterFirstLoad = api.calls.length;

    // A stroke should not cost four REST reads.
    gateway.push(SocketEvents.serverDrawBegin, <String, dynamic>{});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(api.calls.length, afterFirstLoad);
  });
}
