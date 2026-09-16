import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/avatar_art.dart';
import 'package:scribble_guess/widgets/player_avatar.dart';

/// Tests for the character avatars.
///
/// The catalogue is the one place in the app where a constant and a list have
/// to agree: `AppConstants.avatarCount` is what the randomiser and the picker
/// count up to, while `AvatarCatalog.faces` is what actually gets drawn. If
/// they drift, players are offered faces that do not exist — or never see the
/// ones that do.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: child)),
      );

  group('AvatarCatalog', () {
    test('holds exactly avatarCount faces, in id order', () {
      expect(AvatarCatalog.faces, hasLength(AppConstants.avatarCount));
      for (int i = 0; i < AvatarCatalog.faces.length; i++) {
        expect(AvatarCatalog.faces[i].id, i);
      }
    });

    test('gives every family the same number of faces', () {
      final int perKind = AppConstants.avatarCount ~/ AvatarKind.values.length;
      for (final AvatarKind kind in AvatarKind.values) {
        expect(AvatarCatalog.of(kind), hasLength(perKind), reason: kind.name);
      }
    });

    test('draws a different shape for every id', () {
      final Set<AvatarShape> shapes =
          AvatarCatalog.faces.map((AvatarFace f) => f.shape).toSet();
      expect(shapes, hasLength(AppConstants.avatarCount));
    });

    test('resolves any id, including out of range and negative', () {
      // Ids arrive off the wire and out of older builds, so the lookup wraps
      // rather than throwing in the middle of a room.
      expect(AvatarCatalog.faceAt(0).id, 0);
      expect(AvatarCatalog.faceAt(AppConstants.avatarCount).id, 0);
      expect(AvatarCatalog.faceAt(-1).id, 1);
      expect(AvatarCatalog.faceAt(9999), isNotNull);
    });
  });

  group('PlayerAvatar', () {
    testWidgets('paints a character at every size it is used at',
        (WidgetTester tester) async {
      for (final double size in <double>[26, 38, 48, 96]) {
        await tester.pumpWidget(
          wrap(PlayerAvatar(avatarId: 7, colorIndex: 3, size: size)),
        );
        expect(find.byType(CustomPaint), findsWidgets);
        expect(tester.getSize(find.byType(PlayerAvatar)), Size.square(size));
      }
    });

    testWidgets('names the character for screen readers',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const PlayerAvatar(avatarId: 6, colorIndex: 0)),
      );
      expect(
        find.bySemanticsLabel(RegExp(AvatarCatalog.faceAt(6).name)),
        findsOneWidget,
      );
    });

    testWidgets('an out-of-range id still draws', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const PlayerAvatar(avatarId: 4242, colorIndex: 99)),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
