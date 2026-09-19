import 'package:flutter/material.dart';

/// The ten cats, as drawing instructions.
///
/// Kept separate from the numeric id because the two mean different things: an
/// id is persisted with the profile and broadcast to every other player, so it
/// must never be reordered, while a shape is only ever a drawing instruction
/// and is free to change with the art.
enum AvatarShape {
  /// Eyes shut, one ear folded, snoring.
  sleeping,

  /// Squeezed-shut eyes and a wide open laugh. The house style.
  laughing,

  /// Flattened ears, slanted brows, a small furious frown.
  angry,

  /// One brow up, head tilted, mouth off to one side.
  confused,

  /// Enormous round eyes and a tiny O of a mouth.
  shocked,

  /// Eyes closed in bliss, head tilted, one paw raised mid-move.
  dancing,

  /// Half-lidded eyes and a yawn.
  lazy,

  /// Narrowed eyes and a one-sided smirk.
  smug,

  /// Wide eyes, pinned-back ears, a wobbling frown.
  scared,

  /// Mismatched eyes, a manic grin, fur sticking out.
  chaotic,
}

/// The pigments characters are drawn with.
///
/// Deliberately brightness independent, the same way `AppColors.drawingPalette`
/// is: an avatar is a sticker stuck onto the page, and a sticker does not
/// repaint itself at night. Only the disc behind it and its ring follow the
/// theme, which is what keeps the avatar sitting in the page rather than on it.
abstract final class AvatarPigments {
  /// Every outline on a character.
  static const Color line = Color(0xFF33302B);

  /// Eye whites, teeth and highlights.
  static const Color light = Color(0xFFFFFBF3);

  /// Warm cheeks, always laid down translucent.
  static const Color blush = Color(0xFFE07A72);

  /// Noses, inner ears and tongues.
  static const Color petal = Color(0xFFE58B92);

  /// The inside of an open mouth.
  static const Color maw = Color(0xFF7E3B44);

  // ------------------------------------------------------------------ fur ---

  /// Ginger coat — the brand cat's own.
  static const Color furGinger = Color(0xFFE9A055);

  /// Cocoa coat.
  static const Color furCocoa = Color(0xFF9E6F4A);

  /// Grey coat.
  static const Color furAsh = Color(0xFFC5BCAF);

  /// Cream coat.
  static const Color furCream = Color(0xFFF7EBDB);

  /// Sooty coat.
  ///
  /// Lifted well off the outline colour on purpose: a coat any darker
  /// swallows the eyes and whiskers drawn on top of it, and the cat reads as a
  /// silhouette rather than as a face.
  static const Color furSoot = Color(0xFF8C8073);

  /// Rust coat.
  static const Color furRust = Color(0xFFDB7440);

  /// Slate-blue coat.
  static const Color furSlate = Color(0xFF8FA3B5);

  /// Toffee coat.
  static const Color furToffee = Color(0xFFD9B06A);

  /// Mint coat, for the one that is clearly not a normal cat.
  static const Color furMint = Color(0xFF8FC7AE);

  /// Lilac coat.
  static const Color furLilac = Color(0xFFB9A2CC);

  // ---------------------------------------------------------------- cloth ---

  /// Denim shoulders.
  static const Color clothDenim = Color(0xFF4C7CAE);

  /// Olive shoulders.
  static const Color clothOlive = Color(0xFF7F9A55);

  /// Plum shoulders.
  static const Color clothPlum = Color(0xFF8E6BA8);

  /// Coral shoulders.
  static const Color clothCoral = Color(0xFFDD7A63);

  /// Sand shoulders.
  static const Color clothSand = Color(0xFFE0C48D);

  /// Teal shoulders.
  static const Color clothTeal = Color(0xFF4AA096);

  /// Slate shoulders.
  static const Color clothSlate = Color(0xFF5F6B78);

  /// Berry shoulders.
  static const Color clothBerry = Color(0xFFC0567F);

  /// Mustard shoulders.
  static const Color clothMustard = Color(0xFFD9A63C);

  /// Ink shoulders.
  static const Color clothInk = Color(0xFF445066);
}

/// One character in the catalogue: an id, the drawing to make, and the colours
/// to make it in.
@immutable
class AvatarFace {
  /// Describes a character.
  const AvatarFace({
    required this.id,
    required this.name,
    required this.shape,
    required this.fur,
    required this.cloth,
    this.trim,
  });

  /// Stable index, persisted as `avatarId`.
  final int id;

  /// Short name, spoken by screen readers and shown under the picker.
  final String name;

  /// Which drawing the painter makes.
  final AvatarShape shape;

  /// The coat.
  final Color fur;

  /// The shoulders below the chin.
  final Color cloth;

  /// One accent: a collar tag, a tuft, a bow.
  final Color? trim;
}

/// Every character the app can draw, in id order.
///
/// ## Ten cats, one family
///
/// This used to be eighteen faces across People, Animals and Anime, tabbed in
/// the picker. STUPID GAMES has one cast, and it is cats — so the tabs are
/// gone, the grid is one wrap of ten, and every character is a variation on
/// the same animal wearing a different mood. A player scrolling this should
/// recognise the app's logo in all ten.
///
/// ## What happened to everybody's old avatar
///
/// Nothing had to be migrated. [faceAt] has always folded an out-of-range id
/// back into the catalogue, which is what let a client render an avatar from a
/// newer build without throwing. That same fold is the migration: an account
/// holding id 14 from the old eighteen now draws cat 4. Every existing player
/// keeps a stable, deterministic face — a different one than before, which is
/// the point of a rebrand — and no stored row was touched.
///
/// The server still *accepts* the old range so those rows stay saveable; it
/// clamps new writes to ten. See `INPUT_LIMITS.legacyAvatarCount`.
abstract final class AvatarCatalog {
  /// The catalogue.
  ///
  /// Entries may be appended, never reordered: an index is persisted with the
  /// profile and broadcast to every other player.
  static const List<AvatarFace> faces = <AvatarFace>[
    AvatarFace(
      id: 0,
      name: 'Sleepy',
      shape: AvatarShape.sleeping,
      fur: AvatarPigments.furAsh,
      cloth: AvatarPigments.clothSlate,
    ),
    AvatarFace(
      id: 1,
      name: 'Giggles',
      shape: AvatarShape.laughing,
      fur: AvatarPigments.furGinger,
      cloth: AvatarPigments.clothTeal,
      trim: AvatarPigments.clothBerry,
    ),
    AvatarFace(
      id: 2,
      name: 'Grumpy',
      shape: AvatarShape.angry,
      fur: AvatarPigments.furSoot,
      cloth: AvatarPigments.clothCoral,
    ),
    AvatarFace(
      id: 3,
      name: 'Puzzled',
      shape: AvatarShape.confused,
      fur: AvatarPigments.furToffee,
      cloth: AvatarPigments.clothOlive,
    ),
    AvatarFace(
      id: 4,
      name: 'Startled',
      shape: AvatarShape.shocked,
      fur: AvatarPigments.furCream,
      cloth: AvatarPigments.clothPlum,
    ),
    AvatarFace(
      id: 5,
      name: 'Boogie',
      shape: AvatarShape.dancing,
      fur: AvatarPigments.furRust,
      cloth: AvatarPigments.clothMustard,
      trim: AvatarPigments.clothDenim,
    ),
    AvatarFace(
      id: 6,
      name: 'Yawns',
      shape: AvatarShape.lazy,
      fur: AvatarPigments.furCocoa,
      cloth: AvatarPigments.clothSand,
    ),
    AvatarFace(
      id: 7,
      name: 'Smug',
      shape: AvatarShape.smug,
      fur: AvatarPigments.furSlate,
      cloth: AvatarPigments.clothInk,
      trim: AvatarPigments.clothMustard,
    ),
    AvatarFace(
      id: 8,
      name: 'Nervous',
      shape: AvatarShape.scared,
      fur: AvatarPigments.furLilac,
      cloth: AvatarPigments.clothDenim,
    ),
    AvatarFace(
      id: 9,
      name: 'Chaos',
      shape: AvatarShape.chaotic,
      fur: AvatarPigments.furMint,
      cloth: AvatarPigments.clothBerry,
      trim: AvatarPigments.clothCoral,
    ),
  ];

  /// The face for [id], wrapping so any int is drawable.
  ///
  /// The wrap is load-bearing twice over: an avatar id from a newer build, or
  /// a corrupt value off the wire, still draws a character instead of throwing
  /// in the middle of a room — and it is what silently carried every account
  /// from the old eighteen-face catalogue onto a cat. See the class note.
  static AvatarFace faceAt(int id) => faces[id.abs() % faces.length];
}
