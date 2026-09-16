/// Pure clock maths for a turn, driven by the server clock.
///
/// The client never trusts its own wall clock: every function takes the
/// server-corrected "now" so a skewed device still shows the right countdown.
abstract final class TurnTimer {
  /// Time left until [turnEndMs], never negative.
  static Duration remaining({
    required int turnEndMs,
    required int serverNowMs,
  }) {
    final int leftMs = turnEndMs - serverNowMs;
    return leftMs <= 0 ? Duration.zero : Duration(milliseconds: leftMs);
  }

  /// Whole seconds left until [turnEndMs], rounded up and never negative.
  static int secondsRemaining({
    required int turnEndMs,
    required int serverNowMs,
  }) {
    final int leftMs = turnEndMs - serverNowMs;
    return leftMs <= 0 ? 0 : (leftMs + 999) ~/ 1000;
  }

  /// Whether the turn deadline has passed.
  static bool isExpired({required int turnEndMs, required int serverNowMs}) =>
      serverNowMs >= turnEndMs;

  /// Fraction of the turn already elapsed, clamped to `0..1`.
  ///
  /// A window that ends before it starts reads as finished, so a malformed
  /// payload can never leave a progress bar stuck.
  static double progress({
    required int startMs,
    required int endMs,
    required int nowMs,
  }) {
    final int span = endMs - startMs;
    if (span <= 0) {
      return 1;
    }
    final int elapsed = nowMs - startMs;
    if (elapsed <= 0) {
      return 0;
    }
    return elapsed >= span ? 1 : elapsed / span;
  }
}
