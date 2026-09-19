import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/utils/id_generator.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/repositories/profile_repository.dart';
import 'package:scribble_guess/services/auth_service.dart';

/// The local player's identity, or `null` until they have picked a name.
class ProfileNotifier extends Notifier<PlayerProfile?> {
  static final Random _random = Random();

  @override
  PlayerProfile? build() => ref.watch(bootstrapProfileProvider);

  ProfileRepository get _repository => ref.read(profileRepositoryProvider);

  /// Persists [profile] locally and pushes it to the server.
  ///
  /// The id is always the one the *server* issued, never a locally minted one:
  /// it is what rooms, scores and drawer checks are keyed by, so a
  /// client-generated value would simply not match anything (§6). A uuid is
  /// used only as a stand-in before the session resolves, and is replaced on
  /// the next save.
  ///
  /// The `ensureSession` call is a guard, not the thing that creates the
  /// account: since sign-in became a gate, this screen is only reachable with
  /// a session already in hand, so it short-circuits on the existing one. It
  /// stays because this method must not write a profile against a
  /// client-minted id if it is ever reached another way — the name itself is
  /// pushed to the server by `updateProfile` below.
  Future<Result<void>> save(PlayerProfile profile) async {
    final AuthService auth = ref.read(authServiceProvider);
    await auth.ensureSession(profile: profile);

    final String uid = ref.read(currentUserIdProvider);
    final String id = uid.isNotEmpty
        ? uid
        : (state?.id.isNotEmpty ?? false)
            ? state!.id
            : IdGenerator.uuid();

    final PlayerProfile stamped = profile.copyWith(id: id);

    // Local first: the device's copy is what renders the next frame, and a
    // rename should not appear to fail because the network was slow. The
    // server copy is corrected below, and re-sent on the next handshake
    // regardless.
    final Result<void> result = await _repository.save(stamped);
    if (result.isOk) {
      state = stamped;
      unawaited(auth.updateProfile(stamped));
    }
    return result;
  }

  /// Forgets the local player entirely.
  Future<Result<void>> clear() async {
    final Result<void> result = await _repository.clear();
    if (result.isOk) {
      state = null;
    }
    return result;
  }

  /// A fresh avatar and colour, leaving the name alone.
  static PlayerProfile randomizeAppearance(PlayerProfile profile) =>
      profile.copyWith(
        avatarId: _random.nextInt(AppConstants.avatarCount),
        avatarColorIndex: _random.nextInt(AppConstants.avatarColorCount),
      );

  /// A blank profile with a random look, for the first-run screen.
  static PlayerProfile blank() => PlayerProfile(
        id: IdGenerator.uuid(),
        avatarId: _random.nextInt(AppConstants.avatarCount),
        avatarColorIndex: _random.nextInt(AppConstants.avatarColorCount),
      );
}

final NotifierProvider<ProfileNotifier, PlayerProfile?> profileProvider =
    NotifierProvider<ProfileNotifier, PlayerProfile?>(ProfileNotifier.new);

/// Whether the player has finished the first-run profile step.
final Provider<bool> hasProfileProvider = Provider<bool>(
  (Ref ref) => ref.watch(profileProvider) != null,
);

/// The local player's id: the Firebase uid.
///
/// Read from auth rather than from the saved profile, because the uid exists
/// from the moment the app signs in — before any profile has been chosen —
/// and because it is the id the server actually keys this player by. The saved
/// profile is only consulted as a fallback for the brief window before
/// anonymous sign-in resolves.
final Provider<String> selfIdProvider = Provider<String>((Ref ref) {
  final String uid = ref.watch(currentUserIdProvider);
  return uid.isNotEmpty ? uid : (ref.watch(profileProvider)?.id ?? '');
});
