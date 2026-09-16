import 'package:flutter/widgets.dart';

/// Every animation duration and curve in the app.
///
/// Motion here is deliberately cheap: short fades, slides and scales, nothing
/// above 250ms. Route every duration through [duration] or [durationFor] so a
/// player who has asked for reduced motion gets an instant, still interface
/// instead of a jumpy one.
abstract final class AppMotion {
  /// Micro feedback: press states, ticks, colour swaps (120ms).
  static const Duration fast = Duration(milliseconds: 120);

  /// The default: fades, cross-fades, list item entrances (200ms).
  static const Duration normal = Duration(milliseconds: 200);

  /// The longest allowed: sheets, dialogs, page transitions (250ms).
  static const Duration slow = Duration(milliseconds: 250);

  /// The one curve the sketchbook animates on.
  static const Curve standard = Curves.easeOut;

  /// [base], or [Duration.zero] when the platform asks for reduced motion.
  ///
  /// Reads `MediaQuery.maybeDisableAnimationsOf`, so it is safe to call from a
  /// context with no [MediaQuery] above it.
  static Duration duration(BuildContext context, Duration base) {
    return durationFor(
      reducedMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
      base: base,
    );
  }

  /// [base], or [Duration.zero] when [reducedMotion] is set.
  ///
  /// For callers that already hold the setting — an `AppSettings` value, say —
  /// and do not want to re-read the [MediaQuery].
  static Duration durationFor({
    required bool reducedMotion,
    required Duration base,
  }) {
    return reducedMotion ? Duration.zero : base;
  }
}
