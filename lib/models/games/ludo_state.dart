import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// The board, as coordinates on a fifteen-by-fifteen grid.
///
/// ## Why the geometry lives on the client and the rules do not
///
/// The server knows a token is at *relative position 23*. It does not know,
/// and has no reason to know, that this is the eighth square of the right-hand
/// arm. Where the squares are is a drawing problem; which squares a token may
/// reach is a rules problem, and the two are kept apart exactly as they are in
/// every other game here.
///
/// So nothing in this class decides anything. It turns a number the server
/// sent into a place to draw a counter.
///
/// ## The coordinate system
///
/// The classic cross: four six-by-six yards in the corners, three-wide arms
/// between them, and the centre at (7, 7). Coordinates are grid cells, so a
/// renderer multiplies by the cell size and never thinks about pixels.
abstract final class LudoGeometry {
  /// Cells on the shared ring. Thirteen per arm.
  static const int ringLength = 52;

  /// The position value the server uses for a token still in its yard.
  static const int inYard = -1;

  /// The position value for a token that has finished.
  static const int home = 56;

  /// The first home-path position. 52 to 55, then [home].
  static const int homePathStart = 52;

  /// The grid is fifteen cells square.
  static const double gridSize = 15;

  static const Offset centre = Offset(7, 7);

  /// The ring, clockwise, starting outside the top-left yard.
  ///
  /// Fifty-two cells built as twelve runs: six along an arm's outer row, six
  /// up its outer column, then the single cell that turns the corner at the
  /// top of the middle lane. Written out rather than generated because the
  /// turns are irregular and a loop that produced them would be longer than
  /// the list and harder to check against a real board.
  static const List<Offset> ring = <Offset>[
    // Left arm, outward along row 6.
    Offset(0, 6), Offset(1, 6), Offset(2, 6), Offset(3, 6), Offset(4, 6), Offset(5, 6),
    // Up the left side of the top arm.
    Offset(6, 5), Offset(6, 4), Offset(6, 3), Offset(6, 2), Offset(6, 1), Offset(6, 0),
    // Over the top of the middle lane.
    Offset(7, 0),
    // Down the right side of the top arm.
    Offset(8, 0), Offset(8, 1), Offset(8, 2), Offset(8, 3), Offset(8, 4), Offset(8, 5),
    // Right arm, outward along row 6.
    Offset(9, 6), Offset(10, 6), Offset(11, 6), Offset(12, 6), Offset(13, 6), Offset(14, 6),
    // Round the right-hand end.
    Offset(14, 7),
    // Back along row 8.
    Offset(14, 8), Offset(13, 8), Offset(12, 8), Offset(11, 8), Offset(10, 8), Offset(9, 8),
    // Down the right side of the bottom arm.
    Offset(8, 9), Offset(8, 10), Offset(8, 11), Offset(8, 12), Offset(8, 13), Offset(8, 14),
    // Under the bottom of the middle lane.
    Offset(7, 14),
    // Up the left side of the bottom arm.
    Offset(6, 14), Offset(6, 13), Offset(6, 12), Offset(6, 11), Offset(6, 10), Offset(6, 9),
    // Left arm, back along row 8.
    Offset(5, 8), Offset(4, 8), Offset(3, 8), Offset(2, 8), Offset(1, 8), Offset(0, 8),
    // Round the left-hand end, back to the start.
    Offset(0, 7),
  ];

  /// Where each seat joins the ring.
  ///
  /// Thirteen apart, which is what the server assumes when it converts a
  /// player's own position into a shared board cell: `(seat * 13 + position)`.
  /// Changing this without changing that would put two players on the same
  /// square and capture nobody.
  static int startCell(int seat) => (seat * 13) % ringLength;

  /// The shared board cell a token occupies.
  ///
  /// The one piece of arithmetic that has to agree with the server exactly,
  /// because it is what decides whether two counters are on the same square.
  static int boardCell(int seat, int position) =>
      (startCell(seat) + position) % ringLength;

  /// The squares a counter cannot be taken on.
  ///
  /// The server stores these as positions relative to whoever is moving, which
  /// looks seat-dependent and is not: the offsets are symmetric about thirteen,
  /// so every seat resolves to the same eight absolute cells. Those eight are
  /// the four starts plus the four eighth-squares — the classic star layout,
  /// arrived at from the other direction.
  static const Set<int> safeCells = <int>{0, 8, 13, 21, 26, 34, 39, 47};

  static bool isSafeCell(int cell) => safeCells.contains(cell);

  /// The four parking slots inside a seat's yard.
  static List<Offset> yardSlots(int seat) {
    // Yards run clockwise from the top left, matching the ring's start order.
    final Offset corner = switch (seat % 4) {
      0 => const Offset(0, 0),
      1 => const Offset(9, 0),
      2 => const Offset(9, 9),
      _ => const Offset(0, 9),
    };

    return <Offset>[
      corner + const Offset(1.5, 1.5),
      corner + const Offset(3.5, 1.5),
      corner + const Offset(1.5, 3.5),
      corner + const Offset(3.5, 3.5),
    ];
  }

  /// The five cells of a seat's run to the middle.
  ///
  /// Five are drawn; four are ever occupied. Positions 52 to 55 sit on the
  /// first four, and 56 is the centre — so the last drawn cell is the gap a
  /// counter crosses on its final move, which is what it looks like on a real
  /// board.
  static List<Offset> homeLane(int seat) => switch (seat % 4) {
        0 => <Offset>[
            for (int step = 1; step <= 5; step++) Offset(step.toDouble(), 7),
          ],
        1 => <Offset>[
            for (int step = 1; step <= 5; step++) Offset(7, step.toDouble()),
          ],
        2 => <Offset>[
            for (int step = 1; step <= 5; step++) Offset(14 - step.toDouble(), 7),
          ],
        _ => <Offset>[
            for (int step = 1; step <= 5; step++) Offset(7, 14 - step.toDouble()),
          ],
      };

  /// Where to draw a counter, given the position the server reported.
  ///
  /// [slot] is which of the seat's four counters this is, and is used only to
  /// park it in the yard — once a counter is on the board its position alone
  /// decides where it stands.
  static Offset cellFor({
    required int seat,
    required int position,
    required int slot,
  }) {
    if (position == inYard) return yardSlots(seat)[slot % 4];
    if (position >= home) return centre;
    if (position >= homePathStart) {
      return homeLane(seat)[position - homePathStart];
    }
    return ring[boardCell(seat, position)];
  }
}

/// One seat's four counters.
@immutable
class LudoSeatState {
  const LudoSeatState({
    required this.playerId,
    required this.seat,
    required this.positions,
  });

  final String playerId;

  /// Index in the turn order. Decides this player's colour, start square and
  /// which corner their yard is in.
  final int seat;

  /// Four positions, exactly as the server sent them.
  final List<int> positions;

  int get inYard =>
      positions.where((int p) => p == LudoGeometry.inYard).length;

  int get finished => positions.where((int p) => p >= LudoGeometry.home).length;

  int get onBoard => 4 - inYard - finished;
}

/// A roll, for the dice animation and the running commentary.
@immutable
class LudoRoll {
  const LudoRoll({required this.playerId, required this.dice, required this.atMs});

  static LudoRoll? fromJson(Map<String, dynamic> json) {
    final String playerId = asString(json['playerId']);
    if (playerId.isEmpty) return null;
    return LudoRoll(
      playerId: playerId,
      dice: asInt(json['dice']),
      atMs: asInt(json['atMs']),
    );
  }

  final String playerId;
  final int dice;
  final int atMs;
}

/// The last counter that moved, and whatever it landed on.
@immutable
class LudoMove {
  const LudoMove({
    required this.playerId,
    required this.tokenIndex,
    required this.from,
    required this.to,
    required this.captured,
    required this.atMs,
  });

  static LudoMove? fromJson(Map<String, dynamic> json) {
    final String playerId = asString(json['playerId']);
    if (playerId.isEmpty) return null;
    return LudoMove(
      playerId: playerId,
      tokenIndex: asInt(json['tokenIndex']),
      from: asInt(json['from'], LudoGeometry.inYard),
      to: asInt(json['to']),
      captured: asStringList(json['captured']),
      atMs: asInt(json['atMs']),
    );
  }

  final String playerId;
  final int tokenIndex;
  final int from;
  final int to;

  /// Whoever was sent back to their yard. One entry per counter taken.
  final List<String> captured;

  final int atMs;
}

/// Everything a Ludo screen needs, parsed from one projection.
///
/// ## There is nothing hidden here
///
/// Ludo has no secrets: every counter is on the board and the dice are shown
/// the moment they are rolled. So the private projection and the public one
/// are the same object, and this parses either. That does **not** mean the
/// client may decide anything — the dice are rolled on the server, the legality
/// of a move is checked there, and a move this class believes is legal is
/// still refused if the server disagrees.
@immutable
class LudoState {
  const LudoState({
    required this.status,
    required this.currentPlayerId,
    required this.dice,
    required this.order,
    required this.positions,
    required this.lastRoll,
    required this.lastMove,
    required this.result,
  });

  static const LudoState empty = LudoState(
    status: '',
    currentPlayerId: '',
    dice: null,
    order: <String>[],
    positions: <String, List<int>>{},
    lastRoll: null,
    lastMove: null,
    result: null,
  );

  factory LudoState.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> raw = asMap(json['positions']);
    final Map<String, dynamic> result = asMap(json['result']);

    return LudoState(
      status: asString(json['status']),
      currentPlayerId: asString(json['currentPlayerId']),
      // Null means "nothing on the table": the turn has not been rolled yet,
      // or the roll has already been spent on a move.
      dice: json['dice'] is num ? asInt(json['dice']) : null,
      order: asStringList(json['order']),
      positions: <String, List<int>>{
        for (final MapEntry<String, dynamic> entry in raw.entries)
          entry.key: <int>[
            for (final Object? value in asList(entry.value)) asInt(value, -1),
          ],
      },
      lastRoll: LudoRoll.fromJson(asMap(json['lastRoll'])),
      lastMove: LudoMove.fromJson(asMap(json['lastMove'])),
      result: result.isEmpty ? null : result,
    );
  }

  final String status;
  final String currentPlayerId;

  /// The roll waiting to be spent, or null.
  final int? dice;

  /// Turn order. A player's index in this is their seat, and their seat is
  /// their colour, their start square and their corner.
  final List<String> order;

  final Map<String, List<int>> positions;
  final LudoRoll? lastRoll;
  final LudoMove? lastMove;
  final Map<String, dynamic>? result;

  bool get isPlaying => status == 'playing';
  bool get isOver => status == 'completed';

  bool isTurnOf(String playerId) =>
      isPlaying && currentPlayerId.isNotEmpty && currentPlayerId == playerId;

  int seatOf(String playerId) => order.indexOf(playerId);

  LudoSeatState? seatState(String playerId) {
    final int seat = seatOf(playerId);
    if (seat < 0) return null;
    return LudoSeatState(
      playerId: playerId,
      seat: seat,
      positions: positions[playerId] ?? const <int>[-1, -1, -1, -1],
    );
  }

  /// Whether [playerId] may roll right now.
  ///
  /// Their turn, and nothing already on the table. The server refuses a second
  /// roll before a move, so offering one would be a button that fails.
  bool canRoll(String playerId) => isTurnOf(playerId) && dice == null;

  /// Which of [playerId]'s counters the current roll could legally move.
  ///
  /// Mirrors the server's own `canMove`: a counter leaves the yard only on a
  /// six, and cannot overshoot home. It is a **courtesy**, not a rule — it is
  /// what lets the board light up the counters worth tapping instead of
  /// offering four and refusing three. The server checks it again regardless,
  /// and its answer is the one that counts.
  List<int> movableTokens(String playerId) {
    final int? roll = dice;
    if (roll == null || !isTurnOf(playerId)) return const <int>[];

    final List<int> mine = positions[playerId] ?? const <int>[];
    final List<int> movable = <int>[];

    for (int index = 0; index < mine.length; index++) {
      final int position = mine[index];
      if (position >= LudoGeometry.home) continue;
      if (position == LudoGeometry.inYard) {
        if (roll == 6) movable.add(index);
        continue;
      }
      if (position + roll <= LudoGeometry.home) movable.add(index);
    }
    return movable;
  }

  /// Every counter on the board, with enough to draw it.
  ///
  /// Flattened here rather than in the painter so the stacking rule — two
  /// counters on one square are drawn side by side — has a single place to
  /// live.
  List<({String playerId, int seat, int slot, int position})> get counters {
    final List<({String playerId, int seat, int slot, int position})> out =
        <({String playerId, int seat, int slot, int position})>[];

    for (int seat = 0; seat < order.length; seat++) {
      final String playerId = order[seat];
      final List<int> mine = positions[playerId] ?? const <int>[];
      for (int slot = 0; slot < mine.length; slot++) {
        out.add((playerId: playerId, seat: seat, slot: slot, position: mine[slot]));
      }
    }
    return out;
  }
}
