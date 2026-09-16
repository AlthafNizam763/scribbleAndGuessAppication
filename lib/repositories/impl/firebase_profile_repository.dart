import 'package:scribble_guess/core/errors/app_exception.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/repositories/profile_repository.dart';
import 'package:scribble_guess/services/firestore_service.dart';

/// [ProfileRepository] that keeps the device preference and the Firestore
/// profile in step.
///
/// Both copies exist for a reason. The local one is read synchronously before
/// the first frame, so the app knows whether to show the profile screen without
/// waiting on a network round trip. The Firestore one is what other players
/// see, and what the lifetime statistics hang off.
///
/// Local is the source of truth for *reads*, and a Firestore write that fails
/// is logged rather than surfaced: a name saved on the device but not yet
/// synced is a much better outcome than an error dialog over a working game,
/// and the next save reconciles it. What the server ultimately trusts is
/// neither copy — it is the name passed to `createRoom`/`joinRoom`, which it
/// sanitises itself (§7).
class FirebaseProfileRepository implements ProfileRepository {
  FirebaseProfileRepository({
    required ProfileRepository local,
    required FirestoreService firestore,
    required String Function() userId,
  })  : _local = local,
        _firestore = firestore,
        _userId = userId;

  final ProfileRepository _local;
  final FirestoreService _firestore;
  final String Function() _userId;

  @override
  Future<PlayerProfile?> load() async {
    final PlayerProfile? stored = await _local.load();
    final String uid = _userId();
    if (stored == null || uid.isEmpty) return stored;

    // The uid is authoritative: a profile carried over from a previous
    // anonymous session must not keep claiming that identity.
    return stored.id == uid ? stored : stored.copyWith(id: uid);
  }

  @override
  Future<Result<void>> save(PlayerProfile profile) async {
    final String uid = _userId();
    final PlayerProfile stamped =
        uid.isEmpty ? profile : profile.copyWith(id: uid);

    final Result<void> local = await _local.save(stamped);
    if (local.isErr) return local;

    if (uid.isNotEmpty) {
      try {
        await _firestore.saveProfile(uid, stamped);
      } on AppException catch (error) {
        AppLogger.w('profile did not sync to Firestore', error);
      }
    }
    return local;
  }

  @override
  Future<Result<void>> clear() => _local.clear();
}
