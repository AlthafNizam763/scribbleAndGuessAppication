import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/sketch_button.dart';
import 'package:scribble_guess/core/widgets/sketch_scaffold.dart';
import 'package:scribble_guess/features/progression/achievement_card.dart';
import 'package:scribble_guess/features/progression/xp_progress_widget.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The trophy case, with the XP bar above it.
///
/// ## Why locked entries are shown
///
/// The catalogue is a list of things to aim at, not only a record of what has
/// been done. A player who has unlocked nothing should still open this and see
/// twelve cards with progress on them, which is also the only way the ones
/// that count — "43 / 100 guesses" — mean anything.
///
/// ## Unlocked first
///
/// The sort is here rather than on the server because it is presentation: the
/// server returns the catalogue in its declared order, which is the order the
/// achievements were designed in, and this screen chooses to float what has
/// been earned to the top.
class AchievementsScreen extends ConsumerWidget {
  /// Creates the screen for the local player, or for [userId] when given.
  const AchievementsScreen({this.userId, super.key});

  /// Whose achievements to show. Null means the local player.
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isSelf = userId == null || userId!.isEmpty;

    final AsyncValue<AchievementsPage> page = isSelf
        ? ref
            .watch(progressionProvider)
            .whenData((Progression value) => value.achievements)
        : ref.watch(playerAchievementsProvider(userId!));

    return SketchScaffold(
      title: context.l10n.achievementsTitle,
      padded: false,
      child: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => SketchEmptyState(
          message: error is Failure ? error.message : context.l10n.errorUnknown,
          icon: Icons.cloud_off_outlined,
          action: SketchButton(
            label: context.l10n.retry,
            onPressed: () => _refresh(ref, isSelf: isSelf),
          ),
        ),
        data: (AchievementsPage value) => _Catalogue(
          page: value,
          // The XP bar belongs to the local player; somebody else's level is
          // shown on their profile, not stacked on top of their badges.
          level: isSelf ? ref.watch(playerLevelProvider) : null,
          onRefresh: () => _refresh(ref, isSelf: isSelf),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref, {required bool isSelf}) {
    if (isSelf) return ref.read(progressionProvider.notifier).refresh();
    return ref.read(playerAchievementsProvider(userId!).notifier).refresh();
  }
}

/// The list, with the summary and XP bar pinned above it.
class _Catalogue extends StatelessWidget {
  const _Catalogue({
    required this.page,
    required this.level,
    required this.onRefresh,
  });

  final AchievementsPage page;
  final PlayerLevel? level;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    // Unlocked first, then by how close the rest are — a player scrolling down
    // meets what they nearly have before what they have barely started.
    final List<Achievement> sorted = <Achievement>[...page.items]..sort((
      Achievement a,
      Achievement b,
    ) {
      if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
      return b.fraction.compareTo(a.fraction);
    });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          if (level != null) ...<Widget>[
            XpProgressWidget(level: level!),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(
            context.l10n.achievementsUnlockedOf(page.unlockedCount, page.totalCount),
            style: text.labelMedium?.copyWith(color: colors.inkSoft),
          ),
          const SizedBox(height: AppSpacing.md),
          if (sorted.isEmpty)
            SketchEmptyState(
              message: context.l10n.achievementsEmpty,
              icon: Icons.workspace_premium_outlined,
            )
          else
            for (final Achievement entry in sorted)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AchievementCard(achievement: entry),
              ),
        ],
      ),
    );
  }
}
