import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/progression_api.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/core_providers.dart';

/// Levels, XP and achievements.
///
/// ## Where the truth is
///
/// Entirely the server, and more strictly than anywhere else in this app.
/// There is no optimistic update in this file and no arithmetic: the app never
/// adds XP to its own total, never decides a threshold was crossed, and never
/// marks an achievement unlocked. Every number here arrived in a response.
///
/// That is not caution for its own sake — it is what makes the displayed level
/// match the one the leaderboard sorts by. A client that predicted its own XP
/// would be right until it missed a match report, and then wrong forever.
///
/// ## What realtime carries
///
/// One event: `s:progression:levelUp`. It exists for the animation, which has
/// to play while the result screen is still on screen. The authoritative
/// figures still come from the next read, and that read wins.

/// The progression endpoints.
final Provider<ProgressionApi> progressionApiProvider = Provider<ProgressionApi>(
  (Ref ref) => ProgressionApi(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Realtime
// ---------------------------------------------------------------------------

/// A level-up, as the server announces it.
///
/// Carries the level and its title so a banner can be drawn the instant it
/// lands. Malformed payloads are dropped rather than surfaced: a level-up
/// banner with no level is a banner with nothing to say.
final StreamProvider<({int level, String title})> levelUpProvider =
    StreamProvider<({int level, String title})>(
  (Ref ref) => ref
      .watch(gatewayProvider)
      .inbound
      .where(
        (({String event, Map<String, dynamic> data}) message) =>
            message.event == SocketEvents.serverProgressionLevelUp,
      )
      .map((({String event, Map<String, dynamic> data}) message) {
        AppLogger.d('Progression: level up');
        return (
          level: asInt(message.data['level']),
          title: asString(message.data['title']),
        );
      })
      .where((({int level, String title}) event) => event.level > 0),
);

/// What the last finished match paid the local player.
///
/// Read off `s:game:end`, which carries a per-viewer `progression` block
/// beside the standings — the server builds one per recipient, so this is
/// always the local player's own report and never anybody else's.
///
/// ## Why this is a provider and not a field on the game repository
///
/// The repository's job is the *game*: state, rounds, the board. A payout is
/// a different concern that happens to ride on the same event, and threading
/// it through the repository interface would mean changing every
/// implementation of that interface — including the retired Firebase one — to
/// carry something only this feature reads.
///
/// A match that paid nothing (an abandoned game, a player who left) sends
/// `null` here, and the result screen simply shows no payout section.
final StreamProvider<MatchProgression> matchProgressionProvider =
    StreamProvider<MatchProgression>(
  (Ref ref) => ref
      .watch(gatewayProvider)
      .inbound
      .where(
        (({String event, Map<String, dynamic> data}) message) =>
            message.event == SocketEvents.serverGameEnd,
      )
      .map(
        (({String event, Map<String, dynamic> data}) message) =>
            MatchProgression.fromJson(asMap(message.data['progression'])),
      )
      .where((MatchProgression report) => !report.isEmpty),
);

// ---------------------------------------------------------------------------
// The player's standing
// ---------------------------------------------------------------------------

/// The local player's level and achievement catalogue.
///
/// Not autodisposing: the XP bar is read from the profile screen and from the
/// result screen, and a provider thrown away between them would mean the bar
/// starting empty every time it is looked at.
class ProgressionNotifier extends AsyncNotifier<Progression> {
  ProgressionApi get _api => ref.read(progressionApiProvider);

  @override
  Future<Progression> build() async {
    // A level-up means the figures this holds are stale. `listen` rather than
    // `watch` so the push refreshes the data instead of rebuilding the
    // provider and re-entering `build` from the top.
    ref.listen<AsyncValue<({int level, String title})>>(
      levelUpProvider,
      (
        AsyncValue<({int level, String title})>? previous,
        AsyncValue<({int level, String title})> next,
      ) {
        if (next.hasValue) unawaited(refresh());
      },
    );

    return _load();
  }

  Future<Progression> _load() async {
    final Result<Progression> result = await _api.me();

    return switch (result) {
      Ok<Progression>(:final Progression value) => value,
      // Thrown rather than returned so the screen's error branch renders,
      // which is where the retry button lives.
      Err<Progression>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads level and achievements. Used by pull-to-refresh and after a match.
  Future<void> refresh() async {
    try {
      state = AsyncValue<Progression>.data(await _load());
    } on Failure catch (failure, stack) {
      state = AsyncValue<Progression>.error(failure, stack);
    }
  }
}

/// The local player's progression.
final AsyncNotifierProvider<ProgressionNotifier, Progression> progressionProvider =
    AsyncNotifierProvider<ProgressionNotifier, Progression>(
  ProgressionNotifier.new,
);

/// Just the level, for the XP bar on the profile and home screens.
///
/// A level-1 account while loading or failed, which is what an account with no
/// XP is — so the bar renders empty rather than absent.
final Provider<PlayerLevel> playerLevelProvider = Provider<PlayerLevel>(
  (Ref ref) =>
      ref.watch(progressionProvider).valueOrNull?.level ?? const PlayerLevel(),
);

// ---------------------------------------------------------------------------
// Another player's badges
// ---------------------------------------------------------------------------

/// The achievement catalogue for one player, keyed by their id.
///
/// Autodisposing and family-keyed: this backs the badges on somebody else's
/// profile, which is a screen the player opens, reads and leaves. Holding
/// every profile ever viewed would be a cache nothing invalidates.
class PlayerAchievementsNotifier
    extends AutoDisposeFamilyAsyncNotifier<AchievementsPage, String> {
  @override
  Future<AchievementsPage> build(String arg) async {
    final Result<AchievementsPage> result =
        await ref.read(progressionApiProvider).achievements(userId: arg);

    return switch (result) {
      Ok<AchievementsPage>(:final AchievementsPage value) => value,
      Err<AchievementsPage>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the catalogue.
  Future<void> refresh() async {
    state = await AsyncValue.guard<AchievementsPage>(() => build(arg));
  }
}

/// One player's achievements, keyed by their id.
final AutoDisposeAsyncNotifierProviderFamily<PlayerAchievementsNotifier,
    AchievementsPage, String> playerAchievementsProvider =
    AsyncNotifierProvider.autoDispose
        .family<PlayerAchievementsNotifier, AchievementsPage, String>(
  PlayerAchievementsNotifier.new,
);

// ---------------------------------------------------------------------------
// XP history
// ---------------------------------------------------------------------------

/// The local player's recent XP awards, newest first.
///
/// Autodisposing: it is a detail screen, and the rows are only meaningful next
/// to the balance they explain — which is re-read whenever it is shown.
final AutoDisposeFutureProvider<List<XpEvent>> xpHistoryProvider =
    FutureProvider.autoDispose<List<XpEvent>>((Ref ref) async {
  final Result<List<XpEvent>> result =
      await ref.read(progressionApiProvider).xpHistory();

  return switch (result) {
    Ok<List<XpEvent>>(:final List<XpEvent> value) => value,
    Err<List<XpEvent>>(:final Failure failure) => throw failure,
  };
});
