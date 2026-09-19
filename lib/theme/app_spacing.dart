/// Every spacing, radius and sizing constant used by STUPID GAMES.
///
/// Widgets must never hard-code a padding, gap, radius or border width: pull
/// it from here so the whole app stays on one rhythm. The scale is a 4pt grid,
/// which is what keeps a dense game HUD and a roomy settings list feeling like
/// the same product.
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

  /// Triple extra large gap, for the top of a hero screen (48).
  static const double xxxl = 48;

  // --------------------------------------------------------------- radius ---
  //
  // Modern and generous. Small shapes get proportionally rounder corners than
  // large ones, which is what stops a chip from looking like a shrunken card.

  /// Corner radius for badges, swatches and the tightest chips (8).
  static const double radiusXs = 8;

  /// Corner radius for chips, small tiles and inline pills (12).
  static const double radiusSm = 12;

  /// Corner radius for buttons, inputs and list rows (16).
  static const double radiusMd = 16;

  /// Corner radius for cards and panels (20).
  static const double radiusLg = 20;

  /// Corner radius for dialogs, sheets and hero surfaces (28).
  static const double radiusXl = 28;

  /// Effectively a capsule, for pills and avatars (999).
  static const double radiusPill = 999;

  // --------------------------------------------------------------- strokes ---

  /// The hairline every card and divider is drawn with (1.0).
  static const double hairline = 1;

  /// A visible keyline, for outlined buttons and selected edges (1.5).
  static const double border = 1.5;

  /// The heaviest keyline, for focus rings and the active nav pill (2.0).
  static const double borderThick = 2;

  // ---------------------------------------------------------------- sizing ---

  /// Minimum width and height of any interactive target (48).
  static const double minTapTarget = 48;

  /// Height of a standard control: button, input, chip row (52).
  static const double controlHeight = 52;

  /// Height of a compact control, used inside dense rows (40).
  static const double controlHeightSm = 40;

  /// Maximum width of centred page content on large screens (1100).
  static const double maxContentWidth = 1100;
}
