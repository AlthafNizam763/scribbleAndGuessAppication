import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/utils/validators.dart';
import 'package:scribble_guess/data/api/auth_api.dart';

/// The client half of email sign-in.
///
/// Two things are worth pinning here and they fail in opposite directions.
///
/// The validators must not be *stricter* than the server: a pattern that
/// rejects a real address turns a working account into one its owner cannot
/// sign in to, and no error message would explain why. They also must not be
/// looser about the one rule that is a real bound — a password the server will
/// refuse should be caught before the round trip.
///
/// [AuthSession.fromJson] must read the provider the server sends, because
/// every "you are playing as a guest" affordance keys off it. Getting it wrong
/// silently offers a signed-up player an upgrade they do not need, or — worse
/// — hides it from the guest who does.
void main() {
  group('email validation', () {
    test('accepts ordinary addresses', () {
      for (final String address in <String>[
        'ada@example.com',
        'ada.lovelace@example.co.uk',
        // A plus-tag is a real address and a strict pattern would refuse it.
        'ada+games@example.com',
        'ada@sub.domain.example.org',
      ]) {
        expect(Validators.email(address), isNull, reason: address);
      }
    });

    test('refuses what is obviously not an address', () {
      expect(Validators.email('ada-at-example'), isNotNull);
      expect(Validators.email('ada@example'), isNotNull);
      expect(Validators.email('ada @example.com'), isNotNull);
      expect(Validators.email('@example.com'), isNotNull);
    });

    test('reports an empty field as missing rather than malformed', () {
      // Two different messages because they are two different mistakes.
      expect(Validators.email(''), AppStrings.authEmailRequired);
      expect(Validators.email(null), AppStrings.authEmailRequired);
      expect(Validators.email('nonsense'), AppStrings.authEmailInvalid);
    });

    test('ignores surrounding whitespace, as the server does', () {
      expect(Validators.email('  ada@example.com  '), isNull);
    });
  });

  group('password validation', () {
    test('accepts a new password of exactly the minimum length', () {
      expect(Validators.newPassword('12345678'), isNull);
    });

    test('refuses a new password below it', () {
      expect(Validators.newPassword('1234567'), AppStrings.authPasswordTooShort);
    });

    test('reports an empty new password as missing, not short', () {
      expect(Validators.newPassword(''), AppStrings.authPasswordRequired);
    });

    test('does not impose the length floor when signing in', () {
      // An account made under older rules must still be able to sign in.
      expect(Validators.password('old'), isNull);
    });

    test('still requires a password when signing in', () {
      expect(Validators.password(''), AppStrings.authPasswordRequired);
      expect(Validators.password(null), AppStrings.authPasswordRequired);
    });
  });

  group('AuthSession.fromJson', () {
    Map<String, dynamic> payload(String provider) => <String, dynamic>{
          'token': 'a.b.c',
          'user': <String, dynamic>{
            'id': '507f1f77bcf86cd799439011',
            'username': 'Ada',
            'avatarId': 3,
            'avatarColorIndex': 5,
            'provider': provider,
          },
        };

    test('reads the identity the server assigned', () {
      final AuthSession session = AuthSession.fromJson(payload('email'));
      expect(session.token, 'a.b.c');
      expect(session.profile.id, '507f1f77bcf86cd799439011');
      expect(session.profile.name, 'Ada');
      expect(session.profile.avatarId, 3);
      expect(session.profile.avatarColorIndex, 5);
      expect(session.isValid, isTrue);
    });

    test('distinguishes a guest from a signed-up account', () {
      expect(AuthSession.fromJson(payload('guest')).isGuest, isTrue);
      expect(AuthSession.fromJson(payload('email')).isGuest, isFalse);
    });

    test('treats an unknown provider as a guest', () {
      // The conservative reading: every affordance this turns on is an offer
      // to secure the account, which is never harmful to show.
      expect(AuthSession.fromJson(payload('carrier-pigeon')).isGuest, isTrue);
      expect(AuthProvider.fromWire(''), AuthProvider.guest);
    });

    test('keeps a token passed alongside the payload', () {
      // How a resumed session is built: the token came from the keystore, not
      // from the body, because `GET /api/auth/session` does not re-issue one.
      final Map<String, dynamic> body = payload('email')..remove('token');
      final AuthSession session = AuthSession.fromJson(body, token: 'stored');
      expect(session.token, 'stored');
      expect(session.isValid, isTrue);
    });

    test('is invalid when the server sent no usable identity', () {
      final AuthSession session = AuthSession.fromJson(<String, dynamic>{
        'token': '',
        'user': <String, dynamic>{},
      });
      expect(session.isValid, isFalse);
    });
  });
}
