import 'package:flutter/material.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/theme/app_colors.dart';
import 'package:scribble_guess/theme/app_motion.dart';
import 'package:scribble_guess/theme/app_palette.dart';
import 'package:scribble_guess/theme/app_spacing.dart';

/// The one identity the whole product is dressed in.
///
/// ## What this is, and what it deliberately is not
///
/// It is **not** a second design system. The app already had a good one —
/// [AppColors] for pigments, [AppPalette] for roles, [AppSpacing] for rhythm,
/// [AppMotion] for timing, and a widget kit built on all four — and replacing
/// it would have meant re-testing the contrast of every screen in the product
/// to end up somewhere very similar.
///
/// What was actually missing is the thing this file is: a single named place
/// that says *what the platform is*, holds the five games' identities together
/// with it, and states the handful of rules that make the shell feel like one
/// product rather than a set of screens that happen to share a colour.
///
/// So the tokens below are the existing ones, re-exported under one roof, plus
/// the two things that had nowhere to live: the per-game accent, and the
/// component conventions.
///
/// ## The identity
///
/// Dark, by default and on purpose. This is a games platform, the five games
/// it launches are all dark rooms — a card table under a lamp, a back-room
/// bar, a ship in space — and a white lobby that drops into a black table is
/// two products. Near-black with a violet cast rather than neutral grey,
/// because grey reads as a utility and this is meant to be fun.
///
/// One strong accent — electric violet — carried by coral and aqua. Each game
/// then owns exactly one colour of its own, used only where that game is being
/// talked about.
///
/// ## What is banned, and why
///
/// The brief lists these and they are worth writing down rather than merely
/// obeying:
///
///  - **No gradient fills on surfaces.** A gradient is a light source. The
///    games have light sources; the shell does not, and a lobby whose cards
///    are lit from nowhere looks like a template.
///  - **No glass.** Blur is expensive on a mid-range phone, and a list of
///    five cards that each blur what is behind them is a scroll that drops
///    frames for decoration.
///  - **No large shadows.** Depth here comes from one hairline border and a
///    surface one step lighter than its background. That reads as clean on
///    dark, where a drop shadow reads as a smudge.
///  - **No neon.** The accents are saturated, not luminous. Glow belongs to
///    the games, where there is a reason for it.
abstract final class PlatformDesignSystem {
  // ------------------------------------------------------------- identity --

  /// The default brightness of the whole product.
  ///
  /// Dark. See the class comment: the shell and the five tables have to be the
  /// same place. A player who prefers light can still choose it in settings —
  /// this is the default, not a lock.
  static const ThemeMode defaultMode = ThemeMode.dark;

  /// The platform's own colour. Every primary action in the shell wears it.
  static const Color brand = AppColors.violet;

  /// The second voice: live badges, streaks, anything that means "now".
  static const Color pulse = AppColors.coral;

  /// The third: quiet confirmations and informational chips.
  static const Color calm = AppColors.aqua;

  // ------------------------------------------------------- game identities --

  /// The one colour each game owns.
  ///
  /// Read from the catalogue rather than restated here, so a game's colour is
  /// defined once — beside its name, its description and its player limits —
  /// and a card, a glyph and a lobby header cannot disagree about it.
  ///
  /// This is the *shell's* view of a game. Inside a game, [GameSkin] takes
  /// over completely: the accent below is how Bluff Bar is referred to in a
  /// list, and it has nothing to do with the amber bulb over its table.
  static Color accentOf(GameId gameId) => GameCatalog.byId(gameId).color;

  // ------------------------------------------------------------ components --

  /// The radius of a card, a sheet or a dialog.
  static const double cardRadius = AppSpacing.radiusLg;

  /// The radius of a control: a button, a field, a chip.
  static const double controlRadius = AppSpacing.radiusMd;

  /// Anything round and pill-shaped: badges, tabs, filter chips.
  static const double pillRadius = AppSpacing.radiusPill;

  /// The one border weight in the shell.
  ///
  /// One, not three. A system with hairline, border and thick borders spends
  /// its reviewer's attention on which is which; a system with one spends it
  /// on whether a border belongs there at all.
  static const double edge = AppSpacing.border;

  /// Press feedback is `PressableScale`, in `core/widgets/app_button.dart`.
  ///
  /// Named here rather than reimplemented. Every tappable surface in the shell
  /// already sinks slightly when held — `AppButton` and `AppCard` both route
  /// through it — so a second implementation would have been a second feel to
  /// keep in step, which is the opposite of what a design system is for.
  ///
  /// Wrap anything else that should feel tappable in `PressableScale`.
  static const Duration pressDuration = AppMotion.fast;

  /// The tallest a content column grows before it stops.
  ///
  /// A games list that ran the full width of a tablet would put the Play
  /// button a hand's width from the game it belongs to.
  static const double maxContentWidth = 560;

  // ----------------------------------------------------------- conventions --

  /// The surface a card sits on, given the palette in force.
  ///
  /// A method rather than a constant because the shell supports both
  /// brightnesses and a card is "one step lighter than its background" in
  /// dark and "one step darker" in light — the same rule, two answers.
  static Color cardSurface(AppPalette palette) => palette.surface;

  /// The tint a game's own colour gets when it fills a surface.
  ///
  /// Never the raw accent: a card headed in full-strength violet is a card
  /// nothing can be read on. [AppPalette.wash] already does this correctly for
  /// both brightnesses, and this names it so the rule is findable.
  static Color washOf(AppPalette palette, Color accent) => palette.wash(accent);
}
