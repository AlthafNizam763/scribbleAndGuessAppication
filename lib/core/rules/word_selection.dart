import 'dart:math';

import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/models/word_item.dart';

/// Picks the words a drawer is offered at the start of a turn.
///
/// All randomness comes from the injected [random], so a seeded selector
/// always produces the same offer for the same inputs.
class WordSelector {
  /// Creates a selector driven by [random].
  const WordSelector(this.random);

  /// The only source of randomness in this class.
  final Random random;

  /// Returns [count] words for the drawer to choose from.
  ///
  /// The pool is filtered by the categories of [settings] — where
  /// [WordCategory.random] means "every category" — and words in [usedWords]
  /// are skipped case-insensitively. When that leaves too few candidates the
  /// constraints are relaxed in order: first [usedWords] is ignored, then the
  /// category filter, and finally the result is padded by repeating words.
  /// Custom word mode draws from `settings.customWords` instead.
  ///
  /// Never throws and never returns fewer than `min(count, pool.length)`
  /// items; an empty pool yields an empty list.
  List<WordItem> pickChoices({
    required List<WordItem> pool,
    required RoomSettings settings,
    required Set<String> usedWords,
    required int count,
  }) {
    if (count < 1) {
      return const <WordItem>[];
    }
    // A room that supplied its own words always draws from them; the word
    // mode only changes how the clue is shown, not where words come from.
    final bool isCustom = settings.customWords.isNotEmpty;
    final List<WordItem> source =
        isCustom ? _customPool(settings.customWords) : _cleanPool(pool);
    if (source.isEmpty) {
      return const <WordItem>[];
    }
    final Set<WordCategory>? categories =
        isCustom ? null : _categoryFilter(settings.categories);
    final Set<String> used = <String>{
      for (final String word in usedWords) _key(word),
    };

    List<WordItem> candidates =
        _filter(source, categories: categories, used: used);
    if (candidates.length < count) {
      candidates = _filter(source, categories: categories, used: const <String>{});
    }
    if (candidates.length < count) {
      candidates = source;
    }
    final List<WordItem> picked = _spread(candidates, count);
    _pad(picked, count);
    return picked;
  }

  /// Wraps raw custom words as medium, uncategorised word items.
  List<WordItem> _customPool(List<String> customWords) => <WordItem>[
        for (final String word in customWords)
          if (word.trim().isNotEmpty)
            WordItem(
              text: word.trim(),
              category: WordCategory.random,
              difficulty: WordDifficulty.medium,
            ),
      ];

  /// Drops blank entries from a word-bank pool.
  List<WordItem> _cleanPool(List<WordItem> pool) => <WordItem>[
        for (final WordItem item in pool)
          if (item.text.trim().isNotEmpty) item,
      ];

  /// The categories to keep, or `null` when every category is allowed.
  Set<WordCategory>? _categoryFilter(Set<WordCategory> categories) =>
      categories.isEmpty || categories.contains(WordCategory.random)
          ? null
          : categories;

  /// The entries of [source] passing the category and used-word filters.
  List<WordItem> _filter(
    List<WordItem> source, {
    required Set<WordCategory>? categories,
    required Set<String> used,
  }) =>
      <WordItem>[
        for (final WordItem item in source)
          if ((categories == null || categories.contains(item.category)) &&
              !used.contains(_key(item.text)))
            item,
      ];

  /// Draws up to [count] items from [candidates], round-robin over the
  /// difficulties so an offer mixes easy and hard words when it can.
  List<WordItem> _spread(List<WordItem> candidates, int count) {
    final Map<WordDifficulty, List<WordItem>> buckets =
        <WordDifficulty, List<WordItem>>{
      for (final WordDifficulty difficulty in WordDifficulty.values)
        difficulty: <WordItem>[],
    };
    for (final WordItem item in candidates) {
      buckets[item.difficulty]!.add(item);
    }
    for (final List<WordItem> bucket in buckets.values) {
      bucket.shuffle(random);
    }
    final List<WordItem> picked = <WordItem>[];
    bool progressed = true;
    while (picked.length < count && progressed) {
      progressed = false;
      for (final WordDifficulty difficulty in WordDifficulty.values) {
        if (picked.length >= count) {
          break;
        }
        final List<WordItem> bucket = buckets[difficulty]!;
        if (bucket.isNotEmpty) {
          picked.add(bucket.removeLast());
          progressed = true;
        }
      }
    }
    return picked;
  }

  /// Repeats [picked] in place until it holds [count] items.
  void _pad(List<WordItem> picked, int count) {
    if (picked.isEmpty || picked.length >= count) {
      return;
    }
    final int available = picked.length;
    for (int i = 0; picked.length < count; i++) {
      picked.add(picked[i % available]);
    }
  }

  /// The case- and whitespace-insensitive key of [word].
  static String _key(String word) => word.trim().toLowerCase();
}
