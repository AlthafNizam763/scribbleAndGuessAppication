import 'package:flutter/painting.dart';

/// The raw colour tokens of STUPID GAMES.
///
/// These are the pigments, not the theme. Widgets should almost always read
/// colours through `context.palette` (see `AppPalette`) so they follow the
/// active brightness; reach for [AppColors] directly only for brightness
/// independent data such as [avatarPalette] and [drawingPalette].
///
/// The system is built on one strong primary — an electric violet — carried by
/// a coral secondary and an aqua tertiary, printed on near-black violet-tinted
/// surfaces at night and on cool off-white by day. Nothing here is a gradient
/// and nothing here glows: depth comes from surface steps and hairline borders,
/// which is what keeps it reading as premium rather than as a skin.
abstract final class AppColors {
  // -------------------------------------------------------------- primary ---

  /// The brand primary: electric violet. Every main action wears it.
  static const Color violet = Color(0xFF6C4DFF);

  /// A pressed, deepened violet, for held buttons and active navigation.
  static const Color violetDeep = Color(0xFF5436E0);

  /// The night-side violet: lifted so it still reads on a near-black surface.
  static const Color violetBright = Color(0xFF8B72FF);

  /// A whisper of violet, for selected rows and tinted containers by day.
  static const Color violetWash = Color(0xFFEDE9FF);

  /// The night equivalent of [violetWash].
  static const Color violetShade = Color(0xFF241F45);

  // ------------------------------------------------------------ secondary ---

  /// Hot coral. The second voice: highlights, streaks, new, live badges.
  static const Color coral = Color(0xFFFF4D7D);

  /// The night-side coral.
  static const Color coralBright = Color(0xFFFF7098);

  /// Coral at wash strength, by day.
  static const Color coralWash = Color(0xFFFFE7EE);

  /// Coral at wash strength, at night.
  static const Color coralShade = Color(0xFF3A1C2A);

  // ------------------------------------------------------------- tertiary ---

  /// Aqua. The cool third: scores, XP, anything that should feel earned.
  static const Color aqua = Color(0xFF00BFB4);

  /// The night-side aqua.
  static const Color aquaBright = Color(0xFF2BE0D3);

  /// Aqua at wash strength, by day.
  static const Color aquaWash = Color(0xFFDCF6F4);

  /// Aqua at wash strength, at night.
  static const Color aquaShade = Color(0xFF10332F);

  // ---------------------------------------------------------------- light ---

  /// Cool off-white the light theme is printed on.
  static const Color bg = Color(0xFFF5F4FA);

  /// The card surface: plain white, so cards lift off [bg] without a shadow.
  static const Color surface = Color(0xFFFFFFFF);

  /// A recessed surface, for inputs, tracks and wells.
  static const Color surfaceSunken = Color(0xFFEDECF5);

  /// A pressed or hovered surface, one step past [surfaceSunken].
  static const Color surfaceActive = Color(0xFFE3E1EF);

  /// The hairline every card, input and divider is drawn with.
  static const Color border = Color(0xFFE4E2EF);

  /// A stronger keyline, for focused and selected edges.
  static const Color borderStrong = Color(0xFFCFCCE1);

  /// Primary text: near-black with a violet cast, never pure black.
  static const Color text = Color(0xFF14121F);

  /// Secondary text and captions.
  static const Color textMuted = Color(0xFF5C5878);

  /// Placeholders, disabled marks and metadata.
  static const Color textFaint = Color(0xFF8E8AAB);

  /// The white sheet the drawing canvas is painted on.
  static const Color canvas = Color(0xFFFFFFFF);

  // ----------------------------------------------------------------- dark ---

  /// Near-black with a violet cast: the page the dark theme is printed on.
  static const Color darkBg = Color(0xFF0A0912);

  /// The card surface at night.
  static const Color darkSurface = Color(0xFF14121F);

  /// A recessed night surface, for inputs, tracks and wells.
  static const Color darkSurfaceSunken = Color(0xFF0F0E18);

  /// A pressed or hovered night surface.
  static const Color darkSurfaceActive = Color(0xFF232135);

  /// The hairline at night.
  static const Color darkBorder = Color(0xFF272539);

  /// A stronger night keyline, for focused and selected edges.
  static const Color darkBorderStrong = Color(0xFF3B3858);

  /// Primary text at night: warm white, never pure white.
  static const Color darkText = Color(0xFFF4F3FB);

  /// Secondary text and captions at night.
  static const Color darkTextMuted = Color(0xFFA5A1C2);

  /// Placeholders, disabled marks and metadata at night.
  static const Color darkTextFaint = Color(0xFF6E6A8E);

  /// The drawing sheet stays light at night, only a touch softer.
  static const Color darkCanvas = Color(0xFFF2F1F7);

  // --------------------------------------------------------- STUPID GAMES ---

  /// The colours of the platform mark itself.
  ///
  /// Distinct from the palette above, which dresses the interface. These
  /// belong to the cat and the wordmark, appear in the launcher icon, and are
  /// deliberately brightness independent: the icon is baked once and has to
  /// read on a light home screen and a dark one without being asked which.

  /// Wordmark violet: the STUPID half, and the platform primary.
  static const Color brandViolet = violet;

  /// The cat coat.
  static const Color brandOrange = Color(0xFFFF8A3D);

  /// Wordmark aqua: the GAMES half.
  static const Color brandAqua = aqua;

  /// The plate a platform icon is printed on.
  static const Color brandPlate = violet;

  /// The hot note: inner ears, and anything that needs to look delighted.
  static const Color brandPink = coral;

  /// The ink every mark outline is drawn in, on any background.
  static const Color brandInk = Color(0xFF14121F);

  // ------------------------------------------------------------ semantics ---

  /// Positive outcome: correct guess, connected, saved.
  static const Color success = Color(0xFF12B76A);

  /// Caution: nearly out of time, close guess, unsaved changes.
  static const Color warning = Color(0xFFF79009);

  /// Destructive or failed: kick, ban, disconnected, error.
  static const Color danger = Color(0xFFF0483C);

  /// Neutral information: hints, tips, system notices.
  static const Color info = Color(0xFF2E90FA);

  /// Positive outcome at night.
  static const Color darkSuccess = Color(0xFF3AD98C);

  /// Caution at night.
  static const Color darkWarning = Color(0xFFFDB022);

  /// Destructive or failed at night.
  static const Color darkDanger = Color(0xFFFF6B5E);

  /// Neutral information at night.
  static const Color darkInfo = Color(0xFF58AEFF);

  // -------------------------------------------------------------- accents ---
  //
  // The eight player accents. Named by hue rather than by role: they are
  // identity colours, handed out by index, and no one of them means anything.

  /// Accent 0.
  static const Color accentRed = Color(0xFFFF5A5F);

  /// Accent 1.
  static const Color accentBlue = Color(0xFF4D8BFF);

  /// Accent 2.
  static const Color accentYellow = Color(0xFFFFC53D);

  /// Accent 3.
  static const Color accentGreen = Color(0xFF2FD07B);

  /// Accent 4.
  static const Color accentPurple = Color(0xFF9B5CFF);

  /// Accent 5.
  static const Color accentOrange = Color(0xFFFF8A3D);

  /// Accent 6.
  static const Color accentPink = Color(0xFFFF5CA2);

  /// Accent 7.
  static const Color accentTeal = Color(0xFF00CFC1);

  /// Accent 0 at night.
  static const Color darkAccentRed = Color(0xFFFF7B7F);

  /// Accent 1 at night.
  static const Color darkAccentBlue = Color(0xFF74A5FF);

  /// Accent 2 at night.
  static const Color darkAccentYellow = Color(0xFFFFD264);

  /// Accent 3 at night.
  static const Color darkAccentGreen = Color(0xFF57DE99);

  /// Accent 4 at night.
  static const Color darkAccentPurple = Color(0xFFB286FF);

  /// Accent 5 at night.
  static const Color darkAccentOrange = Color(0xFFFFA463);

  /// Accent 6 at night.
  static const Color darkAccentPink = Color(0xFFFF7FB8);

  /// Accent 7 at night.
  static const Color darkAccentTeal = Color(0xFF2BE0D3);

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

  /// The twenty-four drawing colours, laid out as a painter grid of six
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
