/// Barrel for the domain repository layer.
///
/// These are the only contracts the UI, the providers and the tests are
/// allowed to depend on. Concrete socket-backed and practice-mode
/// implementations live under `lib/data/repositories/` and are selected at
/// runtime through `BackendMode`, so importing this file never pulls in a
/// transport.
library;

export 'package:scribble_guess/repositories/chat_repository.dart';
export 'package:scribble_guess/repositories/drawing_repository.dart';
export 'package:scribble_guess/repositories/game_repository.dart';
export 'package:scribble_guess/repositories/leaderboard_repository.dart';
export 'package:scribble_guess/repositories/platform_game_repository.dart';
export 'package:scribble_guess/repositories/profile_repository.dart';
export 'package:scribble_guess/repositories/realtime_gateway.dart';
export 'package:scribble_guess/repositories/room_repository.dart';
export 'package:scribble_guess/repositories/settings_repository.dart';
