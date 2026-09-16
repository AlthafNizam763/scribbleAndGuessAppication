import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/models/words/fallback_words.dart';

/// Every word available for one [AppLanguage], grouped by [WordCategory].
///
/// A bank is immutable data: it is parsed once from `assets/words/words_*.json`
/// by [WordBankLoader] and then queried by the word selector to build the
/// choices offered to a drawer.
class WordBank {
  /// Creates a bank holding [byCategory] for [language].
  const WordBank({required this.language, required this.byCategory});

  /// Builds a bank from the asset shape
  /// `{"language": "en", "categories": {"<category>": {"easy": [...]}}}`.
  ///
  /// Parsing is defensive: unknown category keys, unknown difficulty keys,
  /// non-list values and blank words are skipped instead of throwing, so a
  /// partially broken asset still yields every word it got right.
  factory WordBank.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> categories = asMap(json['categories']);
    final Map<WordCategory, List<WordItem>> byCategory =
        <WordCategory, List<WordItem>>{};
    for (final MapEntry<String, dynamic> categoryEntry in categories.entries) {
      final WordCategory? category =
          asEnum(WordCategory.values, categoryEntry.key);
      if (category == null) {
        continue;
      }
      final List<WordItem> words =
          byCategory.putIfAbsent(category, () => <WordItem>[]);
      final Map<String, dynamic> groups = asMap(categoryEntry.value);
      for (final MapEntry<String, dynamic> groupEntry in groups.entries) {
        final WordDifficulty? difficulty =
            asEnum(WordDifficulty.values, groupEntry.key);
        if (difficulty == null) {
          continue;
        }
        for (final String raw in asStringList(groupEntry.value)) {
          final String text = raw.trim();
          if (text.isEmpty) {
            continue;
          }
          words.add(
            WordItem(text: text, category: category, difficulty: difficulty),
          );
        }
      }
    }
    return WordBank(
      language: AppLanguage.fromName(asString(json['language'])),
      byCategory: byCategory,
    );
  }

  /// Language every word in this bank is written in.
  final AppLanguage language;

  /// Words of the bank, keyed by the category they belong to.
  final Map<WordCategory, List<WordItem>> byCategory;

  /// Total number of words held by the bank.
  int get length {
    int total = 0;
    for (final List<WordItem> words in byCategory.values) {
      total += words.length;
    }
    return total;
  }

  /// Every word of the bank, in canonical [WordCategory] order.
  List<WordItem> all() {
    final List<WordItem> out = <WordItem>[];
    for (final WordCategory category in WordCategory.values) {
      out.addAll(byCategory[category] ?? const <WordItem>[]);
    }
    return List<WordItem>.unmodifiable(out);
  }

  /// Words belonging to any of [categories], deduplicated by lowercase text.
  ///
  /// An empty set, or a set containing [WordCategory.random], selects every
  /// category. The result keeps canonical category order so word selection
  /// stays reproducible for a given seed.
  List<WordItem> wordsFor(Set<WordCategory> categories) {
    final bool everything =
        categories.isEmpty || categories.contains(WordCategory.random);
    final List<WordItem> out = <WordItem>[];
    final Set<String> seen = <String>{};
    for (final WordCategory category in WordCategory.values) {
      if (!everything && !categories.contains(category)) {
        continue;
      }
      for (final WordItem word in byCategory[category] ?? const <WordItem>[]) {
        if (seen.add(word.text.toLowerCase())) {
          out.add(word);
        }
      }
    }
    return List<WordItem>.unmodifiable(out);
  }

  /// Every word of difficulty [d], in canonical [WordCategory] order.
  List<WordItem> byDifficulty(WordDifficulty d) => List<WordItem>.unmodifiable(
        <WordItem>[
          for (final WordItem word in all())
            if (word.difficulty == d) word,
        ],
      );
}

/// Loads and caches the [WordBank] of each [AppLanguage].
///
/// Loading never throws: a missing or malformed asset is logged and answered
/// with [FallbackWords], so the game always has words to draw.
abstract final class WordBankLoader {
  /// Asset folder holding the bundled word lists.
  static const String assetFolder = 'assets/words';

  static final Map<AppLanguage, WordBank> _cache = <AppLanguage, WordBank>{};

  /// Asset key of the word list of [language].
  static String assetPath(AppLanguage language) =>
      '$assetFolder/words_${language.name}.json';

  /// Returns the bank of [language], parsing the asset on first use only.
  static Future<WordBank> load(AppLanguage language) async {
    final WordBank? cached = _cache[language];
    if (cached != null) {
      return cached;
    }
    final WordBank bank =
        await _parseAsset(language) ?? FallbackWords.bank(language);
    _cache[language] = bank;
    return bank;
  }

  /// Drops every cached bank. Intended for tests.
  static void clearCache() => _cache.clear();

  /// Seeds the cache with [bank] for [language]. Intended for tests.
  static void preload(AppLanguage language, WordBank bank) {
    _cache[language] = bank;
  }

  /// Reads and parses the asset of [language], or `null` when it is unusable.
  static Future<WordBank?> _parseAsset(AppLanguage language) async {
    final String path = assetPath(language);
    try {
      final String raw = await rootBundle.loadString(path);
      final WordBank bank = WordBank.fromJson(asMap(jsonDecode(raw)));
      if (bank.all().isEmpty) {
        AppLogger.w('Word asset $path holds no words; using fallback words.');
        return null;
      }
      return bank;
    } catch (error, stackTrace) {
      AppLogger.w(
        'Could not load word asset $path; using fallback words.',
        error,
        stackTrace,
      );
      return null;
    }
  }
}
