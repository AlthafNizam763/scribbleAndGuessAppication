import 'package:flutter/material.dart';
import 'package:scribble_guess/theme/app_colors.dart';
import 'package:scribble_guess/theme/app_spacing.dart';
import 'package:scribble_guess/theme/app_text_styles.dart';
import 'package:scribble_guess/theme/sketch_colors.dart';

/// The two [ThemeData] objects the app runs on.
///
/// Both are Material 3 but deliberately un-Material: no elevation, no surface
/// tint, no splash, no blur. Everything is flat ink on paper, and every
/// component theme is wired from the explicit [SketchColors] palettes rather
/// than from a generated seed, so the pigments never drift.
abstract final class AppTheme {
  /// Warm paper, brown-black ink.
  static ThemeData get light =>
      _build(scheme: _lightScheme, colors: SketchColors.light);

  /// The night desk: soft chalk on deep warm charcoal.
  static ThemeData get dark =>
      _build(scheme: _darkScheme, colors: SketchColors.dark);

  // --------------------------------------------------------------- shapes ---

  static const BorderRadius _radiusSm = BorderRadius.all(
    Radius.circular(AppSpacing.radiusSm),
  );
  static const BorderRadius _radiusMd = BorderRadius.all(
    Radius.circular(AppSpacing.radiusMd),
  );
  static const BorderRadius _radiusLg = BorderRadius.all(
    Radius.circular(AppSpacing.radiusLg),
  );

  /// A flat outlined shape: no shadow, just an ink keyline.
  static RoundedRectangleBorder _outlined(
    Color color,
    BorderRadius radius, {
    double width = AppSpacing.border,
  }) {
    return RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(color: color, width: width),
    );
  }

  static OutlineInputBorder _inputBorder(
    Color color, {
    double width = AppSpacing.border,
  }) {
    return OutlineInputBorder(
      borderRadius: _radiusMd,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  // -------------------------------------------------------------- schemes ---

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.ink,
    onPrimary: AppColors.paper,
    primaryContainer: Color(0xFFF2E4B8),
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.accentBlue,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDCE8F1),
    onSecondaryContainer: Color(0xFF16354B),
    tertiary: AppColors.accentPink,
    onTertiary: Color(0xFF38121F),
    tertiaryContainer: Color(0xFFF7DCE7),
    onTertiaryContainer: Color(0xFF4A1A2B),
    error: AppColors.danger,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF6DAD7),
    onErrorContainer: Color(0xFF5A1A15),
    surface: AppColors.paper,
    onSurface: AppColors.ink,
    surfaceDim: AppColors.paperShade,
    surfaceBright: AppColors.canvasWhite,
    surfaceContainerLowest: AppColors.canvasWhite,
    surfaceContainerLow: AppColors.paper,
    surfaceContainer: AppColors.paperDim,
    surfaceContainerHigh: AppColors.paperShade,
    surfaceContainerHighest: Color(0xFFDED2BB),
    onSurfaceVariant: AppColors.inkSoft,
    outline: AppColors.ink,
    outlineVariant: AppColors.inkFaint,
    shadow: AppColors.ink,
    scrim: AppColors.ink,
    inverseSurface: Color(0xFF2F2A25),
    onInverseSurface: Color(0xFFF6F1E7),
    inversePrimary: AppColors.accentYellow,
    surfaceTint: Color(0x00000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.darkInk,
    onPrimary: AppColors.darkPaper,
    primaryContainer: Color(0xFF3A3229),
    onPrimaryContainer: Color(0xFFF0DFB4),
    secondary: AppColors.darkAccentBlue,
    onSecondary: Color(0xFF0E2434),
    secondaryContainer: Color(0xFF24384A),
    onSecondaryContainer: Color(0xFFC6DDEE),
    tertiary: AppColors.darkAccentPink,
    onTertiary: Color(0xFF3A1524),
    tertiaryContainer: Color(0xFF4E2434),
    onTertiaryContainer: Color(0xFFF7D6E3),
    error: AppColors.darkDanger,
    onError: Color(0xFF3A100C),
    errorContainer: Color(0xFF5A211C),
    onErrorContainer: Color(0xFFF7D6D2),
    surface: AppColors.darkPaper,
    onSurface: AppColors.darkInk,
    surfaceDim: Color(0xFF141210),
    surfaceBright: Color(0xFF3A342C),
    surfaceContainerLowest: Color(0xFF131110),
    surfaceContainerLow: AppColors.darkPaperDim,
    surfaceContainer: Color(0xFF232019),
    surfaceContainerHigh: AppColors.darkPaperShade,
    surfaceContainerHighest: Color(0xFF383229),
    onSurfaceVariant: AppColors.darkInkSoft,
    outline: AppColors.darkInk,
    outlineVariant: AppColors.darkInkFaint,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: AppColors.darkInk,
    onInverseSurface: AppColors.ink,
    inversePrimary: AppColors.accentBlue,
    surfaceTint: Color(0x00000000),
  );

  // ---------------------------------------------------------------- build ---

  static ThemeData _build({
    required ColorScheme scheme,
    required SketchColors colors,
  }) {
    final TextTheme text = AppTypography.textTheme(scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[colors],
      fontFamily: AppTypography.bodyFamily,
      textTheme: text,
      scaffoldBackgroundColor: colors.paper,
      canvasColor: colors.paper,
      dividerColor: colors.inkFaint,
      shadowColor: colors.ink,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: _appBarTheme(colors, text),
      bottomSheetTheme: _bottomSheetTheme(colors),
      cardTheme: _cardTheme(colors),
      dialogTheme: _dialogTheme(colors, text),
      dividerTheme: _dividerTheme(colors),
      iconTheme: _iconTheme(colors),
      inputDecorationTheme: _inputDecorationTheme(colors, text),
      progressIndicatorTheme: _progressIndicatorTheme(colors),
      sliderTheme: _sliderTheme(colors, text),
      snackBarTheme: _snackBarTheme(colors, text),
      switchTheme: _switchTheme(colors),
      textSelectionTheme: _textSelectionTheme(colors),
      tooltipTheme: _tooltipTheme(colors, text),
    );
  }

  // ----------------------------------------------------------- components ---

  static AppBarThemeData _appBarTheme(SketchColors colors, TextTheme text) {
    return AppBarThemeData(
      backgroundColor: colors.paper,
      foregroundColor: colors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      toolbarHeight: 60,
      titleSpacing: AppSpacing.sm,
      titleTextStyle: text.titleLarge,
      toolbarTextStyle: text.bodyMedium,
      iconTheme: IconThemeData(color: colors.ink, size: 24),
      actionsIconTheme: IconThemeData(color: colors.ink, size: 24),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(SketchColors colors) {
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
      side: BorderSide(color: colors.ink, width: AppSpacing.border),
    );
    return BottomSheetThemeData(
      backgroundColor: colors.paper,
      modalBackgroundColor: colors.paper,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: colors.ink.withValues(alpha: 0.45),
      shape: shape,
      showDragHandle: true,
      dragHandleColor: colors.inkFaint,
      dragHandleSize: const Size(44, 4),
    );
  }

  static CardThemeData _cardTheme(SketchColors colors) {
    return CardThemeData(
      color: colors.paper,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.none,
      shape: _outlined(colors.ink, _radiusMd),
    );
  }

  static DialogThemeData _dialogTheme(SketchColors colors, TextTheme text) {
    return DialogThemeData(
      backgroundColor: colors.paper,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      iconColor: colors.ink,
      barrierColor: colors.ink.withValues(alpha: 0.45),
      shape: _outlined(colors.ink, _radiusLg),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium?.copyWith(color: colors.inkSoft),
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
    );
  }

  static DividerThemeData _dividerTheme(SketchColors colors) {
    return DividerThemeData(
      color: colors.inkFaint,
      thickness: 1.5,
      space: AppSpacing.lg,
    );
  }

  static IconThemeData _iconTheme(SketchColors colors) {
    return IconThemeData(color: colors.ink, size: 22);
  }

  static InputDecorationThemeData _inputDecorationTheme(
    SketchColors colors,
    TextTheme text,
  ) {
    return InputDecorationThemeData(
      filled: true,
      fillColor: colors.paperDim,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      hintStyle: text.bodyMedium?.copyWith(color: colors.inkFaint),
      labelStyle: text.bodyMedium?.copyWith(color: colors.inkSoft),
      floatingLabelStyle: text.labelMedium?.copyWith(color: colors.ink),
      helperStyle: text.bodySmall?.copyWith(color: colors.inkSoft),
      errorStyle: text.bodySmall?.copyWith(color: colors.danger),
      counterStyle: text.labelSmall?.copyWith(color: colors.inkSoft),
      prefixIconColor: colors.inkSoft,
      suffixIconColor: colors.inkSoft,
      iconColor: colors.inkSoft,
      border: _inputBorder(colors.ink),
      enabledBorder: _inputBorder(colors.ink),
      focusedBorder: _inputBorder(colors.accentBlue, width: 3),
      disabledBorder: _inputBorder(colors.inkFaint),
      errorBorder: _inputBorder(colors.danger),
      focusedErrorBorder: _inputBorder(colors.danger, width: 3),
    );
  }

  static ProgressIndicatorThemeData _progressIndicatorTheme(
    SketchColors colors,
  ) {
    return ProgressIndicatorThemeData(
      color: colors.ink,
      linearTrackColor: colors.paperShade,
      circularTrackColor: colors.paperShade,
      linearMinHeight: 10,
      borderRadius: _radiusSm,
    );
  }

  static SliderThemeData _sliderTheme(SketchColors colors, TextTheme text) {
    return SliderThemeData(
      trackHeight: 8,
      trackShape: const RoundedRectSliderTrackShape(),
      activeTrackColor: colors.ink,
      inactiveTrackColor: colors.paperShade,
      disabledActiveTrackColor: colors.inkFaint,
      disabledInactiveTrackColor: colors.paperShade,
      thumbColor: colors.accentYellow,
      disabledThumbColor: colors.inkFaint,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 11,
        elevation: 0,
        pressedElevation: 0,
      ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
      overlayColor: colors.ink.withValues(alpha: 0.08),
      valueIndicatorShape: const RectangularSliderValueIndicatorShape(),
      valueIndicatorColor: colors.ink,
      valueIndicatorTextStyle: text.labelMedium?.copyWith(color: colors.paper),
      showValueIndicator: ShowValueIndicator.onDrag,
    );
  }

  static SnackBarThemeData _snackBarTheme(SketchColors colors, TextTheme text) {
    return SnackBarThemeData(
      backgroundColor: colors.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: colors.paper),
      actionTextColor: colors.accentYellow,
      closeIconColor: colors.paper,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: _outlined(colors.paper, _radiusMd),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
    );
  }

  static SwitchThemeData _switchTheme(SketchColors colors) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? colors.paper
            : colors.inkSoft,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? colors.accentGreen
            : colors.paperShade,
      ),
      trackOutlineColor: WidgetStatePropertyAll<Color>(colors.ink),
      trackOutlineWidth: const WidgetStatePropertyAll<double>(
        AppSpacing.border,
      ),
      overlayColor: WidgetStatePropertyAll<Color>(
        colors.ink.withValues(alpha: 0.06),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  static TextSelectionThemeData _textSelectionTheme(SketchColors colors) {
    return TextSelectionThemeData(
      cursorColor: colors.ink,
      selectionColor: colors.accentYellow.withValues(alpha: 0.35),
      selectionHandleColor: colors.accentBlue,
    );
  }

  static TooltipThemeData _tooltipTheme(SketchColors colors, TextTheme text) {
    return TooltipThemeData(
      decoration: BoxDecoration(color: colors.ink, borderRadius: _radiusSm),
      textStyle: text.labelMedium?.copyWith(color: colors.paper),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      waitDuration: const Duration(milliseconds: 400),
    );
  }
}
