import 'package:equatable/equatable.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// One entry of the word bank, offered to the drawer as a choice.
class WordItem extends Equatable {
  /// Creates a word item.
  const WordItem({
    this.text = '',
    this.category = WordCategory.random,
    this.difficulty = WordDifficulty.medium,
  });

  /// Builds a word item from a decoded JSON map, tolerating malformed values.
  factory WordItem.fromJson(Map<String, dynamic> json) => WordItem(
        text: asString(json['text']),
        category: WordCategory.fromName(asString(json['category'])),
        difficulty: WordDifficulty.fromName(asString(json['difficulty'])),
      );

  /// The word itself, as it should be drawn and guessed.
  final String text;

  /// Category the word belongs to.
  final WordCategory category;

  /// How hard the word is to draw and to guess.
  final WordDifficulty difficulty;

  /// Serializes this word item to a JSON-safe map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'category': category.name,
        'difficulty': difficulty.name,
      };

  /// Returns a copy with the given fields replaced.
  WordItem copyWith({
    String? text,
    WordCategory? category,
    WordDifficulty? difficulty,
  }) =>
      WordItem(
        text: text ?? this.text,
        category: category ?? this.category,
        difficulty: difficulty ?? this.difficulty,
      );

  @override
  List<Object?> get props => <Object?>[text, category, difficulty];

  @override
  bool get stringify => true;
}
