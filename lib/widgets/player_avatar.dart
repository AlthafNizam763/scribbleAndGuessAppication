import 'package:flutter/material.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/avatar_art.dart';
import 'package:scribble_guess/widgets/avatar_painter.dart';

/// A player's face: one of [AppConstants.avatarCount] characters — a person,
/// an animal or an anime doodler — on one of [AppConstants.avatarColorCount]
/// accent discs.
///
/// Characters are drawn by [AvatarArtPainter] rather than shipped as images,
/// so the app stays asset-light, a face costs nothing to add, and no avatar
/// has to be downloaded before a room can start. The disc and its ring follow
/// the theme; the character itself is painted in fixed pigments, the way the
/// drawing canvas stays light at night.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    required this.avatarId,
    required this.colorIndex,
    this.size = 44,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
    super.key,
  });

  /// Reads the look straight off a room [Player].
  PlayerAvatar.ofPlayer(
    Player player, {
    this.size = 44,
    this.selected = false,
    this.onTap,
    super.key,
  })  : avatarId = player.avatarId,
        colorIndex = player.avatarColorIndex,
        dimmed = !player.isConnected;

  /// Reads the look straight off the local [PlayerProfile].
  PlayerAvatar.ofProfile(
    PlayerProfile profile, {
    this.size = 44,
    this.selected = false,
    this.onTap,
    super.key,
  })  : avatarId = profile.avatarId,
        colorIndex = profile.avatarColorIndex,
        dimmed = false;

  final int avatarId;
  final int colorIndex;
  final double size;

  /// Draws a heavier ring, for the avatar picker.
  final bool selected;

  /// Fades the face, for players who have dropped off the connection.
  final bool dimmed;

  final VoidCallback? onTap;

  /// The disc an avatar of [colorIndex] sits on.
  ///
  /// A wash of the accent rather than the full pigment: the colour stays the
  /// player's badge, and the character on top of it stays the thing you
  /// actually read. Exposed so the profile screen's colour swatches can show
  /// the disc a player is really choosing.
  static Color discColor(SketchColors colors, int colorIndex) =>
      Color.lerp(colors.accentAt(colorIndex), colors.canvasWhite, 0.38)!;

  /// Outline weight for an avatar drawn at [size].
  ///
  /// The drawing scales with the disc, so at row size its outlines would thin
  /// away to nothing. Small avatars are traced heavier to hold together.
  static double lineWeightFor(double size) {
    if (size <= 32) {
      return 1.45;
    }
    if (size <= 52) {
      return 1.15;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final AvatarFace face = AvatarCatalog.faceAt(avatarId);
    final double ring = selected ? AppSpacing.border + 1 : AppSpacing.border;
    final String label = '${context.l10n.a11yAvatar}: ${face.name}';

    final Widget avatar = Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipOval(
              child: ColoredBox(
                color: discColor(colors, colorIndex),
                child: CustomPaint(
                  painter: AvatarArtPainter(
                    face: face,
                    weight: lineWeightFor(size),
                  ),
                ),
              ),
            ),
            // The ring goes last so the drawing runs under it, edge to edge,
            // instead of stopping short of it.
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.ink, width: ring),
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return Semantics(label: label, image: true, child: avatar);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: avatar,
      ),
    );
  }
}
