import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/social.dart';

/// Turns "where is this device" into a town name, and nothing finer.
///
/// ## What it is for
///
/// One thing: filling in the locality that the locality leaderboard groups
/// players by, so nobody has to type their own town. It is asked to do that
/// only when a player taps a button, and it answers with a [Locality] — a
/// city, a region and a country code, the same three fields the server will
/// accept and the only three it can store.
///
/// ## Why the coordinates never leave this file
///
/// [detect] reads a fix, reverse geocodes it, and lets the [Position] go out
/// of scope. No caller can ask for the latitude, because no method returns
/// one; there is no field to put one in on [Locality], in the body of
/// `PATCH /api/users/me/locality`, or on the user document behind it. The
/// privacy property is structural rather than a rule somebody has to
/// remember — the same shape the rest of the locality feature already has.
///
/// Reverse geocoding runs on the device's own geocoder (`Geocoder` on
/// Android, `CLGeocoder` on Apple platforms), so the fix is not handed to a
/// third-party service either.
///
/// ## Why there is no stream
///
/// There is no position stream, no background mode and no method here that
/// repeats. A locality is read when a player asks for it and never again,
/// which is why this cannot accumulate into location history however it is
/// called. `geolocator` merges a `GeolocatorLocationService` into the Android
/// manifest that this class never starts — it only serves a foreground
/// position stream, which nothing here opens.
///
/// ## Why it does not return a [Result]
///
/// Because a refusal is not an error. "I would rather not say" is an ordinary
/// answer the UI has to draw differently from "the geocoder broke": declining
/// offers the manual fields, a permanent denial has to send the player to
/// system settings, and only [LocationFailed] is worth an error snackbar.
/// Collapsing those into one [Failure] would throw away exactly the
/// distinction the screen needs. Nothing here throws.
class LocationService {
  /// Creates the service.
  const LocationService();

  /// How long to wait for a fix before giving up.
  ///
  /// A coarse fix off cell towers or wifi is usually immediate; this bound is
  /// for the case where a device with no recent fix goes looking for
  /// satellites, which can hang for minutes. A player who tapped a button on
  /// their profile should not watch a spinner for that long when typing the
  /// town themselves takes five seconds.
  static const Duration fixTimeout = Duration(seconds: 15);

  /// Whether this build can detect a locality at all.
  ///
  /// False on web and desktop. `geolocator` has a browser implementation — it
  /// wraps the Geolocation API — but `geocoding` does not, because a browser
  /// has no reverse geocoder to wrap. Turning a fix into a town there would
  /// mean posting the coordinates to somebody's HTTP geocoder, which is the
  /// one thing this feature is built not to do, so the web build keeps the
  /// manual town fields instead.
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Reads one approximate fix and resolves it to a town.
  ///
  /// Requests permission when it has not been asked for yet, which is why the
  /// caller must have shown the explanation first — see
  /// `askToUseLocation`. Every branch below is an ordinary outcome that
  /// leaves the app working; none of them is fatal to the calling screen.
  Future<LocationOutcome> detect() async {
    if (!isSupported) {
      return const LocationUnsupported();
    }

    // Asking for permission while the device's location is switched off earns
    // a grant and then no fix, so the switch is checked first and reported as
    // its own outcome: the fix for it is the location settings page, not the
    // app settings page.
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationOff();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return const LocationDenied();
      case LocationPermission.deniedForever:
        // The system dialog will not appear again, so asking a second time
        // here would sit there doing nothing. Only app settings can undo it.
        return const LocationDenied(permanently: true);
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }

    return _resolve();
  }

  /// Whether location has already been granted, so nothing would be prompted.
  ///
  /// The caller uses this to decide whether the explanation is still owed.
  /// It is owed before the system dialog and not after: a player who already
  /// agreed and is tapping "Update location" because they moved house does
  /// not need the policy read back to them every time, and a dialog that
  /// appears when nothing is being asked for is what trains people to dismiss
  /// the one that matters.
  Future<bool> hasPermission() async {
    if (!isSupported) {
      return false;
    }
    final LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Sends the player to the system page that can undo a permanent denial.
  Future<void> openPermissionSettings() => Geolocator.openAppSettings();

  /// Sends the player to the system page with the location switch on it.
  Future<void> openDeviceLocationSettings() =>
      Geolocator.openLocationSettings();

  // ------------------------------------------------------------ internals --

  /// Takes the fix and throws away everything but the town.
  Future<LocationOutcome> _resolve() async {
    final Result<List<Placemark>> places = await guard(() async {
      final Position position = await Geolocator.getCurrentPosition(
        // Deliberately the coarsest setting that still lands in the right
        // town. The Android build asks for ACCESS_COARSE_LOCATION only, and
        // `best` would spin up GPS to answer a question a cell tower has
        // already answered.
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: fixTimeout,
        ),
      );

      // `position` is read here and nowhere else. It is not returned, not
      // logged and not stored; by the end of this closure the only thing left
      // of it is a list of place names.
      return Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
    });

    switch (places) {
      case Err<List<Placemark>>(:final Failure failure):
        // The failure itself is logged, never the fix that produced it.
        AppLogger.w('LocationService: no locality (${failure.code.name})');
        return LocationFailed(failure);
      case Ok<List<Placemark>>(:final List<Placemark> value):
        final Locality? locality = localityFrom(value);
        // A fix in the middle of the sea, or a device whose geocoder has no
        // data for where it is. Nothing went wrong; there is simply no town.
        return locality == null
            ? const LocationNotFound()
            : LocationFound(locality);
    }
  }

  /// Picks the first placemark that names a town, and keeps three fields.
  ///
  /// The street, the house number and the postcode on a [Placemark] are read
  /// past deliberately: nothing downstream has a field for any of them, and
  /// this is the only point in the app where they are ever in memory.
  ///
  /// Exposed for tests because this is the part of the class with rules in
  /// it, and the rest is two plugin calls. What a geocoder returns varies by
  /// device, by country and by how rural the fix was, and this is where that
  /// variety is flattened into the three fields the board groups by.
  @visibleForTesting
  static Locality? localityFrom(List<Placemark> places) {
    for (final Placemark place in places) {
      // `locality` is the town. `subAdministrativeArea` is the district it
      // sits in, which is what a rural fix comes back with instead — still a
      // town-sized answer rather than a finer one.
      final String town = _clean(place.locality);
      final String city = town.isNotEmpty
          ? town
          : _clean(place.subAdministrativeArea);

      if (city.isEmpty) {
        continue;
      }

      return Locality(
        city: city,
        region: _clean(place.administrativeArea),
        // The server stores ISO 3166-1 alpha-2, so the code is preferred over
        // the country name, which the device's geocoder localises and which
        // would otherwise put "Deutschland" and "Germany" on two boards.
        country: _clean(place.isoCountryCode).toUpperCase(),
      );
    }
    return null;
  }

  static String _clean(String? value) => value?.trim() ?? '';
}

/// What came back from [LocationService.detect].
///
/// Sealed so a screen handling it with a `switch` cannot quietly forget the
/// denial cases when a new one is added.
sealed class LocationOutcome {
  /// Const base constructor for the variants.
  const LocationOutcome();
}

/// A town was found. The only outcome that carries anything.
final class LocationFound extends LocationOutcome {
  /// Wraps the detected [locality].
  const LocationFound(this.locality);

  /// The town, region and country code — never a coordinate.
  final Locality locality;
}

/// The player said no.
///
/// An ordinary answer rather than a failure: the caller offers the manual
/// fields, and everything else on the screen keeps working.
final class LocationDenied extends LocationOutcome {
  /// Creates a denial, [permanently] when the system will not ask again.
  const LocationDenied({this.permanently = false});

  /// Whether only app settings can reverse this.
  ///
  /// True after a second refusal on Android or a "Don't allow" on iOS, where
  /// calling `requestPermission` again would show the player nothing at all.
  final bool permanently;
}

/// Location is switched off for the whole device.
final class LocationOff extends LocationOutcome {
  /// Creates the services-disabled outcome.
  const LocationOff();
}

/// This build cannot detect a locality — see [LocationService.isSupported].
final class LocationUnsupported extends LocationOutcome {
  /// Creates the unsupported outcome.
  const LocationUnsupported();
}

/// A fix was read, but no town could be named for it.
final class LocationNotFound extends LocationOutcome {
  /// Creates the empty-result outcome.
  const LocationNotFound();
}

/// The fix or the lookup failed — no signal, a timeout, a geocoder error.
final class LocationFailed extends LocationOutcome {
  /// Wraps the [failure] that stopped the lookup.
  const LocationFailed(this.failure);

  /// What went wrong, already classified by [guard].
  final Failure failure;
}
