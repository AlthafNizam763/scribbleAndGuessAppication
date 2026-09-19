import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scribble_guess/theme/app_colors.dart';
import 'package:scribble_guess/theme/app_palette.dart';
import 'package:scribble_guess/theme/app_spacing.dart';
import 'package:scribble_guess/theme/app_typography.dart';

/// The two [ThemeData] objects the app runs on.
///
/// Both are Material 3, but every component theme is wired from the explicit
/// [AppPalette] rather than from a generated seed, so the pigments never
/// drift. Material's surface tint is switched off everywhere: a violet primary
/// bleeding into every raised surface is exactly the generic-Flutter look this
/// design exists to avoid. Depth is a surface step and a hairline instead.
abstract final class AppTheme {
  /// Cool off-white, near-black violet-cast ink.
  static ThemeData get light =>
      _build(scheme: _lightScheme, palette: AppPalette.light);

  /// The house style: a near-black violet-tinted page.
  static ThemeData get dark =>
      _build(scheme: _darkScheme, palette: AppPalette.dark);

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
  static const BorderRadius _radiusXl = BorderRadius.all(
    Radius.circular(AppSpacing.radiusXl),
  );

  /// A flat, hairline-outlined shape: no shadow, just a keyline.
  static RoundedRectangleBorder _outlined(
    Color color,
    BorderRadius radius, {
    double width = AppSpacing.hairline,
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
    primary: AppColors.violet,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: AppColors.violetWash,
    onPrimaryContainer: Color(0xFF2A1A78),
    secondary: AppColors.coral,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: AppColors.coralWash,
    onSecondaryContainer: Color(0xFF6B0E2C),
    tertiary: AppColors.aqua,
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: AppColors.aquaWash,
    onTertiaryContainer: Color(0xFF00413C),
    error: AppColors.danger,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFDE4E1),
    onErrorContainer: Color(0xFF6B1711),
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceDim: AppColors.surfaceActive,
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: AppColors.bg,
    surfaceContainer: AppColors.surfaceSunken,
    surfaceContainerHigh: AppColors.surfaceActive,
    surfaceContainerHighest: Color(0xFFD9D7E8),
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
    shadow: AppColors.text,
    scrim: AppColors.text,
    inverseSurface: AppColors.text,
    onInverseSurface: Color(0xFFF4F3FB),
    inversePrimary: AppColors.violetBright,
    surfaceTint: Color(0x00000000),
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.violetBright,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: AppColors.violetShade,
    onPrimaryContainer: Color(0xFFD9CFFF),
    secondary: AppColors.coralBright,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: AppColors.coralShade,
    onSecondaryContainer: Color(0xFFFFD2DF),
    tertiary: AppColors.aquaBright,
    onTertiary: Color(0xFF00302C),
    tertiaryContainer: AppColors.aquaShade,
    onTertiaryContainer: Color(0xFFAFF3EC),
    error: AppColors.darkDanger,
    onError: Color(0xFF45100B),
    errorContainer: Color(0xFF4A1A15),
    onErrorContainer: Color(0xFFFFD6D1),
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkText,
    surfaceDim: AppColors.darkBg,
    surfaceBright: AppColors.darkSurfaceActive,
    surfaceContainerLowest: Color(0xFF07060D),
    surfaceContainerLow: AppColors.darkSurfaceSunken,
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: AppColors.darkSurfaceActive,
    surfaceContainerHighest: Color(0xFF2C2A42),
    onSurfaceVariant: AppColors.darkTextMuted,
    outline: AppColors.darkBorderStrong,
    outlineVariant: AppColors.darkBorder,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: AppColors.darkText,
    onInverseSurface: AppColors.text,
    inversePrimary: AppColors.violet,
    surfaceTint: Color(0x00000000),
  );

  // ---------------------------------------------------------------- build ---

  static ThemeData _build({
    required ColorScheme scheme,
    required AppPalette palette,
  }) {
    final TextTheme text = AppTypography.textTheme(scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[palette],
      fontFamily: AppTypography.bodyFamily,
      textTheme: text,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      dividerColor: palette.border,
      shadowColor: palette.shadow,
      // Material's ink ripple fights a design built on scale-on-press: the
      // splash lands a frame after the shrink and reads as a second, slower
      // reaction to the same tap. Every interactive surface in the kit gives
      // its own feedback instead.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: palette.surfaceActive.withValues(alpha: 0.5),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: _appBarTheme(palette, text),
      badgeTheme: _badgeTheme(palette, text),
      bottomSheetTheme: _bottomSheetTheme(palette),
      cardTheme: _cardTheme(palette),
      checkboxTheme: _checkboxTheme(palette),
      chipTheme: _chipTheme(palette, text),
      dialogTheme: _dialogTheme(palette, text),
      dividerTheme: _dividerTheme(palette),
      iconTheme: _iconTheme(palette),
      inputDecorationTheme: _inputDecorationTheme(palette, text),
      listTileTheme: _listTileTheme(palette, text),
      navigationBarTheme: _navigationBarTheme(palette, text),
      progressIndicatorTheme: _progressIndicatorTheme(palette),
      radioTheme: _radioTheme(palette),
      sliderTheme: _sliderTheme(palette, text),
      snackBarTheme: _snackBarTheme(palette, text),
      switchTheme: _switchTheme(palette),
      tabBarTheme: _tabBarTheme(palette, text),
      textButtonTheme: _textButtonTheme(palette, text),
      textSelectionTheme: _textSelectionTheme(palette),
      tooltipTheme: _tooltipTheme(palette, text),
    );
  }

  // ----------------------------------------------------------- components ---

  static AppBarThemeData _appBarTheme(AppPalette palette, TextTheme text) {
    return AppBarThemeData(
      backgroundColor: palette.bg,
      foregroundColor: palette.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      toolbarHeight: 64,
      titleSpacing: AppSpacing.xs,
      titleTextStyle: text.titleLarge,
      toolbarTextStyle: text.bodyMedium,
      iconTheme: IconThemeData(color: palette.text, size: 22),
      actionsIconTheme: IconThemeData(color: palette.text, size: 22),
      systemOverlayStyle: palette.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    );
  }

  static BadgeThemeData _badgeTheme(AppPalette palette, TextTheme text) {
    return BadgeThemeData(
      backgroundColor: palette.secondary,
      textColor: Colors.white,
      textStyle: text.labelSmall?.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 5),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(AppPalette palette) {
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
      side: BorderSide(color: palette.border, width: AppSpacing.hairline),
    );
    return BottomSheetThemeData(
      backgroundColor: palette.surface,
      modalBackgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: palette.scrim.withValues(alpha: 0.6),
      shape: shape,
      showDragHandle: true,
      dragHandleColor: palette.borderStrong,
      dragHandleSize: const Size(40, 4),
    );
  }

  static CardThemeData _cardTheme(AppPalette palette) {
    return CardThemeData(
      color: palette.surface,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: _outlined(palette.border, _radiusLg),
    );
  }

  static CheckboxThemeData _checkboxTheme(AppPalette palette) {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? palette.primary
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll<Color>(palette.onPrimary),
      side: BorderSide(color: palette.borderStrong, width: AppSpacing.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
      splashRadius: 0,
    );
  }

  static ChipThemeData _chipTheme(AppPalette palette, TextTheme text) {
    return ChipThemeData(
      backgroundColor: palette.surfaceSunken,
      selectedColor: palette.primary,
      disabledColor: palette.surfaceSunken,
      surfaceTintColor: Colors.transparent,
      checkmarkColor: palette.onPrimary,
      labelStyle: text.labelMedium,
      secondaryLabelStyle: text.labelMedium?.copyWith(color: palette.onPrimary),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      side: BorderSide(color: palette.border, width: AppSpacing.hairline),
      shape: const RoundedRectangleBorder(borderRadius: _radiusSm),
      elevation: 0,
      pressElevation: 0,
      showCheckmark: false,
    );
  }

  static DialogThemeData _dialogTheme(AppPalette palette, TextTheme text) {
    return DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: palette.shadow,
      elevation: 0,
      iconColor: palette.primary,
      barrierColor: palette.scrim.withValues(alpha: 0.6),
      shape: _outlined(palette.border, _radiusXl),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium?.copyWith(color: palette.textMuted),
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
    );
  }

  static DividerThemeData _dividerTheme(AppPalette palette) {
    return DividerThemeData(
      color: palette.border,
      thickness: AppSpacing.hairline,
      space: AppSpacing.lg,
    );
  }

  static IconThemeData _iconTheme(AppPalette palette) {
    return IconThemeData(color: palette.text, size: 22);
  }

  static InputDecorationThemeData _inputDecorationTheme(
    AppPalette palette,
    TextTheme text,
  ) {
    return InputDecorationThemeData(
      filled: true,
      fillColor: palette.surfaceSunken,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      hintStyle: text.bodyMedium?.copyWith(color: palette.textFaint),
      labelStyle: text.bodyMedium?.copyWith(color: palette.textMuted),
      floatingLabelStyle: text.labelMedium?.copyWith(color: palette.primary),
      helperStyle: text.bodySmall?.copyWith(color: palette.textMuted),
      errorStyle: text.bodySmall?.copyWith(color: palette.danger),
      counterStyle: text.labelSmall?.copyWith(color: palette.textFaint),
      prefixIconColor: palette.textMuted,
      suffixIconColor: palette.textMuted,
      iconColor: palette.textMuted,
      border: _inputBorder(Colors.transparent, width: 0),
      enabledBorder: _inputBorder(palette.border, width: AppSpacing.hairline),
      focusedBorder: _inputBorder(palette.primary, width: AppSpacing.borderThick),
      disabledBorder: _inputBorder(palette.border, width: AppSpacing.hairline),
      errorBorder: _inputBorder(palette.danger),
      focusedErrorBorder: _inputBorder(
        palette.danger,
        width: AppSpacing.borderThick,
      ),
    );
  }

  static ListTileThemeData _listTileTheme(AppPalette palette, TextTheme text) {
    return ListTileThemeData(
      iconColor: palette.textMuted,
      textColor: palette.text,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall?.copyWith(color: palette.textMuted),
      shape: const RoundedRectangleBorder(borderRadius: _radiusMd),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      minVerticalPadding: AppSpacing.sm,
    );
  }

  static NavigationBarThemeData _navigationBarTheme(
    AppPalette palette,
    TextTheme text,
  ) {
    return NavigationBarThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      indicatorColor: palette.primaryWash,
      indicatorShape: const RoundedRectangleBorder(borderRadius: _radiusSm),
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? text.labelSmall?.copyWith(color: palette.primary)
            : text.labelSmall?.copyWith(color: palette.textFaint),
      ),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? palette.primary
              : palette.textFaint,
        ),
      ),
    );
  }

  static ProgressIndicatorThemeData _progressIndicatorTheme(
    AppPalette palette,
  ) {
    return ProgressIndicatorThemeData(
      color: palette.primary,
      linearTrackColor: palette.surfaceActive,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 8,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
    );
  }

  static RadioThemeData _radioTheme(AppPalette palette) {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? palette.primary
            : palette.borderStrong,
      ),
      splashRadius: 0,
    );
  }

  static SliderThemeData _sliderTheme(AppPalette palette, TextTheme text) {
    return SliderThemeData(
      trackHeight: 6,
      trackShape: const RoundedRectSliderTrackShape(),
      activeTrackColor: palette.primary,
      inactiveTrackColor: palette.surfaceActive,
      disabledActiveTrackColor: palette.textFaint,
      disabledInactiveTrackColor: palette.surfaceSunken,
      thumbColor: palette.primary,
      disabledThumbColor: palette.textFaint,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 10,
        elevation: 0,
        pressedElevation: 0,
      ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      overlayColor: palette.primary.withValues(alpha: 0.12),
      valueIndicatorShape: const RectangularSliderValueIndicatorShape(),
      valueIndicatorColor: palette.primary,
      valueIndicatorTextStyle: text.labelMedium?.copyWith(
        color: palette.onPrimary,
      ),
      showValueIndicator: ShowValueIndicator.onDrag,
    );
  }

  static SnackBarThemeData _snackBarTheme(AppPalette palette, TextTheme text) {
    // Always the dark chip, in both themes. A toast is a notification, not a
    // surface, and one that changes colour with the theme reads as part of the
    // page it is floating over.
    const Color chip = Color(0xFF1C1A2B);
    return SnackBarThemeData(
      backgroundColor: chip,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: const Color(0xFFF4F3FB),
        fontWeight: AppTypography.medium,
      ),
      actionTextColor: AppColors.violetBright,
      closeIconColor: const Color(0xFFA5A1C2),
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: _outlined(
        const Color(0xFF34314D),
        BorderRadius.circular(AppSpacing.radiusMd),
      ),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
    );
  }

  static SwitchThemeData _switchTheme(AppPalette palette) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? Colors.white
            : palette.textFaint,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? palette.primary
            : palette.surfaceActive,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : palette.border,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll<double>(
        AppSpacing.hairline,
      ),
      overlayColor: WidgetStatePropertyAll<Color>(
        palette.primary.withValues(alpha: 0.10),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  static TabBarThemeData _tabBarTheme(AppPalette palette, TextTheme text) {
    return TabBarThemeData(
      labelColor: palette.text,
      unselectedLabelColor: palette.textFaint,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(
        fontWeight: AppTypography.semibold,
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: palette.border, width: AppSpacing.hairline),
      ),
      dividerColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    );
  }

  static TextButtonThemeData _textButtonTheme(
    AppPalette palette,
    TextTheme text,
  ) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.primary,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        minimumSize: const Size(0, AppSpacing.minTapTarget),
        shape: const RoundedRectangleBorder(borderRadius: _radiusSm),
      ),
    );
  }

  static TextSelectionThemeData _textSelectionTheme(AppPalette palette) {
    return TextSelectionThemeData(
      cursorColor: palette.primary,
      selectionColor: palette.primary.withValues(alpha: 0.28),
      selectionHandleColor: palette.primary,
    );
  }

  static TooltipThemeData _tooltipTheme(AppPalette palette, TextTheme text) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1A2B),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      ),
      textStyle: text.labelMedium?.copyWith(color: const Color(0xFFF4F3FB)),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      waitDuration: const Duration(milliseconds: 400),
    );
  }
}
