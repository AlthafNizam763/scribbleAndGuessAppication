import 'dart:math';

import 'package:scribble_guess/core/constants/game_defaults.dart';

/// How a chat message compares to the secret word.
enum GuessVerdict {
  /// The guess matches the word exactly, once normalized.
  correct,

  /// The guess is one letter away from the word.
  close,

  /// The guess is not the word.
  wrong,
}

/// Compares a guess against the secret word.
///
/// Both sides are normalized first — case, accents and stray whitespace are
/// irrelevant — so `Crème  Brûlée` matches `creme brulee`. Pure and
/// deterministic; the server runs the very same rules.
abstract final class GuessMatcher {
  /// Grades [guess] against [word].
  ///
  /// A blank guess or a blank word is always [GuessVerdict.wrong]. A guess is
  /// [GuessVerdict.close] when the word is at least
  /// `GameDefaults.closeGuessMinLength` characters long and exactly one edit
  /// away, which is what earns the "so close!" chat line.
  static GuessVerdict evaluate(String guess, String word) {
    final String normalizedGuess = normalize(guess);
    final String normalizedWord = normalize(word);
    if (normalizedGuess.isEmpty || normalizedWord.isEmpty) {
      return GuessVerdict.wrong;
    }
    if (normalizedGuess == normalizedWord) {
      return GuessVerdict.correct;
    }
    if (normalizedWord.length >= GameDefaults.closeGuessMinLength &&
        levenshtein(normalizedGuess, normalizedWord) == 1) {
      return GuessVerdict.close;
    }
    return GuessVerdict.wrong;
  }

  /// The canonical form of [value] used for every comparison.
  ///
  /// Lower-cases, folds Latin-1 accents (plus `ñ`, `ç`, the umlauts and
  /// `ß` -> `ss`), collapses runs of whitespace to a single space and trims
  /// the ends.
  static String normalize(String value) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in value.toLowerCase().runes) {
      final String char = String.fromCharCode(rune);
      buffer.write(_accentFolding[char] ?? char);
    }
    return buffer.toString().replaceAll(_whitespace, ' ').trim();
  }

  /// The Levenshtein edit distance between [a] and [b].
  ///
  /// Iterative and two-row, so memory stays at `O(min(a.length, b.length))`
  /// however long the strings are.
  static int levenshtein(String a, String b) {
    if (a == b) {
      return 0;
    }
    if (a.isEmpty) {
      return b.length;
    }
    if (b.isEmpty) {
      return a.length;
    }
    final bool aIsLonger = a.length >= b.length;
    final String rows = aIsLonger ? a : b;
    final String columns = aIsLonger ? b : a;
    final int width = columns.length;
    List<int> previous = List<int>.generate(width + 1, (int i) => i);
    List<int> current = List<int>.filled(width + 1, 0);
    for (int i = 1; i <= rows.length; i++) {
      current[0] = i;
      final int rowUnit = rows.codeUnitAt(i - 1);
      for (int j = 1; j <= width; j++) {
        final int cost = rowUnit == columns.codeUnitAt(j - 1) ? 0 : 1;
        final int substitution = previous[j - 1] + cost;
        final int deletion = previous[j] + 1;
        final int insertion = current[j - 1] + 1;
        current[j] = min(substitution, min(deletion, insertion));
      }
      final List<int> swap = previous;
      previous = current;
      current = swap;
    }
    return previous[width];
  }

  /// One or more whitespace characters.
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Accent folding for the Latin-1 letters the word banks use.
  static const Map<String, String> _accentFolding = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'æ': 'ae',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ð': 'd',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ø': 'o',
    'œ': 'oe',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'þ': 'th',
    'ß': 'ss',
  };
}
