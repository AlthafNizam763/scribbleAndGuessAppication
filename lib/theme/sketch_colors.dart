import 'package:flutter/material.dart';
import 'package:scribble_guess/theme/app_colors.dart';

/// The brightness-aware colour set of the sketchbook, carried on [ThemeData]
/// so widgets can read `context.sketch.ink` instead of branching on brightness.
///
/// [light] is warm paper with brown-black ink; [dark] is a night desk, soft
/// chalk on deep warm charcoal.
final class SketchColors extends ThemeExtension<SketchColors> {
  /// Creates a sketchbook colour set. Prefer [light] or [dark].
  const SketchColors({
    required this.paper,
    required this.paperDim,
    required this.paperShade,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.canvasWhite,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.accentRed,
    required this.accentBlue,
    required this.accentYellow,
    required this.accentGreen,
    required this.accentPurple,
    required this.accentOrange,
    required this.accentPink,
    required this.accentTeal,
  });

  /// The page every screen is printed on.
  final Color paper;

  /// A slightly recessed page, for inset surfaces such as inputs.
  final Color paperDim;

  /// The most distinct page tone, for pressed, selected and striped surfaces.
  final Color paperShade;

  /// Primary text and every hand-drawn outline.
  final Color ink;

  /// Secondary text and captions.
  final Color inkSoft;

  /// Dividers, placeholders and disabled marks.
  final Color inkFaint;

  /// The sheet the drawing canvas is painted on; light in both themes.
  final Color canvasWhite;

  /// Positive outcome: correct guess, connected, saved.
  final Color success;

  /// Caution: nearly out of time, close guess, unsaved changes.
  final Color warning;

  /// Destructive or failed: kick, ban, disconnected, error.
  final Color danger;

  /// Neutral information: hints, tips, system notices.
  final Color info;

  /// Felt-tip red.
  final Color accentRed;

  /// Ballpoint blue.
  final Color accentBlue;

  /// Highlighter yellow.
  final Color accentYellow;

  /// Grass-marker green.
  final Color accentGreen;

  /// Grape marker purple.
  final Color accentPurple;

  /// Traffic-cone orange.
  final Color accentOrange;

  /// Bubblegum pink.
  final Color accentPink;

  /// Chalkboard teal.
  final Color accentTeal;

  /// The warm paper sketchbook.
  static const SketchColors light = SketchColors(
    paper: AppColors.paper,
    paperDim: AppColors.paperDim,
    paperShade: AppColors.paperShade,
    ink: AppColors.ink,
    inkSoft: AppColors.inkSoft,
    inkFaint: AppColors.inkFaint,
    canvasWhite: AppColors.canvasWhite,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    info: AppColors.info,
    accentRed: AppColors.accentRed,
    accentBlue: AppColors.accentBlue,
    accentYellow: AppColors.accentYellow,
    accentGreen: AppColors.accentGreen,
    accentPurple: AppColors.accentPurple,
    accentOrange: AppColors.accentOrange,
    accentPink: AppColors.accentPink,
    accentTeal: AppColors.accentTeal,
  );

  /// The night desk: chalk on deep warm charcoal.
  static const SketchColors dark = SketchColors(
    paper: AppColors.darkPaper,
    paperDim: AppColors.darkPaperDim,
    paperShade: AppColors.darkPaperShade,
    ink: AppColors.darkInk,
    inkSoft: AppColors.darkInkSoft,
    inkFaint: AppColors.darkInkFaint,
    canvasWhite: AppColors.darkCanvasWhite,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    danger: AppColors.darkDanger,
    info: AppColors.darkInfo,
    accentRed: AppColors.darkAccentRed,
    accentBlue: AppColors.darkAccentBlue,
    accentYellow: AppColors.darkAccentYellow,
    accentGreen: AppColors.darkAccentGreen,
    accentPurple: AppColors.darkAccentPurple,
    accentOrange: AppColors.darkAccentOrange,
    accentPink: AppColors.darkAccentPink,
    accentTeal: AppColors.darkAccentTeal,
  );

  /// The eight accents in the same order as `AppColors.avatarPalette`, so a
  /// `Player.avatarColorIndex` can be resolved against the active brightness.
  List<Color> get accents => <Color>[
    accentRed,
    accentBlue,
    accentYellow,
    accentGreen,
    accentPurple,
    accentOrange,
    accentPink,
    accentTeal,
  ];

  /// Returns the accent for [index], wrapping so that any int is safe.
  Color accentAt(int index) => accents[index.abs() % accents.length];

  @override
  SketchColors copyWith({
    Color? paper,
    Color? paperDim,
    Color? paperShade,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? canvasWhite,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? accentRed,
    Color? accentBlue,
    Color? accentYellow,
    Color? accentGreen,
    Color? accentPurple,
    Color? accentOrange,
    Color? accentPink,
    Color? accentTeal,
  }) {
    return SketchColors(
      paper: paper ?? this.paper,
      paperDim: paperDim ?? this.paperDim,
      paperShade: paperShade ?? this.paperShade,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      canvasWhite: canvasWhite ?? this.canvasWhite,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      accentRed: accentRed ?? this.accentRed,
      accentBlue: accentBlue ?? this.accentBlue,
      accentYellow: accentYellow ?? this.accentYellow,
      accentGreen: accentGreen ?? this.accentGreen,
      accentPurple: accentPurple ?? this.accentPurple,
      accentOrange: accentOrange ?? this.accentOrange,
      accentPink: accentPink ?? this.accentPink,
      accentTeal: accentTeal ?? this.accentTeal,
    );
  }

  @override
  SketchColors lerp(covariant SketchColors? other, double t) {
    if (other == null) {
      return this;
    }
    return SketchColors(
      paper: Color.lerp(paper, other.paper, t)!,
      paperDim: Color.lerp(paperDim, other.paperDim, t)!,
      paperShade: Color.lerp(paperShade, other.paperShade, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      canvasWhite: Color.lerp(canvasWhite, other.canvasWhite, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      accentRed: Color.lerp(accentRed, other.accentRed, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      accentYellow: Color.lerp(accentYellow, other.accentYellow, t)!,
      accentGreen: Color.lerp(accentGreen, other.accentGreen, t)!,
      accentPurple: Color.lerp(accentPurple, other.accentPurple, t)!,
      accentOrange: Color.lerp(accentOrange, other.accentOrange, t)!,
      accentPink: Color.lerp(accentPink, other.accentPink, t)!,
      accentTeal: Color.lerp(accentTeal, other.accentTeal, t)!,
    );
  }

  List<Object?> get _props => <Object?>[
    paper,
    paperDim,
    paperShade,
    ink,
    inkSoft,
    inkFaint,
    canvasWhite,
    success,
    warning,
    danger,
    info,
    accentRed,
    accentBlue,
    accentYellow,
    accentGreen,
    accentPurple,
    accentOrange,
    accentPink,
    accentTeal,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! SketchColors) {
      return false;
    }
    final List<Object?> mine = _props;
    final List<Object?> theirs = other._props;
    for (int i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_props);
}

/// Sugar for reading the sketchbook palette off a [BuildContext].
extension SketchColorsX on BuildContext {
  /// The active sketchbook palette.
  ///
  /// Falls back to [SketchColors.light] when the extension is missing, so a
  /// widget rendered under a bare [ThemeData] still paints instead of throwing.
  SketchColors get sketch =>
      Theme.of(this).extension<SketchColors>() ?? SketchColors.light;
}
