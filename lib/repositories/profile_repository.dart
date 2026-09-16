import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/player_profile.dart';

/// Persistence seam for the local player identity.
///
/// The stored [PlayerProfile] is a *preference*, never a credential. It is the
/// name and doodle avatar this device offers when creating or joining a room;
/// the server assigns the id that actually identifies the player in a match
/// and re-checks the name for length and uniqueness, answering with
/// [AppErrorCode.nameTaken] when it clashes. Nothing here grants any
/// permission, so an implementation must never treat the saved id as proof of
/// host or drawer rights.
///
/// Backed by `shared_preferences` in the shipped implementation, which is why
/// failures are storage rather than network shaped.
abstract interface class ProfileRepository {
  /// Reads the saved profile, or `null` when this device has none yet.
  ///
  /// Deliberately does not return a [Result]: a missing or corrupt record is
  /// not an error, it simply means the profile screen must be shown. Malformed
  /// stored JSON is discarded and reported as `null`.
  Future<PlayerProfile?> load();

  /// Writes [profile] as the identity used for the next room.
  ///
  /// [profile] should already satisfy `Validators.playerName`, with
  /// `avatarId` in `0..AppConstants.avatarCount - 1` and `avatarColorIndex` in
  /// `0..AppConstants.avatarColorCount - 1`.
  ///
  /// Fails with [AppErrorCode.validation] for out-of-range values and
  /// [AppErrorCode.storage] when the write itself fails.
  Future<Result<void>> save(PlayerProfile profile);

  /// Deletes the saved profile.
  ///
  /// Succeeds when there was nothing to delete. Fails with
  /// [AppErrorCode.storage] only if the removal itself fails.
  Future<Result<void>> clear();
}
