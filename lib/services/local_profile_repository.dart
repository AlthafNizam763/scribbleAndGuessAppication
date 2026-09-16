import 'package:scribble_guess/core/constants/storage_keys.dart';
import 'package:scribble_guess/core/utils/id_generator.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/repositories/profile_repository.dart';
import 'package:scribble_guess/services/preferences_store.dart';

/// Stores the player's identity on the device.
///
/// The profile id is minted once and then kept for the life of the install so
/// the leaderboard can attribute games to the same person across sessions.
class LocalProfileRepository implements ProfileRepository {
  const LocalProfileRepository(this._store);

  final PreferencesStore _store;

  @override
  Future<PlayerProfile?> load() async {
    final Map<String, dynamic>? json = _store.readObject(StorageKeys.profile);
    if (json == null) {
      return null;
    }
    final PlayerProfile profile = PlayerProfile.fromJson(json);
    // A profile with no name was never finished; treat it as absent so the
    // app routes back to the profile screen.
    if (profile.name.trim().isEmpty) {
      return null;
    }
    return profile.id.isEmpty
        ? profile.copyWith(id: IdGenerator.uuid())
        : profile;
  }

  @override
  Future<Result<void>> save(PlayerProfile profile) {
    final PlayerProfile stamped =
        profile.id.isEmpty ? profile.copyWith(id: IdGenerator.uuid()) : profile;
    return _store.writeJson(StorageKeys.profile, stamped.toJson());
  }

  @override
  Future<Result<void>> clear() => _store.remove(StorageKeys.profile);
}
