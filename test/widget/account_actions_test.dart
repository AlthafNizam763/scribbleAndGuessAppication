import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/features/settings/account_actions.dart';
import 'package:scribble_guess/providers/providers.dart';

/// The two irreversible controls, and the friction in front of them.
///
/// ## Why the friction is what is tested, not the deletion
///
/// The deletion itself is the server's, and it has its own tests against a
/// real database. What this file pins is the part that lives entirely in the
/// UI and that a refactor can quietly remove: **a single tap must never delete
/// an account.** There are two dialogs, the second one asks for a typed word,
/// and its confirm button stays disabled until that word is right. None of
/// those is expressible in a type, and all three are one careless edit away
/// from being gone.
///
/// Nothing here signs anything out: every assertion stops at or before the
/// confirmation, so no provider is reached and no fake is needed for them.
void main() {
  // The section watches one derived boolean to choose which warning the
  // log-out dialog carries. Overridden directly rather than bootstrapping the
  // session and preference stores it is normally derived from — this file is
  // about the dialogs, not about how guest-ness is decided.
  Widget host() => ProviderScope(
        overrides: <Override>[
          isAnonymousProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AccountActionsSection()),
          ),
        ),
      );

  group('the section itself', () {
    testWidgets('offers log out and delete, and says which is permanent', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host());

      expect(find.text('LOG OUT'), findsOneWidget);
      expect(find.text('DELETE ACCOUNT'), findsOneWidget);
      // The distinction is the whole reason these two sit together: one is
      // recoverable and the other is not, and the player is told so before
      // either is tapped.
      expect(find.textContaining('Deleting is permanent'), findsOneWidget);
    });
  });

  group('logging out', () {
    testWidgets('asks first, and does nothing when cancelled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text('LOG OUT'));
      await tester.pumpAndSettle();

      expect(find.text('Log out of STUPID GAMES?'), findsOneWidget);

      // Dismissing has to leave the screen exactly as it was — the section is
      // still there, not a spinner or a half-torn-down session.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountActionsSection), findsOneWidget);
    });
  });

  group('deleting an account', () {
    testWidgets('the first tap only warns', (WidgetTester tester) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text('DELETE ACCOUNT'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your account?'), findsOneWidget);
      // Nothing has been deleted and nothing can be yet: this dialog's
      // affirmative only opens the next one.
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.text('Type DELETE to confirm'), findsNothing);
    });

    testWidgets('a second dialog asks for the word', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text('DELETE ACCOUNT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();

      expect(find.text('Type DELETE to confirm'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('the confirm button stays dead until the word is right', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text('DELETE ACCOUNT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();

      TextButton confirm() => tester.widget<TextButton>(
            find.widgetWithText(TextButton, 'DELETE ACCOUNT'),
          );

      // A live button that then refuses would be the same dismissable dialog
      // this exists to avoid, so it is disabled rather than validating on tap.
      expect(confirm().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delet');
      await tester.pump();
      expect(confirm().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      // Case-insensitive on purpose: this is a speed bump against a reflex,
      // not a spelling test.
      expect(confirm().onPressed, isNotNull);
    });

    testWidgets('backing out of the second dialog deletes nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text('DELETE ACCOUNT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountActionsSection), findsOneWidget);
      expect(find.text('Type DELETE to confirm'), findsNothing);
    });
  });
}
