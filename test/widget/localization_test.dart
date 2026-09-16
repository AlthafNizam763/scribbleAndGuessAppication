import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/i18n/translations/ar.dart';
import 'package:scribble_guess/core/i18n/translations/en.dart';
import 'package:scribble_guess/core/i18n/translations/ml.dart';
import 'package:scribble_guess/core/widgets/sketch_scaffold.dart';
import 'package:scribble_guess/models/enums.dart';

/// The localisation wiring in `ScribbleGuessApp`.
///
/// ## Why this is a widget test and not a unit test
///
/// `AppLanguage.isRtl` is already unit-tested, but it is not what decides the
/// layout — the framework is. Text direction comes from
/// `GlobalWidgetsLocalizations`, resolved from the locale `MaterialApp` was
/// given, and an app that named Arabic in `supportedLocales` without loading
/// those delegates would compile, pass every unit test, and then either lay
/// out left-to-right or assert the first time a widget asked for a tooltip.
///
/// So this pumps the same three delegates and the same `supportedLocales` the
/// app installs, and asks the framework what it concluded.
void main() {
  /// Mirrors the configuration in `lib/app/app.dart`.
  Widget appWith(AppLanguage language, {required Widget child}) => MaterialApp(
        locale: language.locale,
        supportedLocales:
            AppLanguage.values.map((AppLanguage l) => l.locale).toList(),
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppTextDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      );

  testWidgets('Arabic lays out right to left', (WidgetTester tester) async {
    late TextDirection direction;

    await tester.pumpWidget(
      appWith(
        AppLanguage.ar,
        child: Builder(
          builder: (BuildContext context) {
            direction = Directionality.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(direction, TextDirection.rtl);
  });

  testWidgets('every other language lays out left to right',
      (WidgetTester tester) async {
    for (final AppLanguage language in AppLanguage.values) {
      if (language == AppLanguage.ar) continue;

      late TextDirection direction;

      await tester.pumpWidget(
        appWith(
          language,
          child: Builder(
            builder: (BuildContext context) {
              direction = Directionality.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        direction,
        TextDirection.ltr,
        reason: '${language.name} laid out the wrong way',
      );
    }
  });

  /// The failure this guards against is silent: a locale the delegates do not
  /// carry is skipped, `MaterialLocalizations` is then missing, and the first
  /// widget that wants a tooltip or a date throws — at runtime, on a player's
  /// phone, in the one language nobody on the team tested.
  testWidgets('every offered language resolves real Material strings',
      (WidgetTester tester) async {
    for (final AppLanguage language in AppLanguage.values) {
      late String okLabel;

      await tester.pumpWidget(
        appWith(
          language,
          child: Builder(
            builder: (BuildContext context) {
              okLabel = MaterialLocalizations.of(context).okButtonLabel;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        okLabel,
        isNotEmpty,
        reason: '${language.name} has no Material localizations',
      );
    }
  });

  /// The end-to-end proof: the same widget, two locales, two languages of
  /// copy. Everything else in this suite tests a map or a rule; this tests
  /// that the delegate is wired into the tree the way `ScribbleGuessApp` wires
  /// it, and that `context.l10n` resolves through it.
  testWidgets('context.l10n follows the locale', (WidgetTester tester) async {
    Widget probe(AppLanguage language) => appWith(
          language,
          child: Builder(
            builder: (BuildContext context) => Text(
              context.l10n.lobbyStart,
              textDirection: TextDirection.ltr,
            ),
          ),
        );

    await tester.pumpWidget(probe(AppLanguage.en));
    expect(find.text('Start game'), findsOneWidget);

    await tester.pumpWidget(probe(AppLanguage.ml));
    expect(find.text(mlStrings['lobbyStart']!), findsOneWidget);
    expect(find.text('Start game'), findsNothing);

    await tester.pumpWidget(probe(AppLanguage.ar));
    expect(find.text(arStrings['lobbyStart']!), findsOneWidget);
  });

  /// A string the brand deliberately does not translate still renders, rather
  /// than falling through to its own key.
  testWidgets('an untranslated key renders English, not the key',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      appWith(
        AppLanguage.ja,
        child: Builder(
          builder: (BuildContext context) => Text(
            context.l10n.appName,
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    expect(find.text('Scribble & Guess'), findsOneWidget);
  });

  /// Error text is built where there is no context, so it travels as English
  /// and is translated by the widget that shows it.
  testWidgets('SketchEmptyState localises an English failure message',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      appWith(
        AppLanguage.ml,
        child: Scaffold(
          body: SketchEmptyState(message: enStrings['errorRoomFull']!),
        ),
      ),
    );

    expect(find.text(mlStrings['errorRoomFull']!), findsOneWidget);
  });
}
