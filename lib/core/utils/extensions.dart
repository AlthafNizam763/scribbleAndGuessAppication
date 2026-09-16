/// Small, dependency-free extensions used across the app.
///
/// Nothing here touches Flutter: theme and `BuildContext` helpers live with
/// the theme and in `responsive.dart`.
library;

/// String helpers for display and guess comparison.
extension StringX on String {
  /// This string with its first character upper-cased.
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  /// Whether this string is empty once trimmed.
  bool get isBlank => trim().isEmpty;

  /// Whether this string holds anything but whitespace.
  bool get isNotBlank => !isBlank;

  /// This string cut to [maxLength] characters, ending in [ellipsis].
  ///
  /// Shorter strings are returned untouched, and the result never exceeds
  /// [maxLength].
  String truncate(int maxLength, {String ellipsis = '…'}) {
    if (maxLength <= 0) {
      return '';
    }
    if (length <= maxLength) {
      return this;
    }
    if (ellipsis.length >= maxLength) {
      return substring(0, maxLength);
    }
    return '${substring(0, maxLength - ellipsis.length)}$ellipsis';
  }

  /// A canonical form used to compare a guess against the secret word.
  ///
  /// Lower-cases, folds common accents, drops punctuation and collapses
  /// whitespace, so `Crème  Brûlée!` and `creme brulee` match.
  String normalizedForGuess() {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in toLowerCase().runes) {
      final String char = String.fromCharCode(rune);
      buffer.write(_accentFolding[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(_punctuationPattern, '')
        .replaceAll(_whitespacePattern, ' ')
        .trim();
  }

  /// Everything that is neither a letter, a digit nor whitespace.
  static final RegExp _punctuationPattern =
      RegExp(r'[^\p{L}\p{N}\s]', unicode: true);

  /// One or more whitespace characters.
  static final RegExp _whitespacePattern = RegExp(r'\s+');

  static const Map<String, String> _accentFolding = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae',
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i',
    'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
    'ö': 'o', 'ø': 'o', 'œ': 'oe', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
  };
}

/// Numeric helpers that keep call sites free of `math` imports.
extension IntX on int {
  /// This value pulled into the inclusive range `[min, max]`.
  int clampInt(int min, int max) {
    if (min > max) {
      return this;
    }
    if (this < min) {
      return min;
    }
    return this > max ? max : this;
  }

  /// This value read as a count of milliseconds.
  Duration get asDurationMs => Duration(milliseconds: this);

  /// This value read as a count of seconds.
  Duration get asDurationSeconds => Duration(seconds: this);
}

/// Formatting helpers for durations shown on timers.
extension DurationX on Duration {
  /// This duration as `MM:SS`, clamping negatives to `00:00`.
  String get mmss {
    final int totalSeconds = inSeconds < 0 ? 0 : inSeconds;
    final String minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final String seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Whole seconds left, rounded up, never negative.
  int get secondsCeil =>
      inMilliseconds <= 0 ? 0 : (inMilliseconds + 999) ~/ 1000;
}

/// Collection helpers used when laying out lists and ranking players.
extension IterableX<T> on Iterable<T> {
  /// This iterable with [separator] inserted between every pair of elements.
  ///
  /// Handy for spacing widget lists without a `ListView`.
  Iterable<T> separatedBy(T separator) sync* {
    bool first = true;
    for (final T element in this) {
      if (!first) {
        yield separator;
      }
      first = false;
      yield element;
    }
  }

  /// A new list ordered by [keyOf], highest key first.
  ///
  /// The sort is stable: elements with equal keys keep their original order,
  /// which matters for scoreboards where ties are broken by join order.
  List<T> sortedByDescending<K extends Comparable<K>>(
    K Function(T element) keyOf,
  ) {
    final List<T> source = toList(growable: false);
    final List<int> order = List<int>.generate(source.length, (int i) => i);
    order.sort((int a, int b) {
      final int byKey = keyOf(source[b]).compareTo(keyOf(source[a]));
      return byKey != 0 ? byKey : a.compareTo(b);
    });
    return <T>[for (final int index in order) source[index]];
  }
}
