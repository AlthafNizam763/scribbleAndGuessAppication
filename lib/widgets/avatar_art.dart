import 'package:flutter/material.dart';

/// The three families a player can pick a face from.
enum AvatarKind {
  /// People: hair, caps, glasses, beards.
  human('People'),

  /// Animals: cats, dogs, bears and friends.
  animal('Animals'),

  /// Anime: big eyes, bright hair.
  anime('Anime');

  const AvatarKind(this.label);

  /// Title shown on the picker's category tab.
  final String label;
}

/// The distinct drawings `AvatarArtPainter` knows how to make.
///
/// Kept separate from the numeric id because the two mean different things: an
/// id is persisted with the profile and broadcast to every other player, so it
/// must never be reordered, while a shape is only ever a drawing instruction
/// and is free to change with the art.
enum AvatarShape {
  /// Straight fringe, cut in a line across the brow.
  bowlCut,

  /// Side part gathered into a tail behind the right ear.
  ponytail,

  /// A halo of tight curls.
  curls,

  /// Baseball cap, brim to the left.
  ballCap,

  /// Top knot and round glasses.
  topBun,

  /// Full beard and moustache.
  beard,

  /// Pointed ears and whiskers.
  cat,

  /// Floppy ears and a wide muzzle.
  dog,

  /// Round ears and a pale snout.
  bear,

  /// Tall ears and cheek tufts.
  fox,

  /// Sooty ears and eye patches.
  panda,

  /// Long ears and two front teeth.
  bunny,

  /// Long hair with a spiked fringe.
  animeLong,

  /// Upswept spikes.
  animeSpiky,

  /// Two ribboned tails.
  animeTwinTails,

  /// Headband with trailing ribbons.
  animeNinja,

  /// Cat ears over a bob.
  animeCatGirl,

  /// Swept fringe and a closed-eye grin.
  animeCool,
}

/// The pigments characters are drawn with.
///
/// Deliberately brightness independent, the same way `AppColors.drawingPalette`
/// is: an avatar is a sticker stuck onto the page, and a sticker does not
/// repaint itself at night. Only the disc behind it and its ring follow the
/// theme, and that is what keeps the avatar reading as part of the sketchbook.
abstract final class AvatarPigments {
  /// Every outline on a character.
  static const Color line = Color(0xFF33302B);

  /// Eye whites, teeth and highlights.
  static const Color light = Color(0xFFFFFBF3);

  /// Warm cheeks, always laid down translucent.
  static const Color blush = Color(0xFFE07A72);

  /// Noses, inner ears and tongues.
  static const Color petal = Color(0xFFE58B92);

  // ----------------------------------------------------------------- skin ---

  /// Palest skin.
  static const Color skinPorcelain = Color(0xFFFBDFC4);

  /// Warm mid skin.
  static const Color skinWarm = Color(0xFFF1C79C);

  /// Tan skin.
  static const Color skinTan = Color(0xFFD29C6D);

  /// Deep skin.
  static const Color skinDeep = Color(0xFFA9714B);

  // ----------------------------------------------------------------- hair ---

  /// Near-black hair.
  static const Color hairInk = Color(0xFF3C332C);

  /// Warm brown hair.
  static const Color hairChestnut = Color(0xFF87512E);

  /// Blonde hair.
  static const Color hairGold = Color(0xFFE9BC57);

  /// Ginger hair.
  static const Color hairRust = Color(0xFFC85E3A);

  /// Anime blue.
  static const Color hairSky = Color(0xFF5B8AC9);

  /// Anime pink.
  static const Color hairBubblegum = Color(0xFFEB8FB7);

  /// Anime mint.
  static const Color hairMint = Color(0xFF57BFAA);

  /// Anime purple.
  static const Color hairGrape = Color(0xFF9A7ACD);

  // ------------------------------------------------------------------ fur ---

  /// Ginger coat.
  static const Color furGinger = Color(0xFFE9A055);

  /// Cocoa coat.
  static const Color furCocoa = Color(0xFF9E6F4A);

  /// Grey coat.
  static const Color furAsh = Color(0xFFC5BCAF);

  /// Cream coat.
  static const Color furCream = Color(0xFFF7EBDB);

  /// Sooty markings.
  static const Color furSoot = Color(0xFF3E372F);

  /// Fox rust.
  static const Color furRust = Color(0xFFDB7440);

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
}

/// One character in the catalogue: an id, the family it is filed under, the
/// drawing to make, and the colours to make it in.
@immutable
class AvatarFace {
  /// Describes a character.
  const AvatarFace({
    required this.id,
    required this.kind,
    required this.name,
    required this.shape,
    required this.skin,
    required this.hair,
    required this.cloth,
    this.trim,
  });

  /// Stable index, persisted as `avatarId`.
  final int id;

  /// The family this face is filed under in the picker.
  final AvatarKind kind;

  /// Short name, spoken by screen readers.
  final String name;

  /// Which drawing the painter makes.
  final AvatarShape shape;

  /// Skin for people, coat for animals.
  final Color skin;

  /// Hair for people, ear lining or marking for animals.
  final Color hair;

  /// The shoulders below the chin.
  final Color cloth;

  /// One accent: a ribbon, a headband, a cap button.
  final Color? trim;
}

/// Every character the app can draw, in id order.
abstract final class AvatarCatalog {
  /// The catalogue, grouped by family for the picker.
  ///
  /// Entries may be appended, never reordered: an index is persisted with the
  /// profile and broadcast to every other player.
  static const List<AvatarFace> faces = <AvatarFace>[
    // -------------------------------------------------------- people (0-5) ---
    AvatarFace(
      id: 0,
      kind: AvatarKind.human,
      name: 'Bowl cut',
      shape: AvatarShape.bowlCut,
      skin: AvatarPigments.skinPorcelain,
      hair: AvatarPigments.hairInk,
      cloth: AvatarPigments.clothCoral,
    ),
    AvatarFace(
      id: 1,
      kind: AvatarKind.human,
      name: 'Ponytail',
      shape: AvatarShape.ponytail,
      skin: AvatarPigments.skinWarm,
      hair: AvatarPigments.hairChestnut,
      cloth: AvatarPigments.clothTeal,
      trim: AvatarPigments.clothBerry,
    ),
    AvatarFace(
      id: 2,
      kind: AvatarKind.human,
      name: 'Curly hair',
      shape: AvatarShape.curls,
      skin: AvatarPigments.skinDeep,
      hair: AvatarPigments.hairInk,
      cloth: AvatarPigments.clothSand,
    ),
    AvatarFace(
      id: 3,
      kind: AvatarKind.human,
      name: 'Baseball cap',
      shape: AvatarShape.ballCap,
      skin: AvatarPigments.skinTan,
      hair: AvatarPigments.hairInk,
      cloth: AvatarPigments.clothOlive,
      trim: AvatarPigments.clothDenim,
    ),
    AvatarFace(
      id: 4,
      kind: AvatarKind.human,
      name: 'Glasses',
      shape: AvatarShape.topBun,
      skin: AvatarPigments.skinPorcelain,
      hair: AvatarPigments.hairGold,
      cloth: AvatarPigments.clothPlum,
    ),
    AvatarFace(
      id: 5,
      kind: AvatarKind.human,
      name: 'Beard',
      shape: AvatarShape.beard,
      skin: AvatarPigments.skinWarm,
      hair: AvatarPigments.hairRust,
      cloth: AvatarPigments.clothSlate,
    ),
    // ------------------------------------------------------ animals (6-11) ---
    AvatarFace(
      id: 6,
      kind: AvatarKind.animal,
      name: 'Cat',
      shape: AvatarShape.cat,
      skin: AvatarPigments.furGinger,
      hair: AvatarPigments.petal,
      cloth: AvatarPigments.clothDenim,
    ),
    AvatarFace(
      id: 7,
      kind: AvatarKind.animal,
      name: 'Dog',
      shape: AvatarShape.dog,
      skin: AvatarPigments.furCocoa,
      hair: AvatarPigments.furCream,
      cloth: AvatarPigments.clothCoral,
    ),
    AvatarFace(
      id: 8,
      kind: AvatarKind.animal,
      name: 'Bear',
      shape: AvatarShape.bear,
      skin: AvatarPigments.furCocoa,
      hair: AvatarPigments.furCream,
      cloth: AvatarPigments.clothTeal,
    ),
    AvatarFace(
      id: 9,
      kind: AvatarKind.animal,
      name: 'Fox',
      shape: AvatarShape.fox,
      skin: AvatarPigments.furRust,
      hair: AvatarPigments.furCream,
      cloth: AvatarPigments.clothOlive,
    ),
    AvatarFace(
      id: 10,
      kind: AvatarKind.animal,
      name: 'Panda',
      shape: AvatarShape.panda,
      skin: AvatarPigments.furCream,
      hair: AvatarPigments.furSoot,
      cloth: AvatarPigments.clothPlum,
    ),
    AvatarFace(
      id: 11,
      kind: AvatarKind.animal,
      name: 'Bunny',
      shape: AvatarShape.bunny,
      skin: AvatarPigments.furAsh,
      hair: AvatarPigments.petal,
      cloth: AvatarPigments.clothBerry,
    ),
    // ------------------------------------------------------- anime (12-17) ---
    AvatarFace(
      id: 12,
      kind: AvatarKind.anime,
      name: 'Long hair',
      shape: AvatarShape.animeLong,
      skin: AvatarPigments.skinPorcelain,
      hair: AvatarPigments.hairBubblegum,
      cloth: AvatarPigments.clothSlate,
    ),
    AvatarFace(
      id: 13,
      kind: AvatarKind.anime,
      name: 'Spiky hair',
      shape: AvatarShape.animeSpiky,
      skin: AvatarPigments.skinWarm,
      hair: AvatarPigments.hairSky,
      cloth: AvatarPigments.clothCoral,
    ),
    AvatarFace(
      id: 14,
      kind: AvatarKind.anime,
      name: 'Twin tails',
      shape: AvatarShape.animeTwinTails,
      skin: AvatarPigments.skinPorcelain,
      hair: AvatarPigments.hairGold,
      cloth: AvatarPigments.clothTeal,
      trim: AvatarPigments.clothBerry,
    ),
    AvatarFace(
      id: 15,
      kind: AvatarKind.anime,
      name: 'Ninja',
      shape: AvatarShape.animeNinja,
      skin: AvatarPigments.skinTan,
      hair: AvatarPigments.hairInk,
      cloth: AvatarPigments.clothSlate,
      trim: AvatarPigments.clothCoral,
    ),
    AvatarFace(
      id: 16,
      kind: AvatarKind.anime,
      name: 'Cat ears',
      shape: AvatarShape.animeCatGirl,
      skin: AvatarPigments.skinPorcelain,
      hair: AvatarPigments.hairGrape,
      cloth: AvatarPigments.clothDenim,
      trim: AvatarPigments.petal,
    ),
    AvatarFace(
      id: 17,
      kind: AvatarKind.anime,
      name: 'Big smile',
      shape: AvatarShape.animeCool,
      skin: AvatarPigments.skinDeep,
      hair: AvatarPigments.hairMint,
      cloth: AvatarPigments.clothSand,
    ),
  ];

  /// The face for [id], wrapping so any int is drawable — an avatar from a
  /// newer build, or a corrupt value off the wire, still draws a character
  /// instead of throwing in the middle of a room.
  static AvatarFace faceAt(int id) => faces[id.abs() % faces.length];

  /// Every face in [kind], in id order.
  static List<AvatarFace> of(AvatarKind kind) =>
      faces.where((AvatarFace face) => face.kind == kind).toList();
}
