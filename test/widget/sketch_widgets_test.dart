import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/widgets/sketch_button.dart';
import 'package:scribble_guess/core/widgets/sketch_card.dart';
import 'package:scribble_guess/theme/theme.dart';

/// Widget tests for the sketch UI kit (§65).
///
/// These deliberately avoid the game screens, which need Firebase providers
/// overridden to be meaningful. What they cover is the layer everything else
/// is built from — and, in the painter group, the one property the hand-drawn
/// aesthetic actually depends on: that the wobble is *stable*. A border that
/// re-randomised every frame would make the whole interface shimmer, which is
/// both ugly and, for motion-sensitive players, genuinely unpleasant (§59).
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('SketchButton', () {
    testWidgets('shows its label', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(SketchButton(label: 'Start Game', onPressed: () {})),
      );
      expect(find.text('Start Game'), findsOneWidget);
    });

    testWidgets('fires once when tapped', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        wrap(SketchButton(label: 'Tap', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Tap'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('does nothing when disabled', (WidgetTester tester) async {
      const int taps = 0;
      await tester.pumpWidget(
        wrap(const SketchButton(label: 'Off', onPressed: null)),
      );
      await tester.tap(find.text('Off'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('meets the minimum touch target', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(SketchButton(label: 'Tap', onPressed: () {})),
      );
      // 44dp is the accessibility floor for a tappable control (§59).
      final Size size = tester.getSize(find.byType(SketchButton));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('SketchCard', () {
    testWidgets('renders its child', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const SketchCard(child: Text('Room A7K9P'))),
      );
      expect(find.text('Room A7K9P'), findsOneWidget);
    });

    testWidgets('is tappable when given a handler', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        wrap(SketchCard(onTap: () => taps++, child: const Text('Pick me'))),
      );
      await tester.tap(find.text('Pick me'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('SketchBorderPainter', () {
    test('does not repaint when nothing changed', () {
      const SketchBorderPainter a =
          SketchBorderPainter(color: Color(0xFF1A1A1A), seed: 42);
      const SketchBorderPainter b =
          SketchBorderPainter(color: Color(0xFF1A1A1A), seed: 42);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('repaints when the seed or colour changes', () {
      const SketchBorderPainter base =
          SketchBorderPainter(color: Color(0xFF1A1A1A), seed: 42);
      expect(
        base.shouldRepaint(
          const SketchBorderPainter(color: Color(0xFF1A1A1A), seed: 43),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const SketchBorderPainter(color: Color(0xFFFF0000), seed: 42),
        ),
        isTrue,
      );
    });

    testWidgets('paints without error at awkward sizes',
        (WidgetTester tester) async {
      // A zero-height box and a box smaller than the corner radius are both
      // reachable during layout; neither may throw.
      for (final Size size in <Size>[
        const Size(0, 0),
        const Size(4, 4),
        const Size(200, 80),
      ]) {
        await tester.pumpWidget(
          wrap(
            SizedBox(
              width: size.width,
              height: size.height,
              child: const CustomPaint(
                painter: SketchBorderPainter(
                  color: Color(0xFF1A1A1A),
                  seed: 7,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('SketchSeeds', () {
    test('is stable for the same input', () {
      expect(SketchSeeds.of('player-1'), SketchSeeds.of('player-1'));
    });

    test('differs between neighbours, so borders do not look cloned', () {
      expect(SketchSeeds.of('player-1'), isNot(SketchSeeds.of('player-2')));
      expect(SketchSeeds.index(0), isNot(SketchSeeds.index(1)));
    });

    test('stays a positive int for any string', () {
      for (final String value in <String>['', 'a', 'a very long room id 12345']) {
        expect(SketchSeeds.of(value), greaterThanOrEqualTo(0));
      }
    });
  });
}
