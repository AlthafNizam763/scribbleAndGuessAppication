import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/auth_api.dart';
import 'package:scribble_guess/data/api/social_api.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/friends_provider.dart';
import 'package:scribble_guess/providers/ranking_provider.dart';
import 'package:scribble_guess/services/location_service.dart';

/// The town the local player plays from, and the two ways it gets set.
///
/// ## Why this is a provider rather than state on the profile screen
///
/// Because two screens now change it. The profile hosts the full control and
/// Settings carries an "Update location" row, and a locality edited in one
/// place has to be the locality the other one shows. Holding it here also
/// means the leaderboard invalidation lives in exactly one method rather than
/// being something each caller has to remember.
///
/// ## It is server-owned
///
/// Unlike the name and the avatar, the locality is not cached in preferences
/// and is not part of the on-device `PlayerProfile`. The only thing that
/// reads it is a server-side leaderboard query, so the server holds it and
/// this is a view of that, re-read on demand. A device that has never been
/// online simply has no locality, which is the correct answer rather than a
/// stale one.

/// The device's geocoder, behind an interface the UI can fake in a test.
final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => const LocationService());

/// The local player's locality: `null` when they have not set one.
final AsyncNotifierProvider<LocalityNotifier, Locality?> localityProvider =
    AsyncNotifierProvider<LocalityNotifier, Locality?>(LocalityNotifier.new);

/// Reads, detects and writes the locality.
class LocalityNotifier extends AsyncNotifier<Locality?> {
  SocialApi get _social => ref.read(socialApiProvider);
  AuthApi get _auth => ref.read(authApiProvider);
  LocationService get _location => ref.read(locationServiceProvider);

  @override
  Future<Locality?> build() async {
    final Result<Map<String, dynamic>> result = await _auth.me();

    // A failed read resolves to "no locality set" rather than to an error.
    // This is an optional profile extra hosted on screens that have other
    // work to do, and it must not be able to break one: a player who opened
    // Settings to turn the sound off still can with the network down.
    final Map<String, dynamic>? me = result.valueOrNull;
    return me == null ? null : Locality.fromJson(me['locality']);
  }

  /// Whether this build can detect a locality, or only accept a typed one.
  bool get canDetect => _location.isSupported;

  /// Asks the device where it is and saves the town it names.
  ///
  /// The caller must have shown the explanation and got a yes first — this
  /// method will trigger the system permission dialog. The returned
  /// [LocationOutcome] is what the caller renders: only [LocationFound] means
  /// anything was written, and every other variant leaves the stored locality
  /// exactly as it was.
  ///
  /// A save that fails after a successful fix comes back as [LocationFailed],
  /// because from the player's side those are the same event — they asked for
  /// their town to be filled in and it was not.
  Future<LocationOutcome> detectAndSave() async {
    final LocationOutcome outcome = await _location.detect();

    if (outcome is! LocationFound) {
      return outcome;
    }

    final Result<void> saved = await save(outcome.locality);

    return switch (saved) {
      Ok<void>() => outcome,
      Err<void>(:final Failure failure) => LocationFailed(failure),
    };
  }

  /// Writes [locality] to the server, or clears it when passed `null`.
  ///
  /// Empty fields are sent as `null` rather than as `''`: that is what the
  /// endpoint treats as "unset", and a city cleared to an empty string would
  /// otherwise leave the player on the board under a blank town.
  Future<Result<void>> save(Locality? locality) async {
    final Result<void> result = await _social.updateLocality(
      city: _orNull(locality?.city),
      region: _orNull(locality?.region),
      country: _orNull(locality?.country)?.toUpperCase(),
    );

    if (result case Err<void>()) {
      return result;
    }

    // The label is the server's to build, so the copy held here until the next
    // read has none. `Locality.display` falls back to the city for exactly
    // this window.
    state = AsyncValue<Locality?>.data(
      locality == null || locality.isEmpty ? null : locality,
    );

    // The locality board is now a different set of people — the player either
    // joined one, moved between two, or dropped off.
    ref.invalidate(rankingProvider(LeaderboardScope.locality));

    return result;
  }

  /// Re-reads the locality from the server.
  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  static String? _orNull(String? value) {
    final String trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
