import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/features/game/widgets/tool_tray_sheet.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/providers/draw_tool_provider.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The drawing tools sheet.
///
/// ## The bug these are written against
///
/// `showToolTray` opened a plain `showModalBottomSheet`, which without
/// `isScrollControlled` is laid out against a hard ceiling of nine sixteenths
/// of the screen. The tray's content is a `Column`, so anything past that line
/// was clipped with no way to reach it: on a 6.5" phone the three tool groups
/// wrap to five rows of chips and consume the budget before the brush size
/// slider, which was therefore invisible and unreachable. At a larger system
/// font scale it went sooner.
///
/// So the assertions below are deliberately about *geometry* rather than about
/// the widget tree. `findsOneWidget` passes for a widget that has been laid out
/// two hundred pixels below the bottom of the screen — which is exactly the
/// state the bug was in — so each test here scrolls the sheet and then checks
/// that the control is inside the viewport and big enough to hit.
void main() {
  /// Opens the tray on a phone of [size] at [textScale].
  ///
  /// The default is a 6.53" phone at 1x — a Redmi Note 10S in logical pixels,
  /// which is the device the overflow was reported on.
  Future<void> openTray(
    WidgetTester tester, {
    Size size = const Size(393, 873),
    double textScale = 1,
    DrawingToolActions actions = const DrawingToolActions(),
  }) async {
    // Everything is set on the *view* rather than by wrapping the screen in a
    // MediaQuery. A modal bottom sheet is a route and builds under the
    // Navigator, not under the widget that opened it, so a MediaQuery wrapped
    // around the home screen never reaches the sheet — a test written that way
    // would appear to pass at 1.4x while having measured 1x.
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      // A gesture-navigation phone: the sheet must keep its last control clear
      // of the bar rather than tucking it underneath.
      ..padding = const FakeViewPadding(bottom: 24)
      ..viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.reset);

    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppTextDelegate(),
          ],
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showToolTray(context, actions: actions),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Scrolls the sheet until [finder] is on screen, then returns its rect.
  ///
  /// `scrollUntilVisible` is the assertion as much as the setup: it fails if
  /// there is no scrollable, which is precisely what the bug was.
  Future<Rect> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    return tester.getRect(finder);
  }

  /// Whether [rect] is wholly inside the screen.
  bool isOnScreen(WidgetTester tester, Rect rect) {
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    return rect.top >= 0 &&
        rect.bottom <= screen.height &&
        rect.left >= 0 &&
        rect.right <= screen.width;
  }

  group('the tool tray', () {
    testWidgets('offers every drawing tool', (WidgetTester tester) async {
      await openTray(tester);

      // All nine, by the label the chip draws. A tool quietly dropped from
      // `_toolGroups` would otherwise be invisible and unreported.
      for (final DrawTool tool in DrawTool.values) {
        await tester.scrollUntilVisible(
          find.text(tool.label),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(tool.label), findsOneWidget, reason: tool.label);
      }
    });

    testWidgets('brings the brush size slider fully on screen',
        (WidgetTester tester) async {
      await openTray(tester);

      final Rect slider = await reveal(tester, find.byType(Slider));

      // The exact control the bug hid.
      expect(isOnScreen(tester, slider), isTrue,
          reason: 'the brush size slider is off screen at $slider');
      expect(slider.height, greaterThan(24));
    });

    testWidgets('scrolls on a small phone', (WidgetTester tester) async {
      // A 4.7" handset — the smallest thing the game is expected to run on.
      await openTray(tester, size: const Size(320, 568));

      final Rect slider = await reveal(tester, find.byType(Slider));
      expect(isOnScreen(tester, slider), isTrue);
    });

    testWidgets('scrolls at the largest system font the app allows',
        (WidgetTester tester) async {
      // 1.4x is the ceiling `app.dart` clamps to. Every chip is taller and
      // wider here, so the content that used to be clipped is now well past
      // the fold.
      await openTray(tester, textScale: 1.4);

      final Rect slider = await reveal(tester, find.byType(Slider));
      expect(isOnScreen(tester, slider), isTrue);
    });

    testWidgets('scrolls in landscape', (WidgetTester tester) async {
      await openTray(tester, size: const Size(873, 393));

      final Rect slider = await reveal(tester, find.byType(Slider));
      expect(isOnScreen(tester, slider), isTrue);
    });

    testWidgets('keeps the last control clear of the keyboard',
        (WidgetTester tester) async {
      // Set on the *view* rather than by wrapping the screen in a MediaQuery.
      //
      // A modal bottom sheet is a route: it builds under the Navigator, not
      // under the widget that opened it, so a MediaQuery wrapped around the
      // home screen never reaches the sheet. Only the view's own metrics do —
      // which is also how a real keyboard arrives.
      tester.view
        ..physicalSize = const Size(393, 873)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppTextDelegate(),
            ],
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showToolTray(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Scrolled to the very end rather than merely "until visible".
      //
      // The distinction matters and is the whole point of this test. The
      // scroll view's own viewport runs to the bottom edge of the screen —
      // Flutter's modal sheet does not inset itself for the keyboard, so a
      // widget sitting *behind* the keyboard counts as visible to the
      // framework. `scrollUntilVisible` would stop there and prove nothing.
      //
      // What the sheet actually guarantees is that the keyboard's height is
      // carried as trailing padding, so scrolling to the end always leaves
      // the last control above it.
      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final Rect done = tester.getRect(find.text('Done'));

      // Above the keyboard, not behind it. The practice screen's guess field
      // is one tap from the tools button, so this is a real sequence rather
      // than a hypothetical one.
      expect(done.bottom, lessThanOrEqualTo(873 - 320));
    });

    testWidgets('changes the tool without closing', (WidgetTester tester) async {
      late WidgetRef captured;

      tester.view
        ..physicalSize = const Size(393, 873)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppTextDelegate(),
            ],
            home: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                captured = ref;
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showToolTray(context),
                      child: const Text('open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(DrawTool.circle.label));
      await tester.pumpAndSettle();

      expect(captured.read(drawToolProvider).tool, DrawTool.circle);
      // Still open: picking a nib and then a size is one errand, and closing
      // after the first half of it is what made the size controls hard to
      // reach in the first place.
      expect(find.text(DrawTool.circle.label), findsOneWidget);
    });

    testWidgets('hides the size slider for the fill, which has no width',
        (WidgetTester tester) async {
      await openTray(tester);

      await tester.tap(find.text(DrawTool.fill.label));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('offers undo, redo and clear when the screen supplies them',
        (WidgetTester tester) async {
      int undos = 0;

      await openTray(
        tester,
        actions: DrawingToolActions(
          onUndo: () => undos += 1,
          onRedo: () {},
          onClear: () {},
        ),
      );

      final Rect undo = await reveal(tester, find.text('Undo'));
      expect(isOnScreen(tester, undo), isTrue);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undos, 1);
    });

    testWidgets('omits the action row when no screen supplied one',
        (WidgetTester tester) async {
      await openTray(tester);

      // Three dead buttons would be worse than none: a drawer who taps one and
      // watches nothing happen learns to distrust the whole sheet.
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Clear'), findsNothing);
    });
  });
}
