import 'package:flutter/painting.dart';

/// The raw colour tokens of the Scribble & Guess sketchbook.
///
/// These are the pigments, not the theme. Widgets should almost always read
/// colours through `context.sketch` (see `SketchColors`) so they follow the
/// active brightness; reach for [AppColors] directly only for brightness
/// independent data such as [avatarPalette] and [drawingPalette].
abstract final class AppColors {
  // ---------------------------------------------------------------- light ---

  /// Warm off-white page the light theme is printed on.
  static const Color paper = Color(0xFFFBF7EF);

  /// Slightly recessed paper, for inset surfaces such as text fields.
  static const Color paperDim = Color(0xFFF4EEE2);

  /// Deepest paper tone, for pressed, selected and striped surfaces.
  static const Color paperShade = Color(0xFFE7DDC9);

  /// Near-black ink with a warm brown cast, used for text and outlines.
  static const Color ink = Color(0xFF2A2622);

  /// Softer ink for secondary text and captions.
  static const Color inkSoft = Color(0xFF5C544B);

  /// Faded pencil ink for dividers, placeholders and disabled marks.
  static const Color inkFaint = Color(0xFF9A8F7E);

  /// The white sheet the drawing canvas is painted on.
  static const Color canvasWhite = Color(0xFFFFFFFF);

  // -------------------------------------------------------------- accents ---

  /// Felt-tip red.
  static const Color accentRed = Color(0xFFD2544B);

  /// Ballpoint blue.
  static const Color accentBlue = Color(0xFF37719E);

  /// Highlighter yellow.
  static const Color accentYellow = Color(0xFFE8B84B);

  /// Grass-marker green.
  static const Color accentGreen = Color(0xFF62A15B);

  /// Grape marker purple.
  static const Color accentPurple = Color(0xFF8B6BB1);

  /// Traffic-cone orange.
  static const Color accentOrange = Color(0xFFE08A3C);

  /// Bubblegum pink.
  static const Color accentPink = Color(0xFFD96A98);

  /// Chalkboard teal.
  static const Color accentTeal = Color(0xFF3E9E96);

  // ------------------------------------------------------------ semantics ---

  /// Positive outcome: correct guess, connected, saved.
  static const Color success = Color(0xFF4E9A57);

  /// Caution: nearly out of time, close guess, unsaved changes.
  static const Color warning = Color(0xFFD99A2B);

  /// Destructive or failed: kick, ban, disconnected, error.
  static const Color danger = Color(0xFFC1453C);

  /// Neutral information: hints, tips, system notices.
  static const Color info = Color(0xFF35719C);

  // ----------------------------------------------------------------- dark ---

  /// Deep warm charcoal the dark theme is printed on: the night desk.
  static const Color darkPaper = Color(0xFF1E1B18);

  /// Slightly recessed night paper, for inset surfaces.
  static const Color darkPaperDim = Color(0xFF191613);

  /// Raised night paper, for pressed, selected and striped surfaces.
  static const Color darkPaperShade = Color(0xFF2E2A25);

  /// Soft chalk white used for text and outlines at night.
  static const Color darkInk = Color(0xFFF2EBDD);

  /// Softer chalk for secondary text and captions.
  static const Color darkInkSoft = Color(0xFFBDB3A2);

  /// Faded chalk dust for dividers, placeholders and disabled marks.
  static const Color darkInkFaint = Color(0xFF6E655A);

  /// The drawing sheet stays light at night, only a touch warmer.
  static const Color darkCanvasWhite = Color(0xFFF3EEE3);

  /// Chalk red.
  static const Color darkAccentRed = Color(0xFFE8776C);

  /// Chalk blue.
  static const Color darkAccentBlue = Color(0xFF6BA3CE);

  /// Chalk yellow.
  static const Color darkAccentYellow = Color(0xFFEFC96B);

  /// Chalk green.
  static const Color darkAccentGreen = Color(0xFF7FBE7A);

  /// Chalk purple.
  static const Color darkAccentPurple = Color(0xFFAC8FD0);

  /// Chalk orange.
  static const Color darkAccentOrange = Color(0xFFEFA765);

  /// Chalk pink.
  static const Color darkAccentPink = Color(0xFFE790B4);

  /// Chalk teal.
  static const Color darkAccentTeal = Color(0xFF63BDB4);

  /// Positive outcome at night.
  static const Color darkSuccess = Color(0xFF74BC7D);

  /// Caution at night.
  static const Color darkWarning = Color(0xFFE6B451);

  /// Destructive or failed at night.
  static const Color darkDanger = Color(0xFFE4695E);

  /// Neutral information at night.
  static const Color darkInfo = Color(0xFF6FA8CE);

  // ------------------------------------------------------------- palettes ---

  /// The eight avatar colours, indexed by `Player.avatarColorIndex` (0..7).
  ///
  /// Order is fixed forever: an index is persisted with the profile and
  /// broadcast to every other player, so entries must never be reordered.
  static const List<Color> avatarPalette = <Color>[
    accentRed,
    accentBlue,
    accentYellow,
    accentGreen,
    accentPurple,
    accentOrange,
    accentPink,
    accentTeal,
  ];

  /// The twenty-four drawing colours, laid out as a painter's grid of six
  /// columns by four rows: neutrals, warms, cools, then pinks and browns.
  ///
  /// Stroke colours travel over the wire as raw ARGB ints, so these values are
  /// deliberately brightness independent and must never be reordered.
  static const List<Color> drawingPalette = <Color>[
    // Row 1 - neutrals, black through white.
    Color(0xFF000000),
    Color(0xFF3A3632),
    Color(0xFF6E6862),
    Color(0xFFA8A29A),
    Color(0xFFDCD6CC),
    Color(0xFFFFFFFF),
    // Row 2 - reds through yellows.
    Color(0xFF8C2F26),
    Color(0xFFC2453A),
    Color(0xFFE0663C),
    Color(0xFFE8913A),
    Color(0xFFE8B93F),
    Color(0xFFF2DC7A),
    // Row 3 - greens through blues.
    Color(0xFF4A7A2E),
    Color(0xFF6FA84A),
    Color(0xFF3FA898),
    Color(0xFF3B84B5),
    Color(0xFF2A4E8C),
    Color(0xFF6B5CA5),
    // Row 4 - purples, pinks and browns.
    Color(0xFF8E5FA8),
    Color(0xFFC25C93),
    Color(0xFFE79FBC),
    Color(0xFF6B4A38),
    Color(0xFF9C7B5E),
    Color(0xFFD9B98C),
  ];
}
