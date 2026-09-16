import 'package:flutter/material.dart';

/// The two hands that write Scribble & Guess.
///
/// PatrickHand is the marker: it signs every display, headline, title and
/// button. Nunito is the neat print: it carries body copy, chat, inputs and
/// small labels, where a handwriting face would cost legibility.
abstract final class AppTypography {
  /// Handwritten marker face used for display, headline, title and button text.
  ///
  /// Only a w400 file is bundled, so never ask this family for a heavier
  /// weight: the engine would synthesise a smeared fake bold.
  static const String displayFamily = 'PatrickHand';

  /// Rounded sans face used for body copy, chat, inputs and small labels.
  ///
  /// Bundled at w400, w600, w700 and w800.
  static const String bodyFamily = 'Nunito';

  /// A full Material 3 [TextTheme] inked in [onSurface].
  ///
  /// Pass the surface foreground of the active brightness — `ink` on light
  /// paper, chalk on the night desk.
  static TextTheme textTheme(Color onSurface) {
    return TextTheme(
      displayLarge: _marker(onSurface, 52, height: 1.06),
      displayMedium: _marker(onSurface, 44, height: 1.08),
      displaySmall: _marker(onSurface, 36, height: 1.10),
      headlineLarge: _marker(onSurface, 32, height: 1.14),
      headlineMedium: _marker(onSurface, 28, height: 1.16),
      headlineSmall: _marker(onSurface, 24, height: 1.20),
      titleLarge: _marker(onSurface, 22, height: 1.22, letterSpacing: 0.2),
      titleMedium: _marker(onSurface, 19, height: 1.24, letterSpacing: 0.2),
      titleSmall: _marker(onSurface, 17, height: 1.26, letterSpacing: 0.3),
      bodyLarge: _print(onSurface, 16, height: 1.45, letterSpacing: 0.1),
      bodyMedium: _print(onSurface, 14, height: 1.45, letterSpacing: 0.15),
      bodySmall: _print(onSurface, 12.5, height: 1.40, letterSpacing: 0.2),
      // Buttons are hand-lettered, so labelLarge stays on the marker.
      labelLarge: _marker(onSurface, 18, height: 1.20, letterSpacing: 0.5),
      labelMedium: _print(
        onSurface,
        13,
        height: 1.20,
        letterSpacing: 0.4,
        weight: FontWeight.w600,
      ),
      labelSmall: _print(
        onSurface,
        11,
        height: 1.20,
        letterSpacing: 0.6,
        weight: FontWeight.w700,
      ),
    );
  }

  /// One hand-lettered style. Weight is pinned to w400: the only file we ship.
  static TextStyle _marker(
    Color color,
    double size, {
    required double height,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontWeight: FontWeight.w400,
      fontSize: size,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  /// One printed style in Nunito.
  static TextStyle _print(
    Color color,
    double size, {
    required double height,
    required double letterSpacing,
    FontWeight weight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: bodyFamily,
      fontWeight: weight,
      fontSize: size,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }
}
