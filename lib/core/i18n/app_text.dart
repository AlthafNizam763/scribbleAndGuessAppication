import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';
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
import 'package:scribble_guess/core/utils/time_utils.dart';
import 'package:scribble_guess/models/enums.dart';

part 'app_text.g.dart';

/// Every UI string, in the language the player chose.
///
/// ## How a string is found
///
/// Catalogues are keyed by `AppStrings` member name — `'lobbyStart'`, not
/// `'Start game'`. Keying by the English text would have been less code, but
/// this app has duplicate English values (`Clear` is a canvas action and a
/// filter; `Chat` is a panel and a setting), and collapsing them would force
/// one translation onto two different senses. Names also mean an edit to the
/// English copy does not silently orphan nine translations.
///
/// ## What happens when a translation is missing
///
/// It falls back to English, key by key. That is not a degraded mode to be
/// fixed later — it is the mechanism that lets a new string ship in one
/// language and appear everywhere immediately, and it is why adding to
/// `AppStrings` can never break a language.
///
/// ## Why this is a `Localizations` delegate
///
/// Because it makes the language reactive for free. A widget that reads
/// `context.l10n` registers an inherited-widget dependency, so changing the
/// setting rebuilds exactly the widgets that display text — no manual
/// invalidation, and no risk of a screen deeper in the stack keeping stale
/// copy. It also works in `StatelessWidget`s that have no Riverpod `ref`.
@immutable
class AppText with GeneratedText {
  /// Creates the text for [language].
  AppText(this.language) : _strings = _catalogueFor(language);

  /// The language these strings are in.
  final AppLanguage language;

  final Map<String, String> _strings;

  /// English, with the parameterised patterns folded in.
  ///
  /// The final fallback for every lookup, which is why it is the one map that
  /// has to be complete.
  static final Map<String, String> _english = <String, String>{
    ...enStrings,
    ...enPatterns,
  };

  /// Every English value mapped back to its key.
  ///
  /// Only used by [fromEnglish]; see the note there. Duplicate English values
  /// collapse onto whichever key was declared last, which is harmless because
  /// the two keys have the same English text and therefore the same intended
  /// meaning at the point this is used.
  static final Map<String, String> _keyOfEnglish = <String, String>{
    for (final MapEntry<String, String> entry in enStrings.entries)
      entry.value: entry.key,
  };

  static Map<String, String> _catalogueFor(AppLanguage language) =>
      switch (language) {
        AppLanguage.en => _english,
        AppLanguage.ml => mlStrings,
        AppLanguage.hi => hiStrings,
        AppLanguage.ta => taStrings,
        AppLanguage.ar => arStrings,
        AppLanguage.de => deStrings,
        AppLanguage.ja => jaStrings,
        AppLanguage.ru => ruStrings,
        AppLanguage.es => esStrings,
        AppLanguage.fr => frStrings,
      };

  /// Resolves [key], falling back to English and then to the key itself.
  ///
  /// Returning the key rather than throwing is deliberate: a missing string is
  /// a copy bug, and a screen that renders `lobbyStart` is debuggable, while a
  /// screen that crashed is not.
  @override
  String lookUp(String key) => _strings[key] ?? _english[key] ?? key;

  /// Translates text that was produced outside the widget tree.
  ///
  /// Error messages are built deep in the stack — in `Failure`, in the socket
  /// repositories, in the validators — where there is no `BuildContext` to
  /// localise against, so they travel as English and are translated here, at
  /// the point something renders them.
  ///
  /// Text this does not recognise comes back unchanged, which is right for the
  /// two cases that produce it: a server message the app did not author, and a
  /// string that was interpolated before it got here.
  String fromEnglish(String english) {
    final String? key = _keyOfEnglish[english];
    return key == null ? english : lookUp(key);
  }

  /// Substitutes `{name}`-style placeholders into the pattern at [key].
  String _fill(String key, Map<String, Object?> values) {
    String out = lookUp(key);
    for (final MapEntry<String, Object?> value in values.entries) {
      out = out.replaceAll('{${value.key}}', '${value.value}');
    }
    return out;
  }

  /// Picks the plural form of [base] for [count] and fills in `{n}`.
  ///
  /// Falls through the language's own category, then its `other`, then
  /// English's — so a catalogue that declares only `one` and `other` still
  /// answers correctly when asked for `few`.
  String _plural(String base, int count) {
    final PluralCategory category = pluralCategory(language, count);

    final String pattern = _strings['$base.${category.name}'] ??
        _strings['$base.other'] ??
        _english['$base.${category.name}'] ??
        _english['$base.other'] ??
        base;

    return pattern.replaceAll('{n}', '$count');
  }

  // --- Counts --------------------------------------------------------------

  /// Pluralised player count, such as `3 players`.
  String playersCount(int n) => _plural('playersCount', n);

  /// Pluralised round count, such as `3 rounds`.
  String roundsCount(int n) => _plural('roundsCount', n);

  /// Pluralised point count, such as `120 points`.
  String pointsCount(int n) => _plural('pointsCount', n);

  /// Pluralised hint count, such as `2 hints`.
  String hintsCount(int n) => _plural('hintsCount', n);

  /// Pluralised word count, such as `7 words`.
  String wordsCount(int n) => _plural('wordsCount', n);

  /// Pluralised finished-match count, such as `9 games`.
  String gamesCount(int n) => _plural('gamesCount', n);

  /// Pluralised win count, such as `2 wins`.
  String winsCount(int n) => _plural('winsCount', n);

  /// Pluralised letter count, such as `6 letters`.
  String lettersCount(int n) => _plural('lettersCount', n);

  /// Duration setting value, such as `80 seconds`.
  String secondsValue(int n) => _plural('secondsValue', n);

  /// Seat usage of a room, such as `4/8 players`.
  String playersOfMax(int n, int max) =>
      _fill('playersOfMax', <String, Object?>{'n': n, 'max': max});

  /// Signed score delta, such as `+120`.
  ///
  /// Not translated, and not a pattern: it is a number with a sign, and every
  /// language writes it the same way.
  String pointsDelta(int n) => n >= 0 ? '+$n' : '$n';

  // --- Match ---------------------------------------------------------------

  /// Progress label of a match, such as `Round 2 of 3`.
  String roundOf(int current, int total) =>
      _fill('roundOf', <String, Object?>{'current': current, 'total': total});

  /// Turn heading, such as `Anna is drawing`.
  String isDrawing(String name) =>
      _fill('isDrawing', <String, Object?>{'name': name});

  /// Countdown before a turn starts, such as `Starting in 3`.
  String startingIn(int seconds) =>
      _fill('startingIn', <String, Object?>{'seconds': seconds});

  /// Reveal of the secret word, such as `The word was banana`.
  String wordWas(String word) =>
      _fill('wordWas', <String, Object?>{'word': word});

  /// System chat line for a correct guess.
  String guessedTheWord(String name) =>
      _fill('guessedTheWord', <String, Object?>{'name': name});

  /// System chat line for a player joining.
  String playerJoined(String name) =>
      _fill('playerJoined', <String, Object?>{'name': name});

  /// System chat line for a player leaving.
  String playerLeft(String name) =>
      _fill('playerLeft', <String, Object?>{'name': name});

  /// System chat line for a host change.
  String hostIsNow(String name) =>
      _fill('hostIsNow', <String, Object?>{'name': name});

  /// System chat line for a kicked player.
  String playerKicked(String name) =>
      _fill('playerKicked', <String, Object?>{'name': name});

  /// System chat line for a banned player.
  String playerBanned(String name) =>
      _fill('playerBanned', <String, Object?>{'name': name});

  /// Vote-kick progress, such as `Kick Anna? 2/4 votes`.
  String voteKickProgress(String name, int votes, int needed) => _fill(
        'voteKickProgress',
        <String, Object?>{'name': name, 'votes': votes, 'needed': needed},
      );

  /// Somebody is composing a message.
  String chatTypingOne(String name) =>
      _fill('chatTypingOne', <String, Object?>{'name': name});

  // --- Results and progression ---------------------------------------------

  /// Placement line on the results screen, such as `2nd place`.
  ///
  /// English gets its ordinal suffix; every other language receives the bare
  /// number and expresses rank in its own pattern. See [englishOrdinal].
  String placement(int rank) => _fill('placement', <String, Object?>{
        'rank': language == AppLanguage.en ? englishOrdinal(rank) : '$rank',
      });

  /// Subtitle under a result heading, such as `Classic · 3 rounds`.
  String resultSubtitle(String mode, int rounds) => _fill(
        'resultSubtitle',
        <String, Object?>{'mode': mode, 'rounds': roundsCount(rounds)},
      );

  /// Caption of a replay, such as `Round 2 · Anna`.
  String replayRoundLabel(int round, String drawer) => _fill(
        'replayRoundLabel',
        <String, Object?>{'round': round, 'drawer': drawer},
      );

  /// Trophy-case progress, such as `7 of 12 unlocked`.
  String achievementsUnlockedOf(int unlocked, int total) => _fill(
        'achievementsUnlockedOf',
        <String, Object?>{'unlocked': unlocked, 'total': total},
      );

  /// XP a match paid, such as `+40 XP`.
  String progressionXpEarned(int xp) =>
      _fill('progressionXpEarned', <String, Object?>{'xp': xp});

  /// Level-up banner, such as `Level 7 — Sketcher`.
  String progressionLevelUp(int level, String title) => _fill(
        'progressionLevelUp',
        <String, Object?>{'level': level, 'title': title},
      );

  // --- Social and chrome ---------------------------------------------------

  /// Confirmation body for removing a friend.
  String friendRemoveBody(String name) =>
      _fill('friendRemoveBody', <String, Object?>{'name': name});

  /// Invite text shared from the lobby.
  String inviteMessage(String code) =>
      _fill('inviteMessage', <String, Object?>{'code': code});

  /// Version row value, such as `Version 1.0.0`.
  String versionLabel(String version) =>
      _fill('versionLabel', <String, Object?>{'version': version});

  /// Retry countdown of the reconnect banner.
  String reconnectingIn(int seconds) =>
      _fill('reconnectingIn', <String, Object?>{'seconds': seconds});

  /// The age of [epochMs] relative to [nowMs], such as `5m` or `now`.
  ///
  /// `TimeUtils` does the arithmetic; this dresses the result, so a language
  /// that spells its units differently can, and one that puts the unit before
  /// the number can too, by carrying `{n}` in the suffix entry.
  String relativeShort(int epochMs, int nowMs) {
    final ({int value, String suffixKey}) parts =
        TimeUtils.relativeParts(epochMs, nowMs);
    if (parts.value <= 0) return timeNow;

    final String suffix = lookUp(parts.suffixKey);
    return suffix.contains('{n}')
        ? suffix.replaceAll('{n}', '${parts.value}')
        : '${parts.value}$suffix';
  }

}

/// Installs [AppText] into the widget tree.
///
/// Resolves synchronously because every catalogue is compiled in: there is no
/// asset to read and no frame where the app would have no strings.
class AppTextDelegate extends LocalizationsDelegate<AppText> {
  /// Creates the delegate.
  const AppTextDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLanguage.values.any((AppLanguage l) => l.name == locale.languageCode);

  @override
  Future<AppText> load(Locale locale) => SynchronousFuture<AppText>(
        AppText(AppLanguage.fromName(locale.languageCode)),
      );

  @override
  bool shouldReload(AppTextDelegate old) => false;
}

/// Reaches the active [AppText].
extension AppTextContext on BuildContext {
  /// The UI strings for the language in force here.
  ///
  /// Falls back to English when no delegate is installed rather than throwing,
  /// so a widget test that pumps a bare `MaterialApp` still renders real copy
  /// instead of failing on a null. Production always has the delegate — it is
  /// installed in `ScribbleGuessApp`.
  AppText get l10n =>
      Localizations.of<AppText>(this, AppText) ?? AppText(AppLanguage.en);
}
