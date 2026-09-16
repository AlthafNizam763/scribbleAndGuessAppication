import 'dart:math';

import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:uuid/uuid.dart';

/// Creates the identifiers used for players, strokes, messages and rooms.
abstract final class IdGenerator {
  /// A random v4 UUID, used for stable entity identifiers.
  static String uuid() => _uuid.v4();

  /// A short, URL-safe identifier of [length] lowercase alphanumerics.
  ///
  /// Collision-resistant enough for stroke and message ids inside one match,
  /// and far cheaper to send than a full UUID.
  static String shortId([int length = 8]) {
    if (length <= 0) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(_shortAlphabet[_random.nextInt(_shortAlphabet.length)]);
    }
    return buffer.toString();
  }

  /// A room code of [AppConstants.roomCodeLength] unambiguous characters.
  ///
  /// Pass [random] to make generation deterministic in tests.
  static String roomCode([Random? random]) {
    final Random source = random ?? _random;
    const String alphabet = AppConstants.roomCodeAlphabet;
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < AppConstants.roomCodeLength; i++) {
      buffer.write(alphabet[source.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  static const Uuid _uuid = Uuid();
  static const String _shortAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _random = Random();
}
