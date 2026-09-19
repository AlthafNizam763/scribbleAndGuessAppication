import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/responsive.dart';
import 'package:scribble_guess/features/progression/xp_progress_widget.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/player_stats.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The player's own card: who they are, and what they have done.
///
/// Read-only on purpose. Editing lives in `EditProfileScreen`, one tap away —
/// a profile is something you show people, and a screen with a keyboard and a
/// save button on it is not that.
///
/// ## What is on it, and what is deliberately not
///
/// Six numbers and a game breakdown. Every one of them answers a question a
/// player actually asks about themselves: how much have I played, how often do
/// I win, do I play with people or with Stupids, and which of these games do I
/// actually reach for. The twenty other figures the server will happily send —
/// fast guesses, perfect drawings, best streak — live behind Achievements,
/// because a wall of statistics is not a profile, it is a report.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerProfile? profile = ref.watch(profileProvider);

    // The redirect guard sends a profile-less player to the editor, so this is
    // the brief window before that lands rather than a state worth designing.
    if (profile == null) {
      return AppScaffold(
        title: context.l10n.profileTitle,
        child: const AppLoadingState(),
      );
    }

    final AsyncValue<PlayerCareerStats> stats =
        ref.watch(playerStatsProvider('me'));

    return AppScaffold(
      title: context.l10n.profileTitle,
      padded: false,
      actions: <Widget>[
        AppIconButton(
          tooltip: 'Settings',
          icon: Icons.settings_rounded,
          onPressed: () => context.pushNamed(AppRoutes.settings),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(playerStatsProvider('me')),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pagePadding(context),
          children: <Widget>[
            _Identity(profile: profile),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Edit profile',
              icon: Icons.edit_outlined,
              expand: true,
              onPressed: () => context.pushNamed(AppRoutes.editProfile),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _LevelStrip(),
            stats.when(
              loading: () => const _StatsSkeleton(),
              error: (Object error, StackTrace stack) => _StatsError(
                message: error is Failure
                    ? error.message
                    : context.l10n.errorUnknown,
                onRetry: () => ref.invalidate(playerStatsProvider('me')),
              ),
              data: (PlayerCareerStats career) => _Career(career: career),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Avatar, name and the line under it.
class _Identity extends ConsumerWidget {
  const _Identity({required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isGuest = ref.watch(isAnonymousProvider);

    return Column(
      children: <Widget>[
        PlayerAvatar(
          avatarId: profile.avatarId,
          colorIndex: profile.avatarColorIndex,
          size: context.isCompact ? 96 : 112,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          profile.name,
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(color: colors.text),
        ),
        const SizedBox(height: 2),
        Text(
          isGuest
              ? context.l10n.settingsAccountGuest
              : context.l10n.settingsAccountLinked,
          style: text.bodySmall?.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// Level and XP, with the way through to the trophy case.
///
/// Hidden until it loads rather than shown at zero: a bar reading "level 1,
/// 0 XP" while a read is in flight is wrong for most of the people who see it.
class _LevelStrip extends ConsumerWidget {
  const _LevelStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Progression> progression = ref.watch(progressionProvider);
    if (!progression.hasValue) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        XpProgressWidget(level: progression.value!.level),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: context.l10n.progressionViewAchievements,
          icon: Icons.workspace_premium_outlined,
          expand: true,
          onPressed: () => context.pushNamed(AppRoutes.achievements),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// The record: the six headline numbers, then what they play.
class _Career extends StatelessWidget {
  const _Career({required this.career});

  final PlayerCareerStats career;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    if (!career.hasPlayed) {
      return AppCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BrandMark(size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nothing stupid has happened yet.',
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(color: colors.text),
            ),
            const SizedBox(height: 2),
            Text(
              'Finish a game and your record starts here.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Record', style: text.titleLarge?.copyWith(color: colors.text)),
        const SizedBox(height: AppSpacing.md),
        _StatGrid(
          tiles: <_Stat>[
            _Stat('Played', '${career.gamesPlayed}'),
            _Stat('Won', '${career.gamesWon}'),
            _Stat('Lost', '${career.gamesLost}'),
            _Stat('Win rate', career.winRateLabel),
            _Stat('Online', '${career.onlineGamesPlayed}'),
            // The branded half of the split, named the way the feature is.
            _Stat('With Stupids', '${career.botGamesPlayed}'),
          ],
        ),
        if (career.gamesByGameId.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Text('What you play', style: text.titleLarge?.copyWith(color: colors.text)),
          const SizedBox(height: AppSpacing.md),
          _GameBreakdown(tallies: career.gamesByGameId),
        ],
      ],
    );
  }
}

/// One figure and its label.
class _Stat {
  const _Stat(this.label, this.value);

  final String label;
  final String value;
}

/// The headline numbers, two or three to a row depending on the phone.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_Stat> tiles;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    // Three across is too tight for "With Stupids" on a small phone at a large
    // text scale, so the narrowest screens get two.
    final int columns = context.isCompact ? 2 : 3;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;

        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final _Stat tile in tiles)
              SizedBox(
                width: width,
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        tile.value,
                        maxLines: 1,
                        style: text.headlineSmall?.copyWith(color: colors.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tile.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Matches per game, as bars proportional to the most-played one.
///
/// Relative rather than absolute: the question this answers is "which of these
/// do I play", and a bar scaled to somebody's lifetime total would be a
/// sliver for everybody with more than one game.
class _GameBreakdown extends StatelessWidget {
  const _GameBreakdown({required this.tallies});

  final List<GameTally> tallies;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    // The server sends these ordered, so the first is the largest.
    final int most = tallies.first.played;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < tallies.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Semantics(
              label: '${tallies[i].displayName}, ${tallies[i].played} played',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            tallies[i].displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(color: colors.text),
                          ),
                        ),
                        Text(
                          '${tallies[i].played}',
                          style: text.labelLarge?.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: most == 0 ? 0 : tallies[i].played / most,
                        minHeight: 8,
                        backgroundColor: colors.surfaceActive,
                        color: tallies[i].game?.color ?? colors.accentBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder tiles, sized like the real ones.
///
/// A spinner here would collapse the page and then push it back open, which
/// on a screen somebody opened to read numbers is worse than a moment of grey.
class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading your record',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int row = 0; row < 2; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  for (int column = 0; column < 3; column++) ...<Widget>[
                    if (column > 0) const SizedBox(width: AppSpacing.sm),
                    const Expanded(child: AppSkeleton(height: 72)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown when the record could not be read. The identity above it still shows.
class _StatsError extends StatelessWidget {
  const _StatsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.cloud_off_outlined, size: 18, color: context.palette.textMuted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: context.l10n.retry,
            icon: Icons.refresh,
            expand: true,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
