import 'package:flutter/painting.dart';

/// The depth tokens: the only shadows the app is allowed to cast.
///
/// Deliberately restrained. Big soft drop shadows are the fastest way to make
/// a mobile UI look cheap, and on a near-black surface they are invisible
/// anyway — so depth at night comes from the surface step and the hairline,
/// and these shadows exist mostly for the light theme.
///
/// [lifted] is the card. [raised] is a sheet or a menu that sits above the
/// page. [pressed] is nothing at all, which is the point: a pressed control
/// drops to the surface rather than growing a bigger shadow.
abstract final class AppElevation {
  /// No shadow. The default for anything sitting flat on the page.
  static const List<BoxShadow> none = <BoxShadow>[];

  /// A card resting on the page.
  static List<BoxShadow> lifted(Color shadow) => <BoxShadow>[
    BoxShadow(
      color: shadow.withValues(alpha: 0.05),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  /// A sheet, menu or floating bar above the page.
  static List<BoxShadow> raised(Color shadow) => <BoxShadow>[
    BoxShadow(
      color: shadow.withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: shadow.withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  /// The one coloured shadow in the system: a primary action, tinted with its
  /// own fill so it reads as energy rather than as weight.
  ///
  /// Reserved for the single most important button on a screen. Anywhere else
  /// it stops meaning anything.
  static List<BoxShadow> glow(Color tint) => <BoxShadow>[
    BoxShadow(
      color: tint.withValues(alpha: 0.32),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
}
