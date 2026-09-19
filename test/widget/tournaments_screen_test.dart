import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/constants/app_strings.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/app_card.dart';
import 'package:scribble_guess/features/tournaments/tournaments_screen.dart';
import 'package:scribble_guess/models/auto_tournament.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The tournament screen's rules about what it may and may not draw.
///
/// ## Why these are worth a test when they are all absences
///
/// Because an absence is exactly what a refactor puts back. "No create button"
/// and "no second play button" are not properties of a widget — they are
/// properties of the whole screen, and nothing in the type system notices when
/// one reappears. The same goes for the card count: three is the day, and a
/// fourth card would mean either the server broke its own unique index or this
/// screen started inventing rows.
///
/// ## Why the notifier is faked rather than the HTTP client
///
/// The screen reads one provider and draws what is in it. Faking the transport
/// underneath would exercise the API client, the result plumbing and the JSON
/// parsing — all of which have their own tests — to assert something about
/// layout. This replaces the provider with a fixed day and asks what was
/// drawn.
void main() {
  /// A tournament, in whichever state the test needs.
  AutoTournament tournament({
    required String id,
    required String name,
    required DailySlot slot,
    required AutoTournamentStatus status,
    ViewerTournamentState viewer = const ViewerTournamentState(),
    TournamentParticipant? winner,
  }) =>
      AutoTournament(
        id: id,
        tournamentDate: '2026-09-16',
        dailySlot: slot,
        slotNumber: DailySlot.values.indexOf(slot) + 1,
        name: name,
        status: status,
        minPlayers: 4,
        maxPlayers: 16,
        humanPlayerCount: 2,
        botPlayerCount: 0,
        totalPlayers: 2,
        startAtMs: DateTime.utc(2026, 9, 16, 14, 30).millisecondsSinceEpoch,
        viewer: viewer,
        winner: winner,
      );

  /// The whole day, as the server sends it.
  TournamentDay day(List<AutoTournament> rows) => TournamentDay(
        tournamentDate: '2026-09-16',
        timeZone: 'Asia/Kolkata',
        tournaments: rows,
      );

  Widget screenWith(TournamentDay value) => ProviderScope(
        overrides: <Override>[
          tournamentsProvider.overrideWith(() => _FixedDay(value)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppTextDelegate(),
          ],
          home: const TournamentsScreen(),
        ),
      );

  /// The day as it usually looks: one finished, one open, one still to come.
  TournamentDay typicalDay() => day(<AutoTournament>[
        tournament(
          id: 't1',
          name: 'Ink Royale',
          slot: DailySlot.morning,
          status: AutoTournamentStatus.completed,
          winner: const TournamentParticipant(
            registrationId: 'r1',
            displayName: 'Althaf',
          ),
        ),
        tournament(
          id: 't2',
          name: 'Doodle Rush',
          slot: DailySlot.afternoon,
          status: AutoTournamentStatus.registration,
          viewer: const ViewerTournamentState(canRegister: true),
        ),
        tournament(
          id: 't3',
          name: 'Sketch Clash',
          slot: DailySlot.evening,
          status: AutoTournamentStatus.upcoming,
        ),
      ]);

  testWidgets('draws one card per tournament, and no more than three',
      (WidgetTester tester) async {
    await tester.pumpWidget(screenWith(typicalDay()));
    await tester.pumpAndSettle();

    expect(find.text('Ink Royale'), findsOneWidget);
    expect(find.text('Doodle Rush'), findsOneWidget);
    expect(find.text('Sketch Clash'), findsOneWidget);

    // Three rows in, three cards out. The screen adds nothing of its own —
    // no placeholder for a slot that does not exist, which is what the old
    // three-slot listing drew and what made a fourth card conceivable.
    expect(find.byType(AppCard), findsNWidgets(3));
  });

  testWidgets('draws only the cards the day actually has',
      (WidgetTester tester) async {
    // A deployment that first booted at midday never published a morning
    // tournament. Two cards is the truth; a third would be invented.
    await tester.pumpWidget(
      screenWith(
        day(<AutoTournament>[
          tournament(
            id: 't2',
            name: 'Doodle Rush',
            slot: DailySlot.afternoon,
            status: AutoTournamentStatus.registration,
            viewer: const ViewerTournamentState(canRegister: true),
          ),
          tournament(
            id: 't3',
            name: 'Sketch Clash',
            slot: DailySlot.evening,
            status: AutoTournamentStatus.upcoming,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppCard), findsNWidgets(2));
    expect(find.text(AppStrings.tournamentSlotEmpty), findsNothing);
  });

  testWidgets('offers no way to create a tournament',
      (WidgetTester tester) async {
    await tester.pumpWidget(screenWith(typicalDay()));
    await tester.pumpAndSettle();

    // The organiser is the backend. There is no route for these, so a button
    // for one would be a button that cannot work.
    expect(find.textContaining('Create'), findsNothing);
    expect(find.textContaining('New Tournament'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  /// Quick Play lives on the home screen, once. A second, unrelated verb on a
  /// tournament card is how a player ends up in an ordinary public room
  /// believing they entered the tournament they were reading about.
  testWidgets('offers no Quick Play or Play Now anywhere on the screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(screenWith(typicalDay()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Quick Play'), findsNothing);
    expect(find.textContaining('Play Now'), findsNothing);
  });

  testWidgets('shows a join button only on the tournament taking entries',
      (WidgetTester tester) async {
    await tester.pumpWidget(screenWith(typicalDay()));
    await tester.pumpAndSettle();

    // One card can be joined, so exactly one join button exists — not one per
    // card, and not one on the finished or scheduled ones.
    expect(find.text(AppStrings.tournamentJoin), findsOneWidget);
  });

  /// The winner belongs to the tournament that was won. A screen that painted
  /// it anywhere else would be the exact failure the snapshot on the server
  /// exists to prevent.
  testWidgets('shows a winner on the finished card and nowhere else',
      (WidgetTester tester) async {
    await tester.pumpWidget(screenWith(typicalDay()));
    await tester.pumpAndSettle();

    expect(find.text('Althaf'), findsOneWidget);
  });

  testWidgets('shows no join button on a completed tournament',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      screenWith(
        day(<AutoTournament>[
          tournament(
            id: 't1',
            name: 'Ink Royale',
            slot: DailySlot.morning,
            status: AutoTournamentStatus.completed,
            winner: const TournamentParticipant(
              registrationId: 'r1',
              displayName: 'Althaf',
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.tournamentJoin), findsNothing);
    expect(find.text(AppStrings.tournamentViewResult), findsOneWidget);
  });

  testWidgets('shows no join button on a cancelled tournament',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      screenWith(
        day(<AutoTournament>[
          tournament(
            id: 't1',
            name: 'Ink Royale',
            slot: DailySlot.morning,
            status: AutoTournamentStatus.cancelled,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.tournamentJoin), findsNothing);
    expect(find.text(AppStrings.tournamentEnterMatch), findsNothing);
  });

  /// "Enter Match" appears only for a player the server has actually called to
  /// one. Drawing it otherwise would be a button that 404s.
  testWidgets('shows no Enter Match button without an assigned match',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      screenWith(
        day(<AutoTournament>[
          tournament(
            id: 't1',
            name: 'Ink Royale',
            slot: DailySlot.morning,
            status: AutoTournamentStatus.running,
            viewer: const ViewerTournamentState(isRegistered: true),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.tournamentEnterMatch), findsNothing);
  });

  testWidgets('shows Enter Match when the server assigned one',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      screenWith(
        day(<AutoTournament>[
          tournament(
            id: 't1',
            name: 'Ink Royale',
            slot: DailySlot.morning,
            status: AutoTournamentStatus.running,
            viewer: const ViewerTournamentState(
              isRegistered: true,
              activeMatch: ViewerMatch(matchId: 'm1', roomCode: 'AB12C'),
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.tournamentEnterMatch), findsOneWidget);
  });

  testWidgets('says so plainly when the day has nothing on it',
      (WidgetTester tester) async {
    await tester.pumpWidget(screenWith(day(const <AutoTournament>[])));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.tournamentNoneToday), findsOneWidget);
    expect(find.text(AppStrings.tournamentJoin), findsNothing);
  });
}

/// A notifier that hands back one fixed day and never asks the network.
class _FixedDay extends TournamentsNotifier {
  _FixedDay(this._day);

  final TournamentDay _day;

  @override
  Future<TournamentDay> build() async => _day;
}
