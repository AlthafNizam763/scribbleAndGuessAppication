/// The pure game-rules layer: scoring, word choice, hints, guess grading,
/// turn maths and the phase lifecycle. No Flutter, no I/O, no globals.
library;

export 'package:scribble_guess/core/rules/guess_matcher.dart';
export 'package:scribble_guess/core/rules/hint_engine.dart';
export 'package:scribble_guess/core/rules/room_state_machine.dart';
export 'package:scribble_guess/core/rules/scoring.dart';
export 'package:scribble_guess/core/rules/turn_timer.dart';
export 'package:scribble_guess/core/rules/word_selection.dart';
