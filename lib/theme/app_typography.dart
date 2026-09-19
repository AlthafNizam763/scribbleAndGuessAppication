import 'package:flutter/material.dart';

/// The two typefaces of STUPID GAMES.
///
/// **Space Grotesk** is the voice: a geometric grotesque with just enough
/// oddity in its letterforms to stop a screen of headings looking like a
/// dashboard. It signs every display, headline, title and score, always tight
/// and always heavy — the expressive half of the system.
///
/// **Plus Jakarta Sans** is the reading face: warm, wide-apertured and built
/// for small sizes, which is what body copy, chat, inputs and button labels
/// need. It carries five weights, so hierarchy inside a dense row comes from
/// weight rather than from yet another size.
///
/// Only the weights bundled in `pubspec.yaml` may be asked for. Requesting one
/// that is not there does not fail; the engine fakes it, and a synthesised
/// bold is exactly the smeared, slightly-wrong look this redesign exists to
/// get rid of.
abstract final class AppTypography {
  /// The expressive face: display, headline, title, score.
  ///
  /// Bundled at w400, w500 and w700. Never ask it for w600 or w800.
  static const String displayFamily = 'SpaceGrotesk';

  /// The reading face: body copy, chat, inputs, labels and button text.
  ///
  /// Bundled at w400, w500, w600, w700 and w800.
  static const String bodyFamily = 'PlusJakartaSans';

  // ---------------------------------------------------------------- weight ---

  /// Ordinary body text.
  static const FontWeight regular = FontWeight.w400;

  /// A body line that needs a nudge of emphasis without becoming a label.
  static const FontWeight medium = FontWeight.w500;

  /// Labels, metadata and secondary buttons.
  static const FontWeight semibold = FontWeight.w600;

  /// Headings, primary buttons and anything that has to be read first.
  static const FontWeight bold = FontWeight.w700;

  /// Reserved for numbers that matter: scores, timers, streaks, ranks.
  static const FontWeight black = FontWeight.w800;

  /// A full Material 3 [TextTheme] inked in [onSurface].
  ///
  /// Pass the surface foreground of the active brightness. The display sizes
  /// carry negative tracking, which is what makes a big heading read as
  /// designed rather than as a default; the small sizes carry positive
  /// tracking, which is what keeps an 11pt uppercase label legible.
  static TextTheme textTheme(Color onSurface) {
    return TextTheme(
      displayLarge: _display(onSurface, 44, height: 1.04, tracking: -1.4),
      displayMedium: _display(onSurface, 36, height: 1.06, tracking: -1.1),
      displaySmall: _display(onSurface, 30, height: 1.10, tracking: -0.8),
      headlineLarge: _display(onSurface, 27, height: 1.14, tracking: -0.7),
      headlineMedium: _display(onSurface, 23, height: 1.18, tracking: -0.5),
      headlineSmall: _display(onSurface, 20, height: 1.22, tracking: -0.4),
      titleLarge: _display(onSurface, 18, height: 1.26, tracking: -0.3),
      titleMedium: _print(
        onSurface,
        16,
        height: 1.30,
        tracking: -0.1,
        weight: bold,
      ),
      titleSmall: _print(
        onSurface,
        14.5,
        height: 1.32,
        tracking: 0,
        weight: bold,
      ),
      bodyLarge: _print(onSurface, 15.5, height: 1.50, tracking: 0),
      bodyMedium: _print(onSurface, 14, height: 1.50, tracking: 0),
      bodySmall: _print(onSurface, 12.5, height: 1.45, tracking: 0.1),
      // Buttons. Heavy and slightly tracked out, so a short label still has
      // presence inside a 52pt pill.
      labelLarge: _print(
        onSurface,
        15,
        height: 1.20,
        tracking: 0.2,
        weight: bold,
      ),
      labelMedium: _print(
        onSurface,
        13,
        height: 1.20,
        tracking: 0.2,
        weight: semibold,
      ),
      // The eyebrow: small, heavy, tracked wide. Almost always uppercased by
      // the caller, which is why the tracking is this generous.
      labelSmall: _print(
        onSurface,
        11,
        height: 1.20,
        tracking: 0.9,
        weight: bold,
      ),
    );
  }

  /// A number that is meant to be looked at: a score, a timer, a rank.
  ///
  /// Tabular figures so a counting timer does not jitter its own width, and
  /// tight tracking so four digits still read as one object.
  static TextStyle numeric(
    Color color, {
    required double size,
    FontWeight weight = bold,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontWeight: weight == black ? bold : weight,
      fontSize: size,
      height: 1.0,
      letterSpacing: -0.5,
      color: color,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  /// One expressive style in Space Grotesk.
  static TextStyle _display(
    Color color,
    double size, {
    required double height,
    required double tracking,
    FontWeight weight = bold,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontWeight: weight,
      fontSize: size,
      height: height,
      letterSpacing: tracking,
      color: color,
    );
  }

  /// One reading style in Plus Jakarta Sans.
  static TextStyle _print(
    Color color,
    double size, {
    required double height,
    required double tracking,
    FontWeight weight = regular,
  }) {
    return TextStyle(
      fontFamily: bodyFamily,
      fontWeight: weight,
      fontSize: size,
      height: height,
      letterSpacing: tracking,
      color: color,
    );
  }
}
