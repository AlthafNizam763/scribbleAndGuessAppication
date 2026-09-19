import 'package:flutter/material.dart';
import 'package:scribble_guess/theme/app_colors.dart';

/// The brightness-aware palette of STUPID GAMES, carried on [ThemeData] so
/// widgets can read `context.palette.text` instead of branching on brightness.
///
/// [light] is cool off-white with near-black violet-cast ink; [dark] is the
/// house style — a near-black violet-tinted page that the primary, the coral
/// and the aqua all burn against.
///
/// Three rules hold the system together, and breaking any one of them is what
/// makes an app look like a pile of separately-styled screens:
///
/// 1. A screen never invents a colour. Everything is a field on this class.
/// 2. Depth is a surface step plus a hairline, not a shadow.
/// 3. [primary] means *the action*. Colour that is merely decorative comes
///    from [accentAt], which is identity, or from the semantic four.
final class AppPalette extends ThemeExtension<AppPalette> {
  /// Creates a palette. Prefer [light] or [dark].
  const AppPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.surfaceActive,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.canvas,
    required this.primary,
    required this.primaryDeep,
    required this.primaryWash,
    required this.onPrimary,
    required this.secondary,
    required this.secondaryWash,
    required this.tertiary,
    required this.tertiaryWash,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.shadow,
    required this.scrim,
    required this.accentRed,
    required this.accentBlue,
    required this.accentYellow,
    required this.accentGreen,
    required this.accentPurple,
    required this.accentOrange,
    required this.accentPink,
    required this.accentTeal,
  });

  /// Whether this is the night palette. Lets a widget pick a wash strength
  /// without reaching back to [Theme].
  final bool isDark;

  // -------------------------------------------------------------- surfaces ---

  /// The page every screen is printed on.
  final Color bg;

  /// A card, a sheet, an app bar: the surface that sits on [bg].
  final Color surface;

  /// A recessed surface: inputs, tracks, wells, skeletons.
  final Color surfaceSunken;

  /// A pressed, hovered or selected surface.
  final Color surfaceActive;

  /// The hairline every card, row and divider is drawn with.
  final Color border;

  /// A stronger keyline, for outlined controls and selected edges.
  final Color borderStrong;

  // ------------------------------------------------------------------ text ---

  /// Primary text and icons.
  final Color text;

  /// Secondary text, captions and inactive icons.
  final Color textMuted;

  /// Placeholders, disabled marks and metadata.
  final Color textFaint;

  /// The sheet the drawing canvas is painted on; light in both themes.
  final Color canvas;

  // ----------------------------------------------------------------- brand ---

  /// The action colour. One primary button per screen, and the active nav.
  final Color primary;

  /// [primary] while held, and the deeper half of any primary pairing.
  final Color primaryDeep;

  /// [primary] at wash strength, for tinted containers and selected rows.
  final Color primaryWash;

  /// Text and icons printed on [primary]. Near-white in both themes, because
  /// a filled violet button is dark whichever way the phone is set.
  final Color onPrimary;

  /// The second voice: live badges, streaks, anything urgent and social.
  final Color secondary;

  /// [secondary] at wash strength.
  final Color secondaryWash;

  /// The cool third: scores, XP, progress, anything earned.
  final Color tertiary;

  /// [tertiary] at wash strength.
  final Color tertiaryWash;

  // ------------------------------------------------------------- semantics ---

  /// Positive outcome: correct guess, connected, saved.
  final Color success;

  /// Caution: nearly out of time, close guess, unsaved changes.
  final Color warning;

  /// Destructive or failed: kick, ban, disconnected, error.
  final Color danger;

  /// Neutral information: hints, tips, system notices.
  final Color info;

  // ----------------------------------------------------------------- depth ---

  /// The colour a shadow is cast in.
  final Color shadow;

  /// The veil behind a dialog or a modal sheet.
  final Color scrim;

  // --------------------------------------------------------------- accents ---

  /// Accent 0.
  final Color accentRed;

  /// Accent 1.
  final Color accentBlue;

  /// Accent 2.
  final Color accentYellow;

  /// Accent 3.
  final Color accentGreen;

  /// Accent 4.
  final Color accentPurple;

  /// Accent 5.
  final Color accentOrange;

  /// Accent 6.
  final Color accentPink;

  /// Accent 7.
  final Color accentTeal;

  /// The day palette: cool off-white, near-black violet-cast ink.
  static const AppPalette light = AppPalette(
    isDark: false,
    bg: AppColors.bg,
    surface: AppColors.surface,
    surfaceSunken: AppColors.surfaceSunken,
    surfaceActive: AppColors.surfaceActive,
    border: AppColors.border,
    borderStrong: AppColors.borderStrong,
    text: AppColors.text,
    textMuted: AppColors.textMuted,
    textFaint: AppColors.textFaint,
    canvas: AppColors.canvas,
    primary: AppColors.violet,
    primaryDeep: AppColors.violetDeep,
    primaryWash: AppColors.violetWash,
    onPrimary: Color(0xFFFFFFFF),
    secondary: AppColors.coral,
    secondaryWash: AppColors.coralWash,
    tertiary: AppColors.aqua,
    tertiaryWash: AppColors.aquaWash,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    info: AppColors.info,
    shadow: Color(0xFF14121F),
    scrim: Color(0xFF14121F),
    accentRed: AppColors.accentRed,
    accentBlue: AppColors.accentBlue,
    accentYellow: AppColors.accentYellow,
    accentGreen: AppColors.accentGreen,
    accentPurple: AppColors.accentPurple,
    accentOrange: AppColors.accentOrange,
    accentPink: AppColors.accentPink,
    accentTeal: AppColors.accentTeal,
  );

  /// The night palette, and the one the platform was designed in.
  static const AppPalette dark = AppPalette(
    isDark: true,
    bg: AppColors.darkBg,
    surface: AppColors.darkSurface,
    surfaceSunken: AppColors.darkSurfaceSunken,
    surfaceActive: AppColors.darkSurfaceActive,
    border: AppColors.darkBorder,
    borderStrong: AppColors.darkBorderStrong,
    text: AppColors.darkText,
    textMuted: AppColors.darkTextMuted,
    textFaint: AppColors.darkTextFaint,
    canvas: AppColors.darkCanvas,
    primary: AppColors.violetBright,
    primaryDeep: AppColors.violet,
    primaryWash: AppColors.violetShade,
    onPrimary: Color(0xFFFFFFFF),
    secondary: AppColors.coralBright,
    secondaryWash: AppColors.coralShade,
    tertiary: AppColors.aquaBright,
    tertiaryWash: AppColors.aquaShade,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    danger: AppColors.darkDanger,
    info: AppColors.darkInfo,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF05040A),
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

  /// [base] at container strength: the fill behind an icon, a badge or a
  /// status banner tinted with its own colour.
  ///
  /// A translucent tint rather than a second set of tokens, so a game colour
  /// that arrives from the server at runtime gets a container that matches it
  /// instead of one that approximately does.
  Color wash(Color base) => base.withValues(alpha: isDark ? 0.18 : 0.12);

  /// [base] at keyline strength, for the edge of a [wash]ed container.
  Color washBorder(Color base) =>
      base.withValues(alpha: isDark ? 0.34 : 0.24);

  /// The colour text and icons should be printed in on top of [base] when
  /// [base] is used as a solid fill.
  ///
  /// Uses relative luminance rather than a lookup, because game tints come
  /// from the catalogue — and, for a game this build has never heard of, from
  /// the server.
  Color onFill(Color base) => base.computeLuminance() > 0.55
      ? const Color(0xFF14121F)
      : const Color(0xFFFFFFFF);

  @override
  AppPalette copyWith({
    bool? isDark,
    Color? bg,
    Color? surface,
    Color? surfaceSunken,
    Color? surfaceActive,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? canvas,
    Color? primary,
    Color? primaryDeep,
    Color? primaryWash,
    Color? onPrimary,
    Color? secondary,
    Color? secondaryWash,
    Color? tertiary,
    Color? tertiaryWash,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? shadow,
    Color? scrim,
    Color? accentRed,
    Color? accentBlue,
    Color? accentYellow,
    Color? accentGreen,
    Color? accentPurple,
    Color? accentOrange,
    Color? accentPink,
    Color? accentTeal,
  }) {
    return AppPalette(
      isDark: isDark ?? this.isDark,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      canvas: canvas ?? this.canvas,
      primary: primary ?? this.primary,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      primaryWash: primaryWash ?? this.primaryWash,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      secondaryWash: secondaryWash ?? this.secondaryWash,
      tertiary: tertiary ?? this.tertiary,
      tertiaryWash: tertiaryWash ?? this.tertiaryWash,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      shadow: shadow ?? this.shadow,
      scrim: scrim ?? this.scrim,
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
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) {
      return this;
    }
    return AppPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceActive: Color.lerp(surfaceActive, other.surfaceActive, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t)!,
      primaryWash: Color.lerp(primaryWash, other.primaryWash, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryWash: Color.lerp(secondaryWash, other.secondaryWash, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      tertiaryWash: Color.lerp(tertiaryWash, other.tertiaryWash, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
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
    isDark,
    bg,
    surface,
    surfaceSunken,
    surfaceActive,
    border,
    borderStrong,
    text,
    textMuted,
    textFaint,
    canvas,
    primary,
    primaryDeep,
    primaryWash,
    onPrimary,
    secondary,
    secondaryWash,
    tertiary,
    tertiaryWash,
    success,
    warning,
    danger,
    info,
    shadow,
    scrim,
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
    if (other is! AppPalette) {
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

/// Sugar for reading the palette off a [BuildContext].
extension AppPaletteX on BuildContext {
  /// The active palette.
  ///
  /// Falls back to [AppPalette.light] when the extension is missing, so a
  /// widget rendered under a bare [ThemeData] still paints instead of throwing.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
