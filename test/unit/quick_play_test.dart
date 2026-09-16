import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/services/quick_play_service.dart';

import '../support/fake_gateway.dart';

/// Quick Play, against a fake socket.
///
/// The matchmaking itself is the server's and is tested there. What matters on
/// this side is the behaviour a player actually feels: that a second tap does
/// nothing, that a refusal keeps the server's own wording, and that the stages
/// arrive in an order a button can render.
void main() {
  const PlayerProfile profile = PlayerProfile(
    id: 'me',
    name: 'Ada',
    avatarId: 1,
    avatarColorIndex: 2,
  );

  /// An ack shaped like the one `c:room:quickPlay` returns.
  Result<Map<String, dynamic>> ack({
    bool created = false,
    bool alreadySeated = false,
  }) =>
      Ok<Map<String, dynamic>>(<String, dynamic>{
        'room': <String, dynamic>{
          'id': 'room-1',
          'code': 'A7K9P',
          'hostId': 'someone',
          'players': <Map<String, dynamic>>[],
        },
        'created': created,
        'alreadySeated': alreadySeated,
      });

  /// A service whose connect step succeeds.
  ({QuickPlayService service, FakeGateway gateway}) build({
    Result<void> connectResult = const Ok<void>(null),
  }) {
    final FakeGateway gateway = FakeGateway();
    final QuickPlayService service = QuickPlayService(
      gateway: gateway,
      connect: (PlayerProfile _) async => connectResult,
    );
    return (service: service, gateway: gateway);
  }

  test('seats the player and returns the room', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(SocketEvents.clientRoomQuickPlay, ack());

    final Result<Room> result = await harness.service.play(profile);

    expect(result.isOk, isTrue);
    expect(result.valueOrNull?.code, 'A7K9P');
    expect(harness.service.stage, QuickPlayStage.done);

    harness.service.dispose();
  });

  test('sends the profile, so the seat carries the right name', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(SocketEvents.clientRoomQuickPlay, ack());

    await harness.service.play(profile);

    final ({String event, Map<String, dynamic> data}) sent =
        harness.gateway.sent.single;
    expect(sent.event, SocketEvents.clientRoomQuickPlay);
    expect(sent.data['profile'], isA<Map<String, dynamic>>());

    harness.service.dispose();
  });

  test('takes no parameters beyond the profile', () async {
    // The point of the button is that there is nothing to decide. A payload
    // carrying settings would be a second, divergent way to create a room.
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(SocketEvents.clientRoomQuickPlay, ack());

    await harness.service.play(profile);

    expect(harness.gateway.sent.single.data.keys, <String>['profile']);

    harness.service.dispose();
  });

  test('refuses a second tap while the first is still running', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(SocketEvents.clientRoomQuickPlay, ack());

    final Future<Result<Room>> first = harness.service.play(profile);
    final Result<Room> second = await harness.service.play(profile);

    expect(second.isErr, isTrue);
    expect((await first).isOk, isTrue);

    // One request reached the socket, so only one room can have been opened.
    expect(harness.gateway.sent, hasLength(1));

    harness.service.dispose();
  });

  test('allows another attempt once the first has finished', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(SocketEvents.clientRoomQuickPlay, ack());

    await harness.service.play(profile);
    await harness.service.play(profile);

    expect(harness.gateway.sent, hasLength(2));

    harness.service.dispose();
  });

  test('keeps the server wording when the server refuses', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(
      SocketEvents.clientRoomQuickPlay,
      const Err<Map<String, dynamic>>(
        Failure(AppErrorCode.roomFull, 'That room is full.'),
      ),
    );

    final Result<Room> result = await harness.service.play(profile);

    expect(result.failureOrNull?.message, 'That room is full.');
    expect(harness.service.stage, QuickPlayStage.failed);
    expect(harness.service.lastFailure, isNotNull);

    harness.service.dispose();
  });

  test('fails without asking for a room when the connection fails', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build(
      connectResult: const Err<void>(Failure.network()),
    );

    final Result<Room> result = await harness.service.play(profile);

    expect(result.isErr, isTrue);
    expect(result.failureOrNull?.code, AppErrorCode.network);
    // Nothing was sent: a quick-play request over a dead socket would just
    // time out and report the wrong cause.
    expect(harness.gateway.sent, isEmpty);

    harness.service.dispose();
  });

  test('reports a server bug as a server error, not as a refusal', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(
      SocketEvents.clientRoomQuickPlay,
      const Ok<Map<String, dynamic>>(<String, dynamic>{'created': true}),
    );

    final Result<Room> result = await harness.service.play(profile);

    // An ack that said ok but carried no room is not something the player did.
    expect(result.failureOrNull?.code, AppErrorCode.serverError);

    harness.service.dispose();
  });

  test('walks through the stages a button renders', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(SocketEvents.clientRoomQuickPlay, ack(created: true));

    final List<QuickPlayStage> seen = <QuickPlayStage>[];
    final sub = harness.service.stages.listen(seen.add);

    await harness.service.play(profile);
    await Future<void>.delayed(Duration.zero);

    expect(
      seen,
      <QuickPlayStage>[
        QuickPlayStage.connecting,
        QuickPlayStage.finding,
        QuickPlayStage.creating,
        QuickPlayStage.done,
      ],
    );

    await sub.cancel();
    harness.service.dispose();
  });

  test('reports joining rather than creating when a room was found', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.gateway.replyTo(SocketEvents.clientRoomQuickPlay, ack());

    final List<QuickPlayStage> seen = <QuickPlayStage>[];
    final sub = harness.service.stages.listen(seen.add);

    await harness.service.play(profile);
    await Future<void>.delayed(Duration.zero);

    expect(seen, contains(QuickPlayStage.joining));
    expect(seen, isNot(contains(QuickPlayStage.creating)));

    await sub.cancel();
    harness.service.dispose();
  });

  test('returns to idle when the failure has been shown', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build(
      connectResult: const Err<void>(Failure.network()),
    );

    await harness.service.play(profile);
    expect(harness.service.stage, QuickPlayStage.failed);

    harness.service.reset();

    expect(harness.service.stage, QuickPlayStage.idle);
    expect(harness.service.lastFailure, isNull);

    harness.service.dispose();
  });

  test('refuses to run once disposed', () async {
    final ({QuickPlayService service, FakeGateway gateway}) harness = build();
    harness.service.dispose();

    final Result<Room> result = await harness.service.play(profile);

    expect(result.isErr, isTrue);
    expect(harness.gateway.sent, isEmpty);
  });
}
