import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/models/games/ludo_state.dart';

/// The board's arithmetic, checked against the server's.
///
/// The ring, the start offsets and the safe squares are the three things that
/// have to agree with `adapters.ts` exactly. If they drift, two counters that
/// the server thinks are on the same square are drawn on different ones — and
/// a capture happens where nothing appears to have been captured.
void main() {
  group('the ring', () {
    test('is fifty-two distinct cells', () {
      expect(LudoGeometry.ring, hasLength(LudoGeometry.ringLength));
      expect(LudoGeometry.ring.toSet(), hasLength(LudoGeometry.ringLength));
    });

    test('never leaves the grid', () {
      for (final Offset cell in LudoGeometry.ring) {
        expect(cell.dx, inInclusiveRange(0, LudoGeometry.gridSize - 1));
        expect(cell.dy, inInclusiveRange(0, LudoGeometry.gridSize - 1));
      }
    });

    test('is a continuous loop, with four corner turns and no gaps', () {
      // Consecutive cells are orthogonal neighbours everywhere except the four
      // inner corners, where the track wraps around the centre block and two
      // squares meet at a point. That is how a real Ludo board is laid out —
      // the left arm's outward row ends at (5, 6) and the top arm's column
      // begins at (6, 5) — so a diagonal step is expected exactly four times
      // and a longer step never.
      int corners = 0;

      for (int i = 0; i < LudoGeometry.ring.length; i++) {
        final Offset a = LudoGeometry.ring[i];
        final Offset b = LudoGeometry.ring[(i + 1) % LudoGeometry.ring.length];
        final double dx = (a.dx - b.dx).abs();
        final double dy = (a.dy - b.dy).abs();

        if (dx + dy == 1) continue;
        expect(dx, 1, reason: 'cell $i to ${i + 1} is not a corner turn');
        expect(dy, 1, reason: 'cell $i to ${i + 1} is not a corner turn');
        corners++;
      }

      expect(corners, 4);
    });
  });

  group('seats', () {
    test('start thirteen apart, as the server assumes', () {
      // `boardCell` on the server is `(seat * 13 + position) % 52`. This is
      // the client half of that same sum.
      for (int seat = 0; seat < 4; seat++) {
        expect(LudoGeometry.startCell(seat), seat * 13);
        expect(LudoGeometry.boardCell(seat, 0), seat * 13);
      }
    });

    test('each start a quarter of the way round, in its own arm', () {
      final Set<Offset> starts = <Offset>{
        for (int seat = 0; seat < 4; seat++)
          LudoGeometry.ring[LudoGeometry.startCell(seat)],
      };
      expect(starts, hasLength(4));
    });

    test('share one set of safe squares, whichever seat is asking', () {
      // The server stores these relative to the mover, which looks
      // seat-dependent and is not — the offsets are symmetric about thirteen.
      // This is the assertion that says so.
      const List<int> relative = <int>[0, 8, 13, 21, 26, 34, 39, 47];

      for (int seat = 0; seat < 4; seat++) {
        final Set<int> resolved = <int>{
          for (final int position in relative)
            LudoGeometry.boardCell(seat, position),
        };
        expect(resolved, LudoGeometry.safeCells, reason: 'seat $seat');
      }
    });

    test('give every seat its own corner and its own lane', () {
      final Set<Offset> yards = <Offset>{
        for (int seat = 0; seat < 4; seat++) ...LudoGeometry.yardSlots(seat),
      };
      // Four seats, four counters each, no two sharing a parking slot.
      expect(yards, hasLength(16));

      final Set<Offset> lanes = <Offset>{
        for (int seat = 0; seat < 4; seat++) ...LudoGeometry.homeLane(seat),
      };
      expect(lanes, hasLength(20));
      // A lane must not cross the ring, or a counter on its way home would be
      // drawn on a square somebody else is racing along.
      expect(lanes.intersection(LudoGeometry.ring.toSet()), isEmpty);
    });
  });

  group('placing a counter', () {
    test('parks it in its own yard while it is still there', () {
      for (int seat = 0; seat < 4; seat++) {
        for (int slot = 0; slot < 4; slot++) {
          expect(
            LudoGeometry.cellFor(
              seat: seat,
              position: LudoGeometry.inYard,
              slot: slot,
            ),
            LudoGeometry.yardSlots(seat)[slot],
          );
        }
      }
    });

    test('walks it round the ring from its own start', () {
      // Seat 1 at its own position 3 is three squares past its own start,
      // which is sixteen squares round the shared board.
      expect(
        LudoGeometry.cellFor(seat: 1, position: 3, slot: 0),
        LudoGeometry.ring[16],
      );
    });

    test('turns it into the lane at fifty-two and the middle at home', () {
      for (int seat = 0; seat < 4; seat++) {
        expect(
          LudoGeometry.cellFor(seat: seat, position: 52, slot: 0),
          LudoGeometry.homeLane(seat).first,
        );
        expect(
          LudoGeometry.cellFor(seat: seat, position: LudoGeometry.home, slot: 0),
          LudoGeometry.centre,
        );
      }
    });
  });

  group('which counters may move', () {
    LudoState stateWith({required int? dice, required List<int> mine}) =>
        LudoState.fromJson(<String, dynamic>{
          'status': 'playing',
          'currentPlayerId': 'me',
          'dice': dice,
          'order': const <String>['me', 'them'],
          'positions': <String, dynamic>{
            'me': mine,
            'them': const <int>[-1, -1, -1, -1],
          },
        });

    test('lets nothing out of the yard except on a six', () {
      expect(
        stateWith(dice: 3, mine: <int>[-1, -1, -1, -1]).movableTokens('me'),
        isEmpty,
      );
      expect(
        stateWith(dice: 6, mine: <int>[-1, -1, -1, -1]).movableTokens('me'),
        const <int>[0, 1, 2, 3],
      );
    });

    test('refuses a move that would overshoot home', () {
      // 54 + 3 is 57, past the 56 that means finished.
      expect(stateWith(dice: 3, mine: <int>[54, -1, -1, -1]).movableTokens('me'), isEmpty);
      // 54 + 2 lands exactly.
      expect(stateWith(dice: 2, mine: <int>[54, -1, -1, -1]).movableTokens('me'), const <int>[0]);
    });

    test('leaves finished counters alone', () {
      expect(stateWith(dice: 6, mine: <int>[56, 56, 10, -1]).movableTokens('me'), const <int>[2, 3]);
    });

    test('offers nothing with no dice on the table', () {
      expect(stateWith(dice: null, mine: <int>[10, 20, 30, 40]).movableTokens('me'), isEmpty);
      expect(stateWith(dice: null, mine: <int>[10, 20, 30, 40]).canRoll('me'), isTrue);
    });

    test('offers nothing when it is not your turn', () {
      final LudoState state = stateWith(dice: 6, mine: <int>[10, 20, 30, 40]);
      expect(state.movableTokens('them'), isEmpty);
      expect(state.canRoll('them'), isFalse);
    });
  });
}
