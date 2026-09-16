import 'dart:async';

import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/repositories/realtime_gateway.dart';

/// A gateway that records what was emitted and lets a test push events back.
///
/// Standing in for Socket.IO is what makes the interesting behaviour testable:
/// the real server relays a stroke to everyone *except* the socket that sent
/// it, so the drawer's own strokes never come back. This fake reproduces that
/// by simply never echoing, which is exactly the situation the repository has
/// to cope with.
class FakeGateway implements RealtimeGateway {
  final StreamController<({String event, Map<String, dynamic> data})>
      _inbound =
      StreamController<({String event, Map<String, dynamic> data})>.broadcast();

  final List<({String event, Map<String, dynamic> data})> sent =
      <({String event, Map<String, dynamic> data})>[];

  ConnectionStatus _status = ConnectionStatus.connected;

  /// Canned ack replies, keyed by event name.
  ///
  /// Empty by default, which keeps every existing test on the original
  /// behaviour of acking `Ok({})` to anything. A test that cares what came
  /// back — Quick Play, whose whole outcome is carried in the ack — registers
  /// a reply with [replyTo].
  final Map<String, Result<Map<String, dynamic>>> _replies =
      <String, Result<Map<String, dynamic>>>{};

  /// Makes [event] ack with [reply] instead of an empty success.
  void replyTo(String event, Result<Map<String, dynamic>> reply) =>
      _replies[event] = reply;

  /// Pretends the transport went down, so refusals can be exercised.
  void goOffline() => _status = ConnectionStatus.disconnected;

  /// Delivers a server push, as the real gateway would.
  void push(String event, Map<String, dynamic> data) =>
      _inbound.add((event: event, data: data));

  @override
  Stream<({String event, Map<String, dynamic> data})> get inbound =>
      _inbound.stream;

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  void emit(String event, [Map<String, dynamic> data = const <String, dynamic>{}]) {
    sent.add((event: event, data: data));
  }

  @override
  Future<Result<Map<String, dynamic>>> request(
    String event, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) async {
    sent.add((event: event, data: data));
    return _replies[event] ?? const Ok<Map<String, dynamic>>(<String, dynamic>{});
  }

  @override
  Stream<ConnectionStatus> get status => Stream<ConnectionStatus>.value(_status);

  @override
  int get clockOffsetMs => 0;

  @override
  int get serverTimeMs => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<Result<void>> connect(String url, PlayerProfile profile) async =>
      const Ok<void>(null);

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() => unawaited(_inbound.close());
}
