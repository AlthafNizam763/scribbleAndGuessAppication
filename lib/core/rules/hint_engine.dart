import 'dart:math';

/// Builds the masked word shown to guessers and decides which letters the
/// server reveals as hints.
///
/// Spaces and hyphens are structural: they are always visible and never count
/// as a hint. Every function is pure, and the only randomness comes from the
/// injected [Random].
abstract final class HintEngine {
  /// The glyph standing in for a hidden letter.
  static const String blank = '_';

  /// Renders [word] with only [revealedIndices] visible.
  ///
  /// Cells are joined with a single space, so `ice cream` with index `0`
  /// revealed becomes `i _ _   _ _ _ _ _`.
  static String maskWord(String word, List<int> revealedIndices) {
    final Set<int> revealed = revealedIndices.toSet();
    return <String>[
      for (int i = 0; i < word.length; i++)
        if (!_isMaskable(word[i]) || revealed.contains(i)) word[i] else blank,
    ].join(' ');
  }

  /// Number of characters in [word] that can be hidden behind a [blank].
  static int letterCount(String word) {
    int count = 0;
    for (int i = 0; i < word.length; i++) {
      if (_isMaskable(word[i])) {
        count++;
      }
    }
    return count;
  }

  /// The cumulative revealed indices of [word] after hint number [hintNumber].
  ///
  /// [hintNumber] is one-based and [current] holds what previous hints already
  /// revealed, so calling this repeatedly only ever adds letters. At most half
  /// of the maskable positions are ever revealed, no index is revealed twice,
  /// and each new letter is taken as far as possible from the ones already
  /// showing so hints do not cluster at the start of the word.
  ///
  /// The returned list is sorted ascending.
  static List<int> nextHintIndices({
    required String word,
    required List<int> current,
    required int totalHints,
    required int hintNumber,
    required Random random,
  }) {
    final List<int> maskable = _maskablePositions(word);
    final Set<int> allowed = maskable.toSet();
    final Set<int> revealed = <int>{
      for (final int index in current)
        if (allowed.contains(index)) index,
    };
    final int target = _target(
      maskablePositions: maskable.length,
      totalHints: totalHints,
      hintNumber: hintNumber,
    );
    if (revealed.length < target) {
      final List<int> candidates = <int>[
        for (final int index in maskable)
          if (!revealed.contains(index)) index,
      ];
      while (revealed.length < target && candidates.isNotEmpty) {
        final int chosen = _mostIsolated(candidates, revealed, random);
        revealed.add(chosen);
        candidates.remove(chosen);
      }
    }
    final List<int> result = revealed.toList()..sort();
    return result;
  }

  /// How many letters should be showing once [hintNumber] hints have landed.
  static int _target({
    required int maskablePositions,
    required int totalHints,
    required int hintNumber,
  }) {
    final int cap = maskablePositions ~/ 2;
    final int wanted = hintNumber < 0 ? 0 : hintNumber;
    final int allowedHints = totalHints < 0 ? 0 : totalHints;
    final int limited = wanted < allowedHints ? wanted : allowedHints;
    return limited < cap ? limited : cap;
  }

  /// The candidate furthest from every already revealed index.
  ///
  /// Ties — including the very first reveal, where nothing is showing yet —
  /// are broken with [random].
  static int _mostIsolated(
    List<int> candidates,
    Set<int> revealed,
    Random random,
  ) {
    int bestScore = -1;
    final List<int> best = <int>[];
    for (final int candidate in candidates) {
      int score = _unbounded;
      for (final int index in revealed) {
        final int distance = (candidate - index).abs();
        if (distance < score) {
          score = distance;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best.clear();
        best.add(candidate);
      } else if (score == bestScore) {
        best.add(candidate);
      }
    }
    return best[random.nextInt(best.length)];
  }

  /// Indices of [word] that can be hidden, in ascending order.
  static List<int> _maskablePositions(String word) => <int>[
        for (int i = 0; i < word.length; i++)
          if (_isMaskable(word[i])) i,
      ];

  /// Whether [char] is hidden until a hint reveals it.
  static bool _isMaskable(String char) => char != ' ' && char != '-';

  /// Stands in for "infinitely far away" while nothing is revealed yet.
  static const int _unbounded = 1 << 30;
}
