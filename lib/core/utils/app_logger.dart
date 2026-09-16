import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kReleaseMode;

/// The single logging entry point of the app.
///
/// `avoid_print` is enforced repo-wide: use [d], [i], [w] or [e] instead.
/// Every call is a no-op in release builds, so logging costs nothing in
/// production and never leaks game state to the console.
abstract final class AppLogger {
  /// Channel name attached to every record.
  static const String name = 'ScribbleGuess';

  /// Master switch, defaulting to on in debug and profile builds.
  ///
  /// Tests flip this to `false` to keep their output clean.
  static bool enabled = !kReleaseMode;

  /// Logs verbose detail useful while debugging.
  static void d(String message, [Object? error, StackTrace? stackTrace]) {
    _log(message, _levelDebug, error, stackTrace);
  }

  /// Logs a notable but expected lifecycle event.
  static void i(String message, [Object? error, StackTrace? stackTrace]) {
    _log(message, _levelInfo, error, stackTrace);
  }

  /// Logs a recoverable problem worth investigating.
  static void w(String message, [Object? error, StackTrace? stackTrace]) {
    _log(message, _levelWarning, error, stackTrace);
  }

  /// Logs a failure that broke the current operation.
  static void e(String message, [Object? error, StackTrace? stackTrace]) {
    _log(message, _levelError, error, stackTrace);
  }

  static const int _levelDebug = 500;
  static const int _levelInfo = 800;
  static const int _levelWarning = 900;
  static const int _levelError = 1000;

  static void _log(
    String message,
    int level,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (kReleaseMode || !enabled) {
      return;
    }
    developer.log(
      message,
      name: name,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
