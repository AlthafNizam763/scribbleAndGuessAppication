import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/user_preferences.dart';
import 'package:scribble_guess/providers/auth_provider.dart';

/// The account's notification and privacy switches.
///
/// ## Optimistic, and honest about it
///
/// A toggle has to move under the thumb — a switch that waits for a round trip
/// before it visibly flips feels broken, and on a poor connection it feels
/// broken for several seconds. So the new value is applied locally first.
///
/// What it does *not* do is keep that value if the server disagrees. The
/// response carries the whole set as the server now holds it, and that
/// overwrites the guess; a failure rolls back to what was there before and
/// hands the caller the message to show. There is no path here that leaves a
/// switch showing a state the server does not have.
class UserPreferencesNotifier extends AsyncNotifier<UserPreferences> {
  @override
  Future<UserPreferences> build() async {
    final Result<UserPreferences> result =
        await ref.read(authApiProvider).preferences();

    return switch (result) {
      Ok<UserPreferences>(:final UserPreferences value) => value,
      // Thrown rather than returned so the screen's error branch renders,
      // which is where the retry lives.
      Err<UserPreferences>(:final Failure failure) => throw failure,
    };
  }

  /// Flips one switch, named by its wire key.
  ///
  /// Returns the failure when the server refused, so the screen can say so.
  /// Null means it went through.
  Future<Failure?> set(String key, bool value) async {
    final UserPreferences? current = state.valueOrNull;
    if (current == null) return null;

    state = AsyncValue<UserPreferences>.data(_applied(current, key, value));

    final Result<UserPreferences> result = await ref
        .read(authApiProvider)
        .updatePreferences(<String, bool>{key: value});

    switch (result) {
      case Ok<UserPreferences>(:final UserPreferences value):
        // The server's copy, not the optimistic one — so a switch the server
        // silently corrected shows what it actually holds.
        state = AsyncValue<UserPreferences>.data(value);
        return null;
      case Err<UserPreferences>(:final Failure failure):
        state = AsyncValue<UserPreferences>.data(current);
        return failure;
    }
  }

  /// Re-reads the switches from the server.
  Future<void> refresh() async {
    state = await AsyncValue.guard<UserPreferences>(build);
  }

  /// [current] with the switch named by [key] set to [value].
  ///
  /// A switch rather than a map so an unknown key cannot silently do nothing:
  /// every key this app sends is one of these six, and the default returning
  /// `current` unchanged is what a newer server's key would land on.
  UserPreferences _applied(UserPreferences current, String key, bool value) =>
      switch (key) {
        'notifyGameInvites' => current.copyWith(notifyGameInvites: value),
        'notifyFriendActivity' => current.copyWith(notifyFriendActivity: value),
        'notifyRoomActivity' => current.copyWith(notifyRoomActivity: value),
        'notifySystem' => current.copyWith(notifySystem: value),
        'showOnlineStatus' => current.copyWith(showOnlineStatus: value),
        'discoverable' => current.copyWith(discoverable: value),
        _ => current,
      };
}

/// The account's switches, as the Settings screen reads them.
final AsyncNotifierProvider<UserPreferencesNotifier, UserPreferences>
    userPreferencesProvider =
    AsyncNotifierProvider<UserPreferencesNotifier, UserPreferences>(
  UserPreferencesNotifier.new,
);
