import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/i18n/plural_rules.dart';
import 'package:scribble_guess/core/i18n/translations/ar.dart';
import 'package:scribble_guess/core/i18n/translations/de.dart';
import 'package:scribble_guess/core/i18n/translations/en.dart';
import 'package:scribble_guess/core/i18n/translations/en_patterns.dart';
import 'package:scribble_guess/core/i18n/translations/es.dart';
import 'package:scribble_guess/core/i18n/translations/fr.dart';
import 'package:scribble_guess/core/i18n/translations/hi.dart';
import 'package:scribble_guess/core/i18n/translations/ja.dart';
import 'package:scribble_guess/core/i18n/translations/ml.dart';
import 'package:scribble_guess/core/i18n/translations/ru.dart';
import 'package:scribble_guess/core/i18n/translations/ta.dart';
import 'package:scribble_guess/models/enums.dart';

/// The translation catalogues and the plural rules.
///
/// ## What is actually checkable here
///
/// Not whether a translation is *good* — no test can tell you that, and the
/// quality of this app's Malayalam is a question for a Malayalam speaker. What
/// a test can pin down is everything structural, and those are the failures
/// that would ship silently:
///
/// - a key that is in no catalogue at all, so it renders as its own name;
/// - a key misspelled in one language, so that language quietly falls back to
///   English for one string and nobody notices;
/// - a pattern that lost its `{name}` placeholder in translation, so the
///   player's name never appears;
/// - a plural family missing a category its language needs.
void main() {
  final Map<AppLanguage, Map<String, String>> catalogues =
      <AppLanguage, Map<String, String>>{
    AppLanguage.ml: mlStrings,
    AppLanguage.hi: hiStrings,
    AppLanguage.ta: taStrings,
    AppLanguage.ar: arStrings,
    AppLanguage.de: deStrings,
    AppLanguage.ja: jaStrings,
    AppLanguage.ru: ruStrings,
    AppLanguage.es: esStrings,
    AppLanguage.fr: frStrings,
  };

  /// Every key English defines, which is the set a catalogue may draw from.
  final Set<String> englishKeys = <String>{
    ...enStrings.keys,
    ...enPatterns.keys,
  };

  /// Plural families, as base name -> the categories English declares.
  final Set<String> pluralBases = <String>{
    for (final String key in enPatterns.keys)
      if (key.contains('.')) key.split('.').first,
  };

  group('catalogue integrity', () {
    /// The one that catches a typo. A key that English does not define can
    /// never be looked up, so it is dead weight that also hides the fact that
    /// the string it was meant for is still English.
    test('no catalogue invents a key English does not have', () {
      for (final MapEntry<AppLanguage, Map<String, String>> entry
          in catalogues.entries) {
        for (final String key in entry.value.keys) {
          final String base = key.contains('.') ? key.split('.').first : key;
          final bool known =
              englishKeys.contains(key) || pluralBases.contains(base);

          expect(
            known,
            isTrue,
            reason: '${entry.key.name}.dart declares unknown key "$key"',
          );
        }
      }
    });

    test('no catalogue entry is blank', () {
      for (final MapEntry<AppLanguage, Map<String, String>> entry
          in catalogues.entries) {
        for (final MapEntry<String, String> row in entry.value.entries) {
          expect(
            row.value.trim(),
            isNotEmpty,
            reason: '${entry.key.name}.dart has an empty value for "${row.key}"',
          );
        }
      }
    });

    /// A pattern whose placeholder was dropped in translation compiles, passes
    /// every other check, and then renders "is drawing" with no name.
    ///
    /// Plural forms are checked more loosely on purpose. English writes its
    /// singular out in full — `1 player`, not `{n} player` — because that is
    /// what reads well, but Russian's `one` form covers 1, 21 and 101 and so
    /// *must* carry `{n}`. Comparing a plural form against English's
    /// placeholders would therefore fail on a correct translation. What still
    /// holds is that a plural form may use no placeholder other than `{n}`.
    test('every translated pattern keeps its placeholders', () {
      final RegExp placeholder = RegExp(r'\{(\w+)\}');

      Set<String> placeholdersIn(String text) => placeholder
          .allMatches(text)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      for (final MapEntry<AppLanguage, Map<String, String>> entry
          in catalogues.entries) {
        for (final MapEntry<String, String> row in entry.value.entries) {
          final bool isPluralForm = row.key.contains('.') &&
              pluralBases.contains(row.key.split('.').first);

          if (isPluralForm) {
            expect(
              placeholdersIn(row.value).difference(<String>{'n'}),
              isEmpty,
              reason:
                  '${entry.key.name}.dart "${row.key}" may only use {n}',
            );
            continue;
          }

          final String? english = enPatterns[row.key];
          if (english == null) continue;

          expect(
            placeholdersIn(row.value),
            placeholdersIn(english),
            reason: '${entry.key.name}.dart "${row.key}" lost a placeholder',
          );
        }
      }
    });

    /// A plural family must cover every category its own language can produce.
    ///
    /// Not "must declare `.other`": Russian has no `other` category for whole
    /// numbers at all — `one`, `few` and `many` between them cover every
    /// integer — so demanding one would be demanding a form the language does
    /// not have. What matters is that no reachable category is missing, since
    /// a missing one falls back to English in the middle of a Russian
    /// sentence.
    test('every plural family covers the categories its language produces', () {
      for (final MapEntry<AppLanguage, Map<String, String>> entry
          in catalogues.entries) {
        // The categories this language actually reaches. Derived from the
        // rules rather than hard-coded, so adding a language needs no edit.
        final Set<PluralCategory> reachable = <PluralCategory>{
          for (int n = 0; n <= 200; n += 1) pluralCategory(entry.key, n),
        };

        final Set<String> declared = <String>{
          for (final String key in entry.value.keys)
            if (key.contains('.') && pluralBases.contains(key.split('.').first))
              key.split('.').first,
        };

        for (final String base in declared) {
          for (final PluralCategory category in reachable) {
            expect(
              entry.value.containsKey('$base.${category.name}'),
              isTrue,
              reason: '${entry.key.name}.dart "$base" is missing '
                  '".${category.name}"',
            );
          }
        }
      }
    });
  });

  group('lookup and fallback', () {
    test('English resolves every key it declares', () {
      final AppText text = AppText(AppLanguage.en);

      for (final String key in enStrings.keys) {
        expect(text.lookUp(key), enStrings[key]);
      }
    });

    /// The fallback is the mechanism that lets a string ship before it is
    /// translated, so it is worth pinning rather than assuming.
    test('an untranslated key falls back to English, not to blank', () {
      for (final AppLanguage language in AppLanguage.values) {
        final AppText text = AppText(language);

        for (final String key in enStrings.keys) {
          final String value = text.lookUp(key);
          expect(value.trim(), isNotEmpty, reason: '$key in ${language.name}');
          // Falling back to the key itself is the debugging path, and must not
          // be reachable for a key English defines.
          expect(value, isNot(key), reason: '$key in ${language.name}');
        }
      }
    });

    test('an unknown key renders as itself rather than crashing', () {
      expect(AppText(AppLanguage.en).lookUp('notAKey'), 'notAKey');
    });

    test('fromEnglish translates text produced outside the widget tree', () {
      final AppText ml = AppText(AppLanguage.ml);

      expect(ml.fromEnglish(enStrings['errorRoomFull']!), mlStrings['errorRoomFull']);
      // Text it does not recognise is passed through, which is what a server
      // message needs.
      expect(ml.fromEnglish('a message we did not write'),
          'a message we did not write');
    });
  });

  group('plural rules', () {
    /// The CLDR cardinal categories, spot-checked at the boundaries that
    /// actually differ between these languages.
    test('English and the other two-form languages', () {
      for (final AppLanguage language in <AppLanguage>[
        AppLanguage.en,
        AppLanguage.de,
        AppLanguage.es,
        AppLanguage.ml,
        AppLanguage.ta,
      ]) {
        expect(pluralCategory(language, 0), PluralCategory.other);
        expect(pluralCategory(language, 1), PluralCategory.one);
        expect(pluralCategory(language, 2), PluralCategory.other);
      }
    });

    test('French and Hindi treat zero as singular', () {
      for (final AppLanguage language in <AppLanguage>[
        AppLanguage.fr,
        AppLanguage.hi,
      ]) {
        expect(pluralCategory(language, 0), PluralCategory.one);
        expect(pluralCategory(language, 1), PluralCategory.one);
        expect(pluralCategory(language, 2), PluralCategory.other);
      }
    });

    test('Japanese has a single form', () {
      for (final int n in <int>[0, 1, 2, 5, 11, 100]) {
        expect(pluralCategory(AppLanguage.ja, n), PluralCategory.other);
      }
    });

    /// Russian is where a naive `n == 1` rule goes visibly wrong: 21 is
    /// singular, 11 is not, and 2–4 have a form of their own.
    test('Russian has one, few and many', () {
      expect(pluralCategory(AppLanguage.ru, 1), PluralCategory.one);
      expect(pluralCategory(AppLanguage.ru, 21), PluralCategory.one);
      expect(pluralCategory(AppLanguage.ru, 101), PluralCategory.one);
      expect(pluralCategory(AppLanguage.ru, 11), PluralCategory.many);
      expect(pluralCategory(AppLanguage.ru, 2), PluralCategory.few);
      expect(pluralCategory(AppLanguage.ru, 24), PluralCategory.few);
      expect(pluralCategory(AppLanguage.ru, 12), PluralCategory.many);
      expect(pluralCategory(AppLanguage.ru, 5), PluralCategory.many);
      expect(pluralCategory(AppLanguage.ru, 0), PluralCategory.many);
    });

    test('Arabic uses all six', () {
      expect(pluralCategory(AppLanguage.ar, 0), PluralCategory.zero);
      expect(pluralCategory(AppLanguage.ar, 1), PluralCategory.one);
      expect(pluralCategory(AppLanguage.ar, 2), PluralCategory.two);
      expect(pluralCategory(AppLanguage.ar, 3), PluralCategory.few);
      expect(pluralCategory(AppLanguage.ar, 10), PluralCategory.few);
      expect(pluralCategory(AppLanguage.ar, 11), PluralCategory.many);
      expect(pluralCategory(AppLanguage.ar, 99), PluralCategory.many);
      expect(pluralCategory(AppLanguage.ar, 100), PluralCategory.other);
    });

    test('English ordinals, including the teens', () {
      expect(englishOrdinal(1), '1st');
      expect(englishOrdinal(2), '2nd');
      expect(englishOrdinal(3), '3rd');
      expect(englishOrdinal(4), '4th');
      expect(englishOrdinal(11), '11th');
      expect(englishOrdinal(12), '12th');
      expect(englishOrdinal(13), '13th');
      expect(englishOrdinal(21), '21st');
      expect(englishOrdinal(112), '112th');
    });
  });

  group('formatting', () {
    test('counts pick the right form and carry the number', () {
      final AppText en = AppText(AppLanguage.en);

      expect(en.playersCount(1), '1 player');
      expect(en.playersCount(4), '4 players');
      expect(en.roundsCount(3), '3 rounds');
    });

    /// A language that declares only `one` and `other` must still answer when
    /// the rules ask it for `few` — which they never will for Malayalam, but
    /// the fallback chain is what makes that safe rather than lucky.
    test('a count resolves in every language', () {
      for (final AppLanguage language in AppLanguage.values) {
        for (final int n in <int>[0, 1, 2, 5, 11, 21, 100]) {
          final String value = AppText(language).playersCount(n);
          expect(value.trim(), isNotEmpty);
          expect(value, isNot(contains('{n}')));
        }
      }
    });

    test('placeholders are filled, not left in the string', () {
      final AppText en = AppText(AppLanguage.en);

      expect(en.isDrawing('Anna'), 'Anna is drawing');
      expect(en.roundOf(2, 3), 'Round 2 of 3');
      expect(en.voteKickProgress('Anna', 2, 4), 'Kick Anna? 2/4 votes');
      expect(en.versionLabel('1.0.0'), 'Version 1.0.0');
    });

    /// English gets its ordinal suffix; everybody else gets the bare number in
    /// their own phrasing, because `2nd` is not a thing you can build in most
    /// languages by appending to a digit.
    test('placement uses an ordinal only in English', () {
      expect(AppText(AppLanguage.en).placement(2), '2nd place');
      expect(AppText(AppLanguage.ja).placement(2), isNot(contains('nd')));
    });

    test('pointsDelta signs the number', () {
      final AppText en = AppText(AppLanguage.en);

      expect(en.pointsDelta(120), '+120');
      expect(en.pointsDelta(0), '+0');
      expect(en.pointsDelta(-30), '-30');
    });
  });

  /// The multi-line privacy notice is the one string with real escape
  /// sequences in it, and a generator that re-escaped them would turn its
  /// newlines into visible backslashes.
  test('the location notice keeps real newlines', () {
    expect(enStrings['locationNoticeBody'], contains('\n'));
    expect(enStrings['locationNoticeBody'], isNot(contains(r'\n')));
  });
}
