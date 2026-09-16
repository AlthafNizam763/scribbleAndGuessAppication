/// Every spacing, radius and sizing constant used by Scribble & Guess.
///
/// Widgets must never hard-code a padding, gap, radius or border width:
/// pull it from here so the whole app stays on one rhythm.
abstract final class AppSpacing {
  /// Hairline gap, used between tightly related glyphs (4).
  static const double xs = 4;

  /// Small gap, the default gap inside a row of controls (8).
  static const double sm = 8;

  /// Medium gap, the default inner padding of compact widgets (12).
  static const double md = 12;

  /// Large gap, the default padding of cards and screens (16).
  static const double lg = 16;

  /// Extra large gap, used between major sections (24).
  static const double xl = 24;

  /// Double extra large gap, used above and below hero content (32).
  static const double xxl = 32;

  /// Corner radius for small chips, badges and tooltips (10).
  static const double radiusSm = 10;

  /// Corner radius for buttons, inputs and cards (14).
  static const double radiusMd = 14;

  /// Corner radius for dialogs, sheets and hero panels (20).
  static const double radiusLg = 20;

  /// Stroke width of every hand-drawn ink border (2.0).
  static const double border = 2;

  /// Minimum width and height of any interactive target (48).
  static const double minTapTarget = 48;

  /// Maximum width of centred page content on large screens (1100).
  static const double maxContentWidth = 1100;
}
