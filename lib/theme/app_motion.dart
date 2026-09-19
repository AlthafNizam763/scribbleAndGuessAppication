import 'package:flutter/widgets.dart';

/// Every animation duration and curve in the app.
///
/// Motion here is deliberately cheap and short: presses, fades, slides and
/// scales, nothing above 280ms. The app is playful, not bouncy — an interface
/// a player sees a hundred times an evening cannot afford a spring on every
/// tap. Route every duration through [duration] or [durationFor] so a player
/// who has asked for reduced motion gets an instant, still interface instead
/// of a jumpy one.
abstract final class AppMotion {
  /// Micro feedback: press states, ticks, colour swaps (110ms).
  static const Duration instant = Duration(milliseconds: 110);

  /// Micro feedback. Kept as the historical name for [instant].
  static const Duration fast = instant;

  /// The default: fades, cross-fades, list item entrances (200ms).
  static const Duration normal = Duration(milliseconds: 200);

  /// Sheets, dialogs and page transitions (280ms).
  static const Duration slow = Duration(milliseconds: 280);

  /// Ambient, non-blocking motion: a pulsing live dot, a shimmer (1200ms).
  static const Duration ambient = Duration(milliseconds: 1200);

  /// The curve almost everything animates on: fast out, settle in.
  static const Curve standard = Curves.easeOutCubic;

  /// For something arriving on screen — a sheet, a toast, a new row.
  static const Curve entrance = Curves.easeOutBack;

  /// For something leaving. Never [entrance]: an overshoot on the way out
  /// reads as a glitch.
  static const Curve exit = Curves.easeInCubic;

  /// How far a control shrinks while held (0.96 of its size).
  ///
  /// A token rather than a number chosen per widget, so the whole app presses
  /// with the same weight.
  static const double pressScale = 0.96;

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

  /// [pressScale], or 1 when the platform asks for reduced motion.
  static double pressScaleOf(BuildContext context) {
    final bool reduced =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return reduced ? 1 : pressScale;
  }
}
