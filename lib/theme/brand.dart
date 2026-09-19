import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:scribble_guess/theme/app_colors.dart';

/// The STUPID GAMES mark, as pure geometry.
///
/// A cat sitting on its haunches, eyes squeezed shut, one paw clapped over its
/// mouth because it cannot keep a straight face. It is the single most
/// recognisable beat in the brand — the moment *after* the stupid thing
/// happened — and it is the whole app icon, because a logo has to survive
/// being 16 pixels wide and a falling person does not.
///
/// It is described exactly once, here, in an abstract 100×100 box. Everything
/// else — the in-app logo, the launcher icons on five platforms, the splash
/// art — is this same set of paths scaled to fit, so there is no master PNG
/// anywhere that can drift out of sync with the app.
///
/// See `tool/generate_brand_assets.dart` for the renderer that turns it into
/// platform bitmaps, and `core/widgets/brand_logo.dart` for the painter.
abstract final class Brand {
  /// The abstract box the geometry below is expressed in.
  static const Size designSize = Size(100, 100);

  // -------------------------------------------------------------- silhouette

  /// Head, ears and haunches as one filled shape.
  ///
  /// Built by union rather than as one hand-traced outline: the three pieces
  /// each have an obvious centre and size that can be nudged independently,
  /// and the seams between them are exactly where a cat's are anyway.
  static Path silhouette() {
    Path shape = Path()..addOval(_headBox);
    shape = Path.combine(PathOperation.union, shape, _ear(mirrored: false));
    shape = Path.combine(PathOperation.union, shape, _ear(mirrored: true));
    return Path.combine(PathOperation.union, shape, haunches());
  }

  /// The head's bounding box. Wider than tall, the way a smug cat's is.
  static const Rect _headBox = Rect.fromLTRB(24, 16.5, 76, 63.5);

  /// One ear. [mirrored] flips it across the vertical centre line.
  static Path _ear({required bool mirrored}) {
    final Path ear = Path()
      ..moveTo(_x(28, mirrored), 25)
      ..lineTo(_x(23, mirrored), 5)
      ..lineTo(_x(45, mirrored), 17)
      ..close();
    return ear;
  }

  /// The inner ear, in the one hot accent colour the mark carries.
  static Path innerEar({required bool mirrored}) {
    return Path()
      ..moveTo(_x(30.5, mirrored), 22)
      ..lineTo(_x(28, mirrored), 11.5)
      ..lineTo(_x(40.5, mirrored), 18)
      ..close();
  }

  /// The sitting body: shoulders narrow, base wide, corners softened.
  static Path haunches() {
    return Path()
      ..moveTo(33, 54)
      ..cubicTo(25, 68, 20, 81, 20, 88)
      ..quadraticBezierTo(20, 93, 26, 93)
      ..lineTo(74, 93)
      ..quadraticBezierTo(80, 93, 80, 88)
      ..cubicTo(80, 81, 75, 68, 67, 54)
      ..close();
  }

  /// The tail, curling up and hooking back in. Stroked, not filled.
  ///
  /// It starts inside the haunches and is drawn before them, so the join
  /// disappears under the body rather than showing as a seam — and the hook
  /// stops clear of the body's right edge, so the curl reads as a curl and
  /// not as a second leg.
  static Path tail() {
    return Path()
      ..moveTo(74, 91)
      ..cubicTo(90, 92, 97, 78, 90, 68)
      ..cubicTo(86, 62, 79, 64, 80, 70);
  }

  /// Pen width for [tail], in design units.
  static const double tailWidth = 8.5;

  // ------------------------------------------------------------------ face

  /// The two shut, delighted eyes. Arcs opening downward — a laughing squint,
  /// not a sleeping one, which is the difference between this cat and a nap.
  static Path eyes() {
    return Path()
      ..moveTo(34, 44)
      ..quadraticBezierTo(40.5, 34.5, 47, 44)
      ..moveTo(53, 44)
      ..quadraticBezierTo(59.5, 34.5, 66, 44);
  }

  /// Pen width for [eyes].
  static const double eyeWidth = 4.2;

  /// The pale muzzle the paw is clapped over.
  static Path muzzle() {
    return Path()..addOval(const Rect.fromLTRB(38, 47, 62, 62));
  }

  /// The paw itself: a tilted bean over the mouth.
  static Path paw() {
    return Path()
      ..moveTo(35, 59)
      ..cubicTo(34, 52, 41, 48.5, 48, 50)
      ..cubicTo(55, 51.5, 57, 58, 52, 61.5)
      ..cubicTo(46, 65, 37, 64.5, 35, 59)
      ..close();
  }

  /// The two creases that make [paw] read as toes rather than a mitten.
  static Path toes() {
    return Path()
      ..moveTo(40, 51.5)
      ..lineTo(39, 59)
      ..moveTo(47, 52.5)
      ..lineTo(46, 60.5);
  }

  /// Pen width for [toes].
  static const double toeWidth = 2.4;

  /// Whiskers, on the side the paw has not covered.
  ///
  /// Deliberately sparse, and deliberately one-sided: the paw is over the
  /// cat's other cheek, so whiskers there would have to cross it. Two lines
  /// survive being shrunk to a favicon as texture, where six become a smudge.
  static Path whiskers() {
    return Path()
      ..moveTo(61, 51)
      ..lineTo(75, 47)
      ..moveTo(62, 55.5)
      ..lineTo(73, 56.5);
  }

  /// Pen width for [whiskers].
  static const double whiskerWidth = 2;

  /// Mirrors [value] about the design box's vertical centre when asked.
  static double _x(double value, bool mirrored) =>
      mirrored ? designSize.width - value : value;

  // ---------------------------------------------------------------- bounds

  /// Everything the mark covers, ink width included.
  ///
  /// Used to centre and scale the composition into whatever box it is given,
  /// so it sits true without anyone hand-tuning offsets per platform.
  static final Rect bounds = _measure();

  static Rect _measure() {
    final Rect solid = silhouette().getBounds();
    // The tail is a stroke, so its own bounds are the centre line; half the
    // pen reaches outside that on every side.
    final Rect tailInk = tail().getBounds().inflate(tailWidth / 2);
    return solid.expandToInclude(tailInk);
  }

  // ---------------------------------------------------------------- colour

  /// The ink every outline and crease is drawn in.
  ///
  /// Fixed rather than theme-aware: a launcher icon is baked once and has no
  /// idea what the phone's brightness will be, so it carries its own colours
  /// with it and reads on any home screen.
  static const Color outline = AppColors.brandInk;

  /// The cat's coat.
  static const Color fur = AppColors.brandOrange;

  /// Muzzle, paw, eyes — everything that has to pop off the coat.
  static const Color light = Color(0xFFFFF3DF);

  /// The one hot note: inner ears.
  static const Color accent = AppColors.brandPink;

  /// The plate a platform icon is printed on.
  static const Color iconPlate = AppColors.brandPlate;

  /// Fraction of a launcher icon's width the mark should occupy.
  ///
  /// Distinct from the adaptive/maskable value below because a plain icon is
  /// never cropped, so it can afford to be bolder.
  static const double iconScale = 0.72;

  /// Fraction for icons the platform is allowed to crop.
  ///
  /// An Android adaptive icon is drawn on a 108dp canvas of which only the
  /// central 72dp is guaranteed to survive the launcher's mask, and Material's
  /// keyline for a square inside that is 60dp — which is what this is: 60 of
  /// 108. A web maskable icon guarantees a more generous central 80%, so the
  /// same number is safe there too and the mark stays one size across both.
  static const double maskableScale = 0.6;

  /// Outline weight, as a fraction of the rendered mark's width.
  ///
  /// Proportional rather than absolute so the cat keeps the same visual weight
  /// at 16 pixels and at 1024, instead of dissolving at one end and turning
  /// into a woodcut at the other.
  static const double outlineRatio = 0.028;

  /// Smallest outline the renderer will lay down, in device pixels.
  ///
  /// Below roughly this, antialiasing turns a line into a grey suggestion.
  static const double minOutline = 0.9;

  /// How far the mark leans, in radians, when it is laughing hardest.
  ///
  /// The mark is drawn upright everywhere static; the splash animation borrows
  /// this so the tilt it rocks through is a brand value rather than a number
  /// somebody picked inside an animation controller.
  static const double laughTilt = 0.075;

  /// Design-space centre the mark rocks about: the base of the haunches.
  static const Offset pivot = Offset(50, 90);

  /// Distance from the design box's centre, used by the splash to throw the
  /// mark up and let it drop back.
  static const double hopHeight = 6;

  /// Converts a fraction of the rendered width into a design-space pen width.
  static double penFor(double renderedWidth, double scale) =>
      math.max(minOutline / math.max(scale, 0.0001), renderedWidth);
}
