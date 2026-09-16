import 'package:scribble_guess/models/enums.dart';

/// The CLDR plural categories this app uses.
///
/// Not every language uses every one: English needs two, Japanese needs one,
/// Arabic needs all six. A catalogue only ever declares the categories its own
/// language has, and [pluralCategory] only ever asks for one that language can
/// produce.
enum PluralCategory {
  /// Arabic's dedicated zero form.
  zero,

  /// The singular.
  one,

  /// Arabic's dual.
  two,

  /// Russian's 2–4 form; Arabic's 3–10 form.
  few,

  /// Russian's 5+ form; Arabic's 11–99 form.
  many,

  /// The catch-all, and the only form in Japanese.
  other,
}

/// Which plural form [count] takes in [language].
///
/// ## Why this is hand-written rather than pulled from `intl`
///
/// `intl` carries the whole CLDR table for every locale on earth, and the app
/// needs ten languages and integer counts only. These are the CLDR cardinal
/// rules for exactly those ten, simplified on one honest assumption: every
/// count in this app is an `int`, so the fractional part is always zero and
/// the `v = 0` branch of each rule is the only reachable one.
///
/// Getting this wrong is quiet rather than loud — Russian would read "5 очка"
/// instead of "5 очков", which is wrong in the way a native speaker notices
/// immediately and a test never would. Hence the table-driven cases in
/// `test/unit/i18n_test.dart` rather than trust.
PluralCategory pluralCategory(AppLanguage language, int count) {
  final int n = count.abs();

  switch (language) {
    // n = 1 is the singular; everything else, including zero, is plural.
    case AppLanguage.en:
    case AppLanguage.de:
    case AppLanguage.es:
    case AppLanguage.ml:
    case AppLanguage.ta:
      return n == 1 ? PluralCategory.one : PluralCategory.other;

    // French and Hindi both treat zero as singular.
    case AppLanguage.fr:
    case AppLanguage.hi:
      return n == 0 || n == 1 ? PluralCategory.one : PluralCategory.other;

    // Japanese does not inflect for number at all.
    case AppLanguage.ja:
      return PluralCategory.other;

    // Russian: one for 1, 21, 31…; few for 2–4, 22–24…; many for the rest,
    // with the teens excluded from both because 11–14 take `many`.
    case AppLanguage.ru:
      final int mod10 = n % 10;
      final int mod100 = n % 100;
      if (mod10 == 1 && mod100 != 11) return PluralCategory.one;
      if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
        return PluralCategory.few;
      }
      return PluralCategory.many;

    // Arabic uses all six.
    case AppLanguage.ar:
      if (n == 0) return PluralCategory.zero;
      if (n == 1) return PluralCategory.one;
      if (n == 2) return PluralCategory.two;
      final int mod100 = n % 100;
      if (mod100 >= 3 && mod100 <= 10) return PluralCategory.few;
      if (mod100 >= 11 && mod100 <= 99) return PluralCategory.many;
      return PluralCategory.other;
  }
}

/// The English ordinal for [n], such as `1st`, `2nd` or `13th`.
///
/// English only, and deliberately so. Ordinals are not a suffix you can bolt
/// onto a number in most languages — Japanese puts 位 after it, Arabic puts a
/// word before it, German writes `3.` — so every other language expresses rank
/// through its own `placement` pattern instead, which receives the bare
/// number. See `AppText.placement`.
String englishOrdinal(int n) {
  final int mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';

  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
