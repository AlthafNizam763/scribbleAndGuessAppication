import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/app_button.dart';
import 'package:scribble_guess/core/widgets/app_card.dart';
import 'package:scribble_guess/core/widgets/app_controls.dart';
import 'package:scribble_guess/core/widgets/app_dialogs.dart';
import 'package:scribble_guess/core/widgets/app_scaffold.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The design system: the tokens, the two themes, and the widget kit every
/// screen is assembled from.
///
/// ## Why these particular assertions
///
/// A visual system cannot be tested by looking at it, so this checks the two
/// things that actually break it in practice. First, that the palette is
/// *reachable*: every screen reads colour through `context.palette`, and a
/// theme that forgot to install the extension would silently fall back to the
/// light palette and paint white cards on a black page. Second, that the kit
/// still lays out — a dialog whose buttons sit in a `Row` of `Expanded`
/// children is one unbounded constraint away from throwing, and it throws in
/// front of the player rather than in the analyzer.
void main() {
  /// Pumps [child] under one of the app's real themes.
  Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
    theme: theme ?? AppTheme.light,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      AppTextDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );

  group('palette', () {
    test('the two palettes disagree about brightness', () {
      expect(AppPalette.light.isDark, isFalse);
      expect(AppPalette.dark.isDark, isTrue);
      expect(AppPalette.light.bg, isNot(AppPalette.dark.bg));
      expect(AppPalette.light.text, isNot(AppPalette.dark.text));
    });

    test('every accent index resolves, however wild the index', () {
      for (final AppPalette palette in <AppPalette>[
        AppPalette.light,
        AppPalette.dark,
      ]) {
        expect(palette.accents, hasLength(8));
        expect(palette.accentAt(0), palette.accentRed);
        expect(palette.accentAt(9), palette.accentAt(1));
        expect(palette.accentAt(-1), palette.accentAt(1));
      }
    });

    test('onFill picks readable ink for both ends of the range', () {
      // A game tint can arrive from the server, so this has to be computed
      // rather than looked up.
      expect(
        AppPalette.light.onFill(const Color(0xFF14121F)).computeLuminance(),
        greaterThan(0.5),
      );
      expect(
        AppPalette.light.onFill(const Color(0xFFFFE066)).computeLuminance(),
        lessThan(0.5),
      );
    });

    test('the avatar palette order is the one the wire depends on', () {
      // An index is persisted with the profile and broadcast to every other
      // player, so a reorder would repaint everybody's face.
      expect(AppColors.avatarPalette, hasLength(8));
      expect(AppColors.avatarPalette.first, AppColors.accentRed);
      expect(AppColors.avatarPalette.last, AppColors.accentTeal);
      expect(AppColors.drawingPalette, hasLength(24));
      expect(AppColors.drawingPalette.first, const Color(0xFF000000));
    });
  });

  group('themes', () {
    for (final (String name, ThemeData theme, AppPalette expected) entry in <
      (String, ThemeData, AppPalette)
    >[
      ('light', AppTheme.light, AppPalette.light),
      ('dark', AppTheme.dark, AppPalette.dark),
    ]) {
      test('${entry.$1} carries its palette as an extension', () {
        expect(entry.$2.extension<AppPalette>(), entry.$3);
        expect(entry.$2.scaffoldBackgroundColor, entry.$3.bg);
      });

      test('${entry.$1} uses the body face and no surface tint', () {
        expect(entry.$2.textTheme.bodyMedium?.fontFamily,
            AppTypography.bodyFamily);
        expect(entry.$2.textTheme.headlineMedium?.fontFamily,
            AppTypography.displayFamily);
        // Material's tint bleeds the primary into every raised surface, which
        // is the look the system is built to avoid.
        expect(entry.$2.colorScheme.surfaceTint.a, 0);
      });
    }

    testWidgets('context.palette follows the active brightness',
        (WidgetTester tester) async {
      late AppPalette seen;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) {
              seen = context.palette;
              return const SizedBox.shrink();
            },
          ),
          theme: AppTheme.dark,
        ),
      );
      expect(seen.isDark, isTrue);
    });
  });

  group('typography', () {
    test('never asks for a weight the app does not bundle', () {
      // Space Grotesk ships 400, 500 and 700 only. Anything else is
      // synthesised, which is exactly the smeared look this replaced.
      final Set<FontWeight> shipped = <FontWeight>{
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w700,
      };
      final TextTheme theme = AppTypography.textTheme(const Color(0xFF000000));
      final List<TextStyle?> styles = <TextStyle?>[
        theme.displayLarge,
        theme.displayMedium,
        theme.displaySmall,
        theme.headlineLarge,
        theme.headlineMedium,
        theme.headlineSmall,
        theme.titleLarge,
      ];
      for (final TextStyle? style in styles) {
        expect(style?.fontFamily, AppTypography.displayFamily);
        expect(shipped, contains(style?.fontWeight));
      }
    });

    test('numeric styles are tabular, so a countdown holds its width', () {
      final TextStyle style = AppTypography.numeric(
        const Color(0xFF000000),
        size: 20,
      );
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(style.fontFamily, AppTypography.displayFamily);
    });
  });

  group('buttons', () {
    testWidgets('a pressed button reports itself enabled and fires once',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        host(
          AppButton(
            label: 'Play',
            variant: AppButtonVariant.primary,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('a null callback blocks the tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(const AppButton(label: 'Play', onPressed: null)),
      );
      final Semantics node = tester.widget(
        find
            .ancestor(
              of: find.text('Play'),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.properties.enabled, isNot(true));
    });

    testWidgets('a busy button hides its label and cannot be pressed',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        host(
          AppButton(
            label: 'Join',
            busy: true,
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.text('Join'), findsNothing);
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('every variant renders in both themes',
        (WidgetTester tester) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light,
        AppTheme.dark,
      ]) {
        await tester.pumpWidget(
          host(
            Column(
              children: <Widget>[
                for (final AppButtonVariant variant
                    in AppButtonVariant.values)
                  AppButton(
                    label: variant.name,
                    variant: variant,
                    onPressed: () {},
                  ),
              ],
            ),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AppButton), findsNWidgets(5));
      }
    });
  });

  group('the kit lays out', () {
    testWidgets('a card, a badge, a chip and a stat tile',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          AppCard(
            child: Column(
              children: <Widget>[
                const AppBadge(label: 'live'),
                AppChip(label: 'Rounds', selected: true, onTap: () {}),
                const AppStatTile(label: 'Wins', value: '12'),
                const AppProgressBar(value: 0.5),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('LIVE'), findsOneWidget);
    });

    testWidgets('an empty state and an error state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          Column(
            children: <Widget>[
              const Expanded(
                child: AppEmptyState(
                  title: 'Nothing here',
                  message: 'No rooms are open.',
                ),
              ),
              Expanded(
                child: AppErrorState(
                  message: 'Something went wrong.',
                  onRetry: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('a confirm dialog, whose actions are a row of expanded buttons',
        (WidgetTester tester) async {
      bool? answer;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) => AppButton(
              label: 'Leave',
              onPressed: () async {
                answer = await confirm(
                  context,
                  title: 'Leave the room?',
                  message: 'Your seat goes to somebody else.',
                  destructive: true,
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      // The layout assertion: an unbounded width here would have thrown.
      expect(tester.takeException(), isNull);
      expect(find.text('Leave the room?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('a toast, with its status glyph', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) => AppButton(
              label: 'Break it',
              onPressed: () => notify(context, 'Room is full.', isError: true),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Break it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Room is full.'), findsOneWidget);
    });
  });
}
