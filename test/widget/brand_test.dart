import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/widgets/brand_logo.dart';
import 'package:scribble_guess/theme/theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('Brand geometry', () {
    test('bounds enclose the whole cat, tail included', () {
      final Rect bounds = Brand.bounds;

      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));

      // The tail is a stroke drawn outside the filled silhouette, and it is
      // the rightmost thing in the mark. A bounds calculation that measured
      // only the fill would crop it on every platform icon.
      final Rect tail = Brand.tail().getBounds();
      expect(bounds.right, greaterThanOrEqualTo(tail.right));
      expect(bounds.top, lessThanOrEqualTo(Brand.silhouette().getBounds().top));
    });

    test('the ears are the top of the mark', () {
      // Cheap proxy for "the silhouette is still cat-shaped": whatever else
      // moves, the ear tips have to stay the highest points, or the cat has
      // quietly become a blob.
      final Rect head = Brand.silhouette().getBounds();
      expect(head.top, lessThan(16.5));
    });

    test('the paw sits over the muzzle, not beside it', () {
      // The whole joke is the paw covering the mouth. If these two stop
      // overlapping the cat is just waving.
      expect(Brand.paw().getBounds().overlaps(Brand.muzzle().getBounds()), isTrue);
    });

    test('stays roughly square, so no platform icon crops it', () {
      final double ratio = Brand.bounds.width / Brand.bounds.height;
      expect(ratio, greaterThan(0.8));
      expect(ratio, lessThan(1.25));
    });

    test('the maskable size fits inside the adaptive icon safe zone', () {
      // Android guarantees only the central 72 of 108 units survives a mask.
      expect(Brand.maskableScale, lessThanOrEqualTo(72 / 108));
      expect(Brand.iconScale, lessThan(1));
    });
  });

  group('BrandInk', () {
    test('a flat cut collapses every colour into one', () {
      const Color black = Color(0xFF000000);
      final BrandInk flat = BrandInk.flat(black);

      // The Android themed-icon layer reads alpha only, so anything that is
      // not one flat colour here would render as a silhouette with holes.
      expect(flat.fur, black);
      expect(flat.outline, black);
      expect(flat.light, black);
      expect(flat.accent, black);
    });
  });

  group('BrandMarkPainter', () {
    test('repaints only when something visible changed', () {
      const BrandMarkPainter base = BrandMarkPainter();

      expect(base.shouldRepaint(base), isFalse);
      expect(
        base.shouldRepaint(BrandMarkPainter(ink: BrandInk.flat(const Color(0xFF111111)))),
        isTrue,
      );
      // The splash animates these two, so a painter that ignored them would
      // hold the first frame for the whole animation.
      expect(base.shouldRepaint(const BrandMarkPainter(tilt: 0.1)), isTrue);
      expect(base.shouldRepaint(const BrandMarkPainter(hop: 1)), isTrue);
    });

    testWidgets('paints without error at awkward sizes', (
      WidgetTester tester,
    ) async {
      for (final double size in <double>[0, 1, 13, 512]) {
        await tester.pumpWidget(_host(BrandMark(size: size)));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('paints without error mid-animation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const BrandMark(size: 96, tilt: Brand.laughTilt, hop: 1)),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('BrandWordmark', () {
    testWidgets('sets STUPID letter by letter and GAMES as one word', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const BrandWordmark()));

      // STUPID is six independently rocked tiles, each painted twice — once
      // stroked for the outline, once filled — so every letter appears twice.
      for (final String letter in <String>['S', 'T', 'U', 'P', 'I', 'D']) {
        expect(find.text(letter), findsNWidgets(2));
      }
      // GAMES stays one run, so it keeps its tracking and stays legible.
      expect(find.text('GAMES'), findsNWidgets(2));
    });

    testWidgets('announces the app name to screen readers', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const BrandWordmark()));

      // The letters are decoration; the name is what a screen reader needs.
      expect(
        find.bySemanticsLabel(AppStrings.appName),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('BrandLogo', () {
    testWidgets('shows the wordmark and, when given, a caption', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const BrandLogo(caption: AppStrings.appTagline)),
      );

      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.byType(BrandWordmark), findsOneWidget);
      expect(find.text(AppStrings.appTagline), findsOneWidget);
    });

    testWidgets('omits the caption when there is none', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const BrandLogo()));

      expect(find.byType(BrandWordmark), findsOneWidget);
      expect(find.text(AppStrings.appTagline), findsNothing);
    });
  });
}
