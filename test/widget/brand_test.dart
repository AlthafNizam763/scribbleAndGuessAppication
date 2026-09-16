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
    test('bounds enclose the whole mark, dot included', () {
      final Rect bounds = Brand.bounds;

      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
      // The dot is the lowest thing drawn, and it is not part of the pen path,
      // so a bounds calculation that forgot it would cut the mark off.
      expect(
        bounds.bottom,
        greaterThanOrEqualTo(Brand.dotCenter.dy + Brand.dotRadius),
      );
      expect(bounds.right, greaterThanOrEqualTo(Brand.dotCenter.dx));
    });

    test('bounds are tighter than the raw control-point box', () {
      // Guards the reason `_measure` exists: control points reach outside the
      // curve, so `getBounds` would pad the mark and push it off centre.
      final Rect naive = Brand.pen().getBounds();
      expect(Brand.bounds.right - Brand.strokeWidth / 2, lessThan(naive.right));
      expect(Brand.bounds.top + Brand.strokeWidth / 2, greaterThan(naive.top));
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

  group('BrandMarkPainter', () {
    test('repaints only when something visible changed', () {
      const BrandMarkPainter base = BrandMarkPainter(
        ink: Color(0xFF000000),
        accent: Color(0xFFFF0000),
      );

      expect(base.shouldRepaint(base), isFalse);
      expect(
        base.shouldRepaint(
          const BrandMarkPainter(
            ink: Color(0xFF111111),
            accent: Color(0xFFFF0000),
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const BrandMarkPainter(
            ink: Color(0xFF000000),
            accent: Color(0xFFFF0000),
            seed: 42,
          ),
        ),
        isTrue,
      );
    });

    testWidgets('paints without error at awkward sizes', (
      WidgetTester tester,
    ) async {
      for (final double size in <double>[0, 1, 13, 512]) {
        await tester.pumpWidget(_host(BrandMark(size: size)));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('BrandLogo', () {
    testWidgets('shows the name and, when given, a caption', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const BrandLogo(caption: AppStrings.appTagline)),
      );

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text(AppStrings.appTagline), findsOneWidget);
    });

    testWidgets('omits the caption when there is none', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const BrandLogo()));

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text(AppStrings.appTagline), findsNothing);
    });
  });
}
