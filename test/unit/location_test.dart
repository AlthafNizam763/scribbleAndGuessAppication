import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/services/location_service.dart';

/// Turning a geocoder's answer into a leaderboard's grouping key.
///
/// This is the one place in the location feature with rules in it, and the
/// rules exist because a reverse geocoder is not consistent: what a city
/// centre calls `locality`, a village leaves blank; what one device calls
/// `country`, another calls `Deutschland`. Every case below is a shape a real
/// geocoder returns, and getting one wrong does not crash anything — it
/// quietly files a player under a town that is not theirs, or splits one town
/// across two boards.
///
/// The other half of what these assert is the privacy property: a [Placemark]
/// carries a street, a house number and a postcode, and none of them may
/// appear in the [Locality] that comes out.
Placemark _place({
  String? locality,
  String? subAdministrativeArea,
  String? administrativeArea,
  String? isoCountryCode,
  String? country,
  String? street,
  String? postalCode,
  String? subThoroughfare,
}) =>
    Placemark(
      locality: locality,
      subAdministrativeArea: subAdministrativeArea,
      administrativeArea: administrativeArea,
      isoCountryCode: isoCountryCode,
      country: country,
      street: street,
      postalCode: postalCode,
      subThoroughfare: subThoroughfare,
    );

void main() {
  group('LocationService.localityFrom', () {
    test('keeps the town, the region and the ISO country code', () {
      final Locality? locality = LocationService.localityFrom(<Placemark>[
        _place(
          locality: 'Kochi',
          administrativeArea: 'Kerala',
          isoCountryCode: 'IN',
          country: 'India',
        ),
      ]);

      expect(locality?.city, 'Kochi');
      expect(locality?.region, 'Kerala');
      expect(locality?.country, 'IN');
    });

    test('prefers the ISO code over the localised country name', () {
      // A German-locale device geocoding a German fix answers "Deutschland".
      // Storing that would put it on a different board from every phone set to
      // English, for the same town.
      final Locality? locality = LocationService.localityFrom(<Placemark>[
        _place(
          locality: 'Köln',
          administrativeArea: 'Nordrhein-Westfalen',
          isoCountryCode: 'de',
          country: 'Deutschland',
        ),
      ]);

      expect(locality?.country, 'DE');
    });

    test('falls back to the district when there is no named town', () {
      // What a rural fix comes back with. Still town-sized, which is the only
      // property that matters here.
      final Locality? locality = LocationService.localityFrom(<Placemark>[
        _place(
          subAdministrativeArea: 'Idukki',
          administrativeArea: 'Kerala',
          isoCountryCode: 'IN',
        ),
      ]);

      expect(locality?.city, 'Idukki');
    });

    test('skips placemarks that name no town at all', () {
      // Geocoders return several candidates, and the first is not always the
      // useful one — a country-level match often comes back ahead of the town.
      final Locality? locality = LocationService.localityFrom(<Placemark>[
        _place(isoCountryCode: 'IN', country: 'India'),
        _place(locality: '   ', administrativeArea: 'Kerala'),
        _place(locality: 'Kochi', isoCountryCode: 'IN'),
      ]);

      expect(locality?.city, 'Kochi');
    });

    test('returns null rather than an empty locality', () {
      // A fix at sea, or a device whose geocoder has no data for where it is.
      // Null is what makes the caller report "no town found" instead of
      // saving a blank one and putting the player on a board named nothing.
      expect(LocationService.localityFrom(<Placemark>[]), isNull);
      expect(
        LocationService.localityFrom(<Placemark>[_place(isoCountryCode: 'IN')]),
        isNull,
      );
    });

    test('drops the street, the house number and the postcode', () {
      // The point of the whole feature. These three fields are in memory for
      // the length of this call and must not survive it: there is nowhere for
      // them to go downstream, and this asserts that nothing smuggles them
      // into a field that does exist.
      final Locality? locality = LocationService.localityFrom(<Placemark>[
        _place(
          locality: 'Kochi',
          administrativeArea: 'Kerala',
          isoCountryCode: 'IN',
          street: 'Marine Drive 14',
          subThoroughfare: '14',
          postalCode: '682031',
        ),
      ]);

      for (final String field in <String>[
        locality!.city,
        locality.region,
        locality.country,
        locality.label,
      ]) {
        expect(field, isNot(contains('Marine')));
        expect(field, isNot(contains('14')));
        expect(field, isNot(contains('682031')));
      }
    });

    test('trims whitespace the geocoder pads its fields with', () {
      final Locality? locality = LocationService.localityFrom(<Placemark>[
        _place(
          locality: '  Kochi ',
          administrativeArea: ' Kerala ',
          isoCountryCode: ' in ',
        ),
      ]);

      expect(locality?.city, 'Kochi');
      expect(locality?.region, 'Kerala');
      expect(locality?.country, 'IN');
    });
  });

  group('LocationOutcome', () {
    test('distinguishes a first refusal from a permanent one', () {
      // The screen draws these differently: one is a snackbar, the other has
      // to send the player to system settings, because asking again after a
      // permanent denial shows them nothing.
      expect(const LocationDenied().permanently, isFalse);
      expect(const LocationDenied(permanently: true).permanently, isTrue);
    });
  });
}
