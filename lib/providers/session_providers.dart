import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/constants/game_defaults.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/drawing_board.dart';
import 'package:scribble_guess/models/drawing_event.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_result.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/round_result.dart';
import 'package:scribble_guess/models/stroke.dart';
import 'package:scribble_guess/models/stroke_point.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/repositories/repositories.dart';

// ------------------------------------------------------------ connection ---

/// Live connection status, starting from whatever the gateway already has.
final StreamProvider<ConnectionStatus> connectionStatusProvider =
    StreamProvider<ConnectionStatus>(
  (Ref ref) => ref.watch(connectivityProvider).onStatusChanged,
);

/// Connection status as a plain value, for widgets that cannot await.
final Provider<ConnectionStatus> connectionProvider =
    Provider<ConnectionStatus>(
  (Ref ref) => ref.watch(connectionStatusProvider).valueOrNull ??
      ref.watch(connectivityProvider).status,
);

// ------------------------------------------------------------------ room ---

/// The current room, or `null` before one is joined.
final StreamProvider<Room> roomStreamProvider = StreamProvider<Room>(
  (Ref ref) => ref.watch(roomRepositoryProvider).roomStream,
);

final Provider<Room?> roomProvider = Provider<Room?>(
  (Ref ref) => ref.watch(roomStreamProvider).valueOrNull ??
      ref.watch(roomRepositoryProvider).currentRoom,
);

/// The players in the current room, ordered as the server sent them.
final Provider<List<Player>> playersProvider = Provider<List<Player>>(
  (Ref ref) => ref.watch(roomProvider)?.players ?? const <Player>[],
);

/// Whether the local player hosts the current room.
final Provider<bool> isHostProvider = Provider<bool>((Ref ref) {
  final Room? room = ref.watch(roomProvider);
  return room != null && room.isHost(ref.watch(selfIdProvider));
});

/// The local player's row in the current room.
final Provider<Player?> selfPlayerProvider = Provider<Player?>((Ref ref) {
  final Room? room = ref.watch(roomProvider);
  if (room == null) {
    return null;
  }
  return room.playerById(ref.watch(selfIdProvider));
});

// ------------------------------------------------------------------ game ---

final StreamProvider<GameState> gameStreamProvider = StreamProvider<GameState>(
  (Ref ref) => ref.watch(gameRepositoryProvider).gameStream,
);

final Provider<GameState> gameProvider = Provider<GameState>(
  (Ref ref) => ref.watch(gameStreamProvider).valueOrNull ?? GameState.initial,
);

/// The words offered to the drawer, as they were pushed.
///
/// Note that the word picker is *not* driven from here. It is opened from
/// `gameProvider` — `phase == wordSelection` plus the choices carried on the
/// authoritative game state — because that survives a screen that was not yet
/// built when the push arrived, and a reconnect mid-selection. See
/// `GameScreen._syncWordSheet`. This stream remains the typed seam for the
/// push itself, and replays its last value to a late listener.
final StreamProvider<List<WordItem>> wordChoicesProvider =
    StreamProvider<List<WordItem>>(
  (Ref ref) => ref.watch(gameRepositoryProvider).wordChoicesStream,
);

final StreamProvider<RoundResult> roundResultProvider =
    StreamProvider<RoundResult>(
  (Ref ref) => ref.watch(gameRepositoryProvider).roundResultStream,
);

final StreamProvider<GameResult> gameResultProvider =
    StreamProvider<GameResult>(
  (Ref ref) => ref.watch(gameRepositoryProvider).gameResultStream,
);

/// Whether the local player holds the pen this turn.
final Provider<bool> isDrawerProvider = Provider<bool>(
  (Ref ref) => ref.watch(gameProvider).isDrawer(ref.watch(selfIdProvider)),
);

/// Whether the local player has already guessed the word this turn.
final Provider<bool> hasGuessedProvider = Provider<bool>((Ref ref) {
  final String selfId = ref.watch(selfIdProvider);
  return selfId.isNotEmpty &&
      ref.watch(gameProvider).correctGuesserIds.contains(selfId);
});

/// The player currently drawing, if they are still in the room.
final Provider<Player?> drawerProvider = Provider<Player?>((Ref ref) {
  final String? drawerId = ref.watch(gameProvider).drawerId;
  if (drawerId == null || drawerId.isEmpty) {
    return null;
  }
  return ref.watch(roomProvider)?.playerById(drawerId);
});

// ------------------------------------------------------------------ chat ---

/// The running chat transcript for the current room.
///
/// Capped at [AppConstants.chatHistoryLimit]; older lines fall off the top so
/// a long game cannot grow the list without bound.
class ChatNotifier extends Notifier<List<ChatMessage>> {
  StreamSubscription<ChatMessage>? _subscription;

  @override
  List<ChatMessage> build() {
    final ChatRepository repository = ref.watch(chatRepositoryProvider);
    _subscription = repository.messages.listen(_append);
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    return const <ChatMessage>[];
  }

  void _append(ChatMessage message) {
    final List<ChatMessage> next = <ChatMessage>[...state, message];
    state = next.length > AppConstants.chatHistoryLimit
        ? next.sublist(next.length - AppConstants.chatHistoryLimit)
        : next;
  }

  /// Drops the transcript, for when a new room begins.
  void clear() => state = const <ChatMessage>[];
}

final NotifierProvider<ChatNotifier, List<ChatMessage>> chatProvider =
    NotifierProvider<ChatNotifier, List<ChatMessage>>(ChatNotifier.new);

// --------------------------------------------------------------- drawing ---

/// The shared canvas, rebuilt from the event stream.
///
/// The board is derived state: every change arrives as a [DrawingEvent], and
/// applying them in order is what keeps every device showing the same picture.
class BoardNotifier extends Notifier<DrawingBoard> {
  StreamSubscription<DrawingEvent>? _subscription;

  @override
  DrawingBoard build() {
    final DrawingRepository repository = ref.watch(drawingRepositoryProvider);
    _subscription = repository.events.listen(_apply);
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    return DrawingBoard.empty;
  }

  void _apply(DrawingEvent event) {
    state = switch (event) {
      StrokeBegan(:final Stroke stroke) => state.addStroke(stroke),
      StrokeAppended(:final String strokeId, :final List<StrokePoint> points) =>
        _appendPoints(strokeId, points),
      // The stroke is already on the board; the end marker only tells the
      // sender they may stop batching.
      StrokeEnded() => state,
      StrokeUndone(:final String strokeId) => state.undo(strokeId),
      StrokeRedone(:final Stroke stroke) => state.redo(stroke),
      BoardCleared() => state.clear(),
      BoardSnapshot(:final List<Stroke> strokes) =>
        DrawingBoard(strokes: strokes),
    };
  }

  DrawingBoard _appendPoints(String strokeId, List<StrokePoint> points) {
    final int index = state.strokes.indexWhere((Stroke s) => s.id == strokeId);
    if (index < 0) {
      // Points for a stroke we never saw begin: a late join, or a dropped
      // packet. Nothing sensible to attach them to.
      return state;
    }
    final Stroke existing = state.strokes[index];
    return state.replaceStroke(
      existing.copyWithPoints(<StrokePoint>[...existing.points, ...points]),
    );
  }

  /// Wipes the local board without telling the server, for leaving a room.
  void reset() => state = DrawingBoard.empty;
}

final NotifierProvider<BoardNotifier, DrawingBoard> boardProvider =
    NotifierProvider<BoardNotifier, DrawingBoard>(BoardNotifier.new);

// ----------------------------------------------------------------- clock ---

/// A coarse clock driving every countdown in the app.
///
/// Emits the gateway's clock-corrected server time so that a device with a
/// skewed clock still sees the same seconds remaining as everybody else.
final StreamProvider<int> serverClockProvider = StreamProvider<int>((Ref ref) {
  final RealtimeGateway gateway = ref.watch(gatewayProvider);
  return Stream<int>.periodic(
    const Duration(milliseconds: GameDefaults.timerTickMs),
    (_) => gateway.serverTimeMs,
  );
});

/// Server time as a plain value, falling back to the device clock.
final Provider<int> serverNowProvider = Provider<int>(
  (Ref ref) =>
      ref.watch(serverClockProvider).valueOrNull ??
      ref.watch(gatewayProvider).serverTimeMs,
);

/// Seconds left in the current turn, or `null` outside a timed phase.
final Provider<int?> secondsRemainingProvider = Provider<int?>((Ref ref) {
  final GameState game = ref.watch(gameProvider);
  if (game.turnEndMs <= 0) {
    return null;
  }
  final int leftMs = game.turnEndMs - ref.watch(serverNowProvider);
  return leftMs <= 0 ? 0 : (leftMs + 999) ~/ 1000;
});
