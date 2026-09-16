import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/constants/game_defaults.dart';

/// Form-field validators shared by every screen.
///
/// Each method returns `null` when the input is acceptable, or the
/// `AppStrings` message describing the single most relevant problem.
abstract final class Validators {
  /// Validates a player nickname.
  static String? username(String? value) {
    final String name = (value ?? '').trim();
    if (name.isEmpty) {
      return AppStrings.validationNameRequired;
    }
    final int length = _lengthOf(name);
    if (length < AppConstants.minNameLength) {
      return AppStrings.validationNameTooShort;
    }
    if (length > AppConstants.maxNameLength) {
      return AppStrings.validationNameTooLong;
    }
    if (!_namePattern.hasMatch(name)) {
      return AppStrings.validationNameInvalid;
    }
    return null;
  }

  /// Validates a room code, ignoring case and surrounding whitespace.
  static String? roomCode(String? value) {
    final String code = normalizeRoomCode(value);
    if (code.isEmpty) {
      return AppStrings.validationCodeRequired;
    }
    if (code.length != AppConstants.roomCodeLength) {
      return AppStrings.validationCodeLength;
    }
    for (int i = 0; i < code.length; i++) {
      if (!AppConstants.roomCodeAlphabet.contains(code[i])) {
        return AppStrings.validationCodeInvalid;
      }
    }
    return null;
  }

  /// Validates a chat message or guess.
  static String? chatMessage(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return AppStrings.validationMessageRequired;
    }
    if (_lengthOf(text) > AppConstants.maxChatLength) {
      return AppStrings.validationMessageTooLong;
    }
    return null;
  }

  /// Validates one entry of the host-supplied custom word list.
  static String? customWord(String? value) {
    final String word = (value ?? '').trim();
    if (word.isEmpty) {
      return AppStrings.validationWordRequired;
    }
    final int length = _lengthOf(word);
    if (length < GameDefaults.minCustomWordLength) {
      return AppStrings.validationWordTooShort;
    }
    if (length > GameDefaults.maxCustomWordLength) {
      return AppStrings.validationWordTooLong;
    }
    if (!_wordPattern.hasMatch(word)) {
      return AppStrings.validationWordInvalid;
    }
    return null;
  }

  /// Validates the player's optional game-server override.
  ///
  /// Empty is valid and means "use the backend this build was configured
  /// with" — the deployed one. Only a value the player actually typed has to
  /// be a well-formed `http`/`https` origin.
  static String? serverUrl(String? value) {
    final String url = (value ?? '').trim();
    if (url.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
      return AppStrings.validationUrlInvalid;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return AppStrings.validationUrlInvalid;
    }
    return null;
  }

  /// Trims and upper-cases a room code so it can be compared or submitted.
  ///
  /// Room codes are always handled case-insensitively.
  static String normalizeRoomCode(String? value) =>
      (value ?? '').trim().toUpperCase();

  /// Whether [a] and [b] name the same room, ignoring case and whitespace.
  static bool sameRoomCode(String? a, String? b) =>
      normalizeRoomCode(a) == normalizeRoomCode(b);

  /// Letters, digits, spaces, dots, hyphens and underscores.
  static final RegExp _namePattern =
      RegExp(r'^[\p{L}\p{N} ._-]+$', unicode: true);

  /// Letters, spaces and hyphens.
  static final RegExp _wordPattern = RegExp(r'^[\p{L} -]+$', unicode: true);

  /// Counts code points, so an emoji counts as one character.
  static int _lengthOf(String value) => value.runes.length;
}
