import 'package:flutter/widgets.dart';

/// The three layout classes the app is designed for.
enum ScreenSize {
  /// Phones and narrow windows, below 600 logical pixels.
  compact,

  /// Large phones, small tablets and split-screen windows, 600 to 1023.
  medium,

  /// Tablets and desktop windows, 1024 and wider.
  expanded,
}

/// Width thresholds separating the [ScreenSize] classes.
abstract final class Breakpoints {
  /// Widths below this are [ScreenSize.compact].
  static const double compact = 600;

  /// Widths at or above this are [ScreenSize.expanded].
  static const double expanded = 1024;

  /// Widest the page content ever grows, centered on large windows.
  static const double maxContentWidth = 1100;

  /// Classifies a raw width in logical pixels.
  static ScreenSize fromWidth(double width) {
    if (width >= expanded) {
      return ScreenSize.expanded;
    }
    if (width >= compact) {
      return ScreenSize.medium;
    }
    return ScreenSize.compact;
  }
}

/// Classifies the window [context] is laid out in.
///
/// Uses `MediaQuery.sizeOf`, so a widget calling this only rebuilds when the
/// size actually changes.
ScreenSize screenSizeOf(BuildContext context) =>
    Breakpoints.fromWidth(MediaQuery.sizeOf(context).width);

/// Shorthands for reading the current layout class from a [BuildContext].
extension ResponsiveX on BuildContext {
  /// The layout class of the current window.
  ScreenSize get screenSize => screenSizeOf(this);

  /// Whether the window is narrower than 600 logical pixels.
  bool get isCompact => screenSize == ScreenSize.compact;

  /// Whether the window is between 600 and 1023 logical pixels wide.
  bool get isMedium => screenSize == ScreenSize.medium;

  /// Whether the window is 1024 logical pixels wide or more.
  bool get isExpanded => screenSize == ScreenSize.expanded;

  /// Shortest edge of the window, handy for orientation-agnostic sizing.
  double get shortestSide => MediaQuery.sizeOf(this).shortestSide;
}
