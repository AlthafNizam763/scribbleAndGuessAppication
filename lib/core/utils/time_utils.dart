import 'package:scribble_guess/core/constants/app_strings.dart';

/// Formatting helpers for the clocks and timestamps shown in the UI.
///
/// Pure functions only: no locale lookups and no `DateTime.now()` calls, so
/// every result is reproducible in tests.
abstract final class TimeUtils {
  /// Formats a countdown as `M:SS`, clamping negative input to `0:00`.
  static String formatSeconds(int seconds) {
    final int safe = seconds < 0 ? 0 : seconds;
    final int minutes = safe ~/ 60;
    final int rest = safe % 60;
    return '$minutes:${_two(rest)}';
  }

  /// Formats a countdown as `MM:SS`, clamping negative input to `00:00`.
  static String formatSecondsPadded(int seconds) {
    final int safe = seconds < 0 ? 0 : seconds;
    return '${_two(safe ~/ 60)}:${_two(safe % 60)}';
  }

  /// Formats an epoch timestamp as a local 24-hour `HH:MM` wall clock.
  static String formatClock(int epochMs) {
    final DateTime local = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${_two(local.hour)}:${_two(local.minute)}';
  }

  /// Renders the age of [epochMs] relative to [nowMs] in one or two glyphs.
  ///
  /// Examples: `now`, `42s`, `9m`, `3h`, `5d`, `2w`, `1y`. Timestamps in the
  /// future collapse to `now`.
  /// The age of [epochMs] relative to [nowMs], as a magnitude and the
  /// catalogue key of its unit.
  ///
  /// Split out from [relativeShort] so the arithmetic has one home and the
  /// wording has another: `AppText.relativeShort` formats these two values
  /// in the player's language, while this stays a pure function with no
  /// opinion about how a unit is spelled. A value of zero means "now".
  static ({int value, String suffixKey}) relativeParts(int epochMs, int nowMs) {
    final int deltaMs = nowMs - epochMs;
    if (deltaMs < 10000) return (value: 0, suffixKey: 'timeNow');

    final int seconds = deltaMs ~/ 1000;
    if (seconds < 60) return (value: seconds, suffixKey: 'timeSecondsSuffix');

    final int minutes = seconds ~/ 60;
    if (minutes < 60) return (value: minutes, suffixKey: 'timeMinutesSuffix');

    final int hours = minutes ~/ 60;
    if (hours < 24) return (value: hours, suffixKey: 'timeHoursSuffix');

    final int days = hours ~/ 24;
    if (days < 7) return (value: days, suffixKey: 'timeDaysSuffix');

    if (days < 365) {
      return (value: days ~/ 7, suffixKey: 'timeWeeksSuffix');
    }
    return (value: days ~/ 365, suffixKey: 'timeYearsSuffix');
  }

  /// The English rendering of [relativeParts], for code with no context.
  static String relativeShort(int epochMs, int nowMs) {
    final int deltaMs = nowMs - epochMs;
    if (deltaMs < 10000) {
      return AppStrings.timeNow;
    }
    final int seconds = deltaMs ~/ 1000;
    if (seconds < 60) {
      return '$seconds${AppStrings.timeSecondsSuffix}';
    }
    final int minutes = seconds ~/ 60;
    if (minutes < 60) {
      return '$minutes${AppStrings.timeMinutesSuffix}';
    }
    final int hours = minutes ~/ 60;
    if (hours < 24) {
      return '$hours${AppStrings.timeHoursSuffix}';
    }
    final int days = hours ~/ 24;
    if (days < 7) {
      return '$days${AppStrings.timeDaysSuffix}';
    }
    final int weeks = days ~/ 7;
    if (days < 365) {
      return '$weeks${AppStrings.timeWeeksSuffix}';
    }
    return '${days ~/ 365}${AppStrings.timeYearsSuffix}';
  }

  /// Whole seconds left until [endMs], never negative.
  static int secondsUntil({required int endMs, required int nowMs}) {
    final int remainingMs = endMs - nowMs;
    return remainingMs <= 0 ? 0 : (remainingMs + 999) ~/ 1000;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
