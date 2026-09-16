import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:scribble_guess/core/constants/firebase_constants.dart';
import 'package:scribble_guess/core/errors/app_exception.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';

/// Custom avatar upload (§52).
///
/// Optional by design: the game ships procedural doodle avatars, and a player
/// who never opens this path still has a face on the scoreboard. That matters
/// for a game people join in thirty seconds.
///
/// Every constraint enforced here is enforced again by `storage.rules`. The
/// client checks are for a fast, clear error; the rules are what actually make
/// the bucket safe.
class StorageService {
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads [bytes] as the player's avatar and returns its download URL.
  ///
  /// [contentType] must be one of [StoragePaths.avatarContentTypes], and
  /// [bytes] must be at most [StoragePaths.maxAvatarBytes].
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!StoragePaths.avatarContentTypes.contains(contentType)) {
      throw AppException.of(
        AppErrorCode.validation,
        'Avatars must be a JPEG, PNG or WebP image.',
      );
    }
    if (bytes.lengthInBytes > StoragePaths.maxAvatarBytes) {
      throw AppException.of(
        AppErrorCode.validation,
        'That image is too large. The limit is 2 MB.',
      );
    }
    if (bytes.isEmpty) {
      throw AppException.of(AppErrorCode.validation, 'That image is empty.');
    }

    try {
      final Reference ref = _storage.ref(StoragePaths.avatar(userId));
      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          // Avatars change rarely and are fetched constantly; a long cache with
          // revalidation keeps the lobby cheap to render.
          cacheControl: 'public, max-age=86400',
        ),
      );
      return await ref.getDownloadURL();
    } on Object catch (error, stack) {
      AppLogger.e('avatar upload failed', error, stack);
      throw toAppException(error, stack);
    }
  }

  /// Removes the player's uploaded avatar, falling back to their doodle.
  ///
  /// A missing object is treated as success: the caller wanted it gone, and it
  /// is gone.
  Future<void> deleteAvatar(String userId) async {
    try {
      await _storage.ref(StoragePaths.avatar(userId)).delete();
    } on FirebaseException catch (error, stack) {
      if (error.code == 'object-not-found') return;
      throw toAppException(error, stack);
    } on Object catch (error, stack) {
      throw toAppException(error, stack);
    }
  }
}
