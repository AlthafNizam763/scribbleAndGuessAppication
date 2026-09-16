import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/stroke.dart';

/// The committed drawing plus its redo history. Every operation is pure and
/// returns a new board, so the board can be held in immutable state.
class DrawingBoard extends Equatable {
  /// Creates a board.
  const DrawingBoard({
    this.strokes = const <Stroke>[],
    this.redoStack = const <Stroke>[],
  });

  /// Builds a board from a decoded JSON map, tolerating malformed values.
  factory DrawingBoard.fromJson(Map<String, dynamic> json) => DrawingBoard(
        strokes: <Stroke>[
          for (final dynamic raw in asList(json['strokes']))
            Stroke.fromJson(asMap(raw)),
        ],
        redoStack: <Stroke>[
          for (final dynamic raw in asList(json['redoStack']))
            Stroke.fromJson(asMap(raw)),
        ],
      );

  /// A board with nothing drawn on it.
  static const DrawingBoard empty = DrawingBoard();

  /// Committed strokes in paint order.
  final List<Stroke> strokes;

  /// Strokes that were undone and can be redone, oldest first.
  final List<Stroke> redoStack;

  /// Whether [undo] would change anything.
  bool get canUndo => strokes.isNotEmpty;

  /// Whether [redo] would change anything.
  bool get canRedo => redoStack.isNotEmpty;

  /// Returns a board with [stroke] appended and the redo history dropped.
  DrawingBoard addStroke(Stroke stroke) => DrawingBoard(
        strokes: <Stroke>[...strokes, stroke],
        redoStack: const <Stroke>[],
      );

  /// Returns a board where the stroke sharing an id with [stroke] is swapped
  /// for it. Appends [stroke] when no such stroke exists yet, which is what
  /// happens while a remote stroke is still growing.
  DrawingBoard replaceStroke(Stroke stroke) {
    // The stroke being replaced is almost always the last one: only one person
    // draws at a time and their batches arrive in order, so an inbound
    // `s:draw:append` is extending the line that is already on the end of the
    // board. Checking that first turns the common case — about seventeen calls
    // a second for the whole of a turn — from a scan of every stroke on the
    // board into a single comparison.
    //
    // The scan is still here for the cases that are not that: a batch arriving
    // out of order, or after an undo moved the target. Correctness comes from
    // the fallback; the speed comes from almost never needing it.
    if (strokes.isNotEmpty && strokes.last.id == stroke.id) {
      final List<Stroke> next = <Stroke>[...strokes];
      next[next.length - 1] = stroke;
      return DrawingBoard(strokes: next, redoStack: redoStack);
    }

    final int index = strokes.indexWhere((Stroke s) => s.id == stroke.id);
    if (index < 0) {
      return DrawingBoard(
        strokes: <Stroke>[...strokes, stroke],
        redoStack: redoStack,
      );
    }
    final List<Stroke> next = <Stroke>[...strokes];
    next[index] = stroke;
    return DrawingBoard(strokes: next, redoStack: redoStack);
  }

  /// Returns a board with the last stroke moved onto the redo stack, or with
  /// the stroke identified by [strokeId] when one is given. Returns the same
  /// board when there is nothing to undo.
  DrawingBoard undo([String? strokeId]) {
    if (strokes.isEmpty) return this;
    final int index = strokeId == null
        ? strokes.length - 1
        : strokes.lastIndexWhere((Stroke s) => s.id == strokeId);
    if (index < 0) return this;
    final List<Stroke> next = <Stroke>[...strokes];
    final Stroke removed = next.removeAt(index);
    return DrawingBoard(
      strokes: next,
      redoStack: <Stroke>[...redoStack, removed],
    );
  }

  /// Returns a board with the most recently undone stroke put back, or with
  /// [stroke] put back when one is given. Returns the same board when there
  /// is nothing to redo.
  DrawingBoard redo([Stroke? stroke]) {
    if (stroke != null) {
      return DrawingBoard(
        strokes: <Stroke>[...strokes, stroke],
        redoStack: <Stroke>[
          for (final Stroke s in redoStack)
            if (s.id != stroke.id) s,
        ],
      );
    }
    if (redoStack.isEmpty) return this;
    final List<Stroke> nextRedo = <Stroke>[...redoStack];
    final Stroke restored = nextRedo.removeLast();
    return DrawingBoard(
      strokes: <Stroke>[...strokes, restored],
      redoStack: nextRedo,
    );
  }

  /// Returns an empty board.
  DrawingBoard clear() => empty;

  /// Serializes this board to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'strokes': <Map<String, dynamic>>[
          for (final Stroke stroke in strokes) stroke.toJson(),
        ],
        'redoStack': <Map<String, dynamic>>[
          for (final Stroke stroke in redoStack) stroke.toJson(),
        ],
      };

  /// Returns a copy with the given fields replaced.
  DrawingBoard copyWith({
    List<Stroke>? strokes,
    List<Stroke>? redoStack,
  }) =>
      DrawingBoard(
        strokes: strokes ?? this.strokes,
        redoStack: redoStack ?? this.redoStack,
      );

  @override
  List<Object?> get props => <Object?>[strokes, redoStack];

  @override
  bool get stringify => true;
}
