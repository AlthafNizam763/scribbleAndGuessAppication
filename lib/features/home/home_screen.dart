import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/config/app_brand_config.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/discovered_room.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/social_widgets.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The STUPID GAMES hub.
///
/// Top to bottom it answers, in order, the four things a player opens the app
/// wanting to know:
///
/// 1. **The slab** — who I am, how far along I am, and the one button that
///    puts me at a table without making me choose anything.
/// 2. **Quick access** — open a room, punch in a code, see what is left to
///    earn.
/// 3. **Quick Match** — rooms with actual people in them, right now, across
///    every game. Read from the server on every visit; nothing on this strip
///    is hardcoded, and it is not limited to one game.
/// 4. **Choose your world** — the catalogue, filterable, each game with its
///    two ways in: online, or against Stupids.
///
/// Note what is *not* here: a Scribble & Guess title. Scribble & Guess is one
/// of the games. The application is STUPID GAMES, and that distinction is the
/// whole point of this screen.
///
/// Stateful for exactly one reason: the catalogue filter. It is a preference
/// about this visit, not about this player — somebody who narrows the list to
/// Cards does not want to find it still narrowed next week — so it lives here
/// rather than in a provider.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates the hub.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  GameFilter _filter = GameFilter.all;

  @override
  Widget build(BuildContext context) {
    final PlayerProfile? profile = ref.watch(profileProvider);
    final int invitations = ref.watch(pendingInvitationCountProvider);
    final int unread = ref.watch(unreadNotificationCountProvider);
    final PlayerLevel level = ref.watch(playerLevelProvider);

    final List<GameDefinition> games = GameCatalog.all
        .where(_filter.matches)
        .toList(growable: false);

    return AppScaffold(
      banner: const ConnectionBanner(),
      padded: false,
      floatingBottom: true,
      bottom: HubNavBar(current: HubTab.games, invitations: invitations),
      child: RefreshIndicator(
        onRefresh: () => ref.read(roomDiscoveryProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pagePadding(context),
          children: <Widget>[
            const SizedBox(height: AppSpacing.xs),
            _HubHeader(unread: unread, level: level),
            const SizedBox(height: AppSpacing.lg),
            _HeroSlab(profile: profile, level: level),
            const SizedBox(height: AppSpacing.md),
            const _QuickAccessRow(),
            const SizedBox(height: AppSpacing.xxl),
            const _QuickMatchSection(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeading(
              title: 'Choose your world',
              subtitle:
                  '${GameCatalog.all.length} games. Play with people, or with '
                  '${AppBrandConfig.current.botLabelPlural}.',
            ),
            const SizedBox(height: AppSpacing.md),
            _FilterStrip(
              selected: _filter,
              onSelect: (GameFilter filter) => setState(() => _filter = filter),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final GameDefinition game in games) ...<Widget>[
              GameCard(game: game),
              const SizedBox(height: AppSpacing.md),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pigment
// ---------------------------------------------------------------------------

/// The hub's arcade pigments.
///
/// Fixed values rather than palette tokens, and deliberately so: they are only
/// ever painted on surfaces this screen draws itself — the hero slab, and the
/// artwork plate at the head of a game card — and both of those stay night-dark
/// under either theme, the way a console dashboard does. Everything else here
/// (cards, chips, buttons, body text) goes through [AppPalette] like the rest
/// of the app, so the hub still follows the light/dark setting.
abstract final class HubNeon {
  /// The lavender the hub is lit in.
  static const Color violet = Color(0xFFD0BCFF);

  /// The edge under a violet control: its own colour, driven down.
  static const Color violetDeep = Color(0xFF5516BE);

  /// The signal colour — live, connected, online — and nothing else.
  static const Color cyan = Color(0xFF4CD7F6);

  /// The warm counterweight, worn by anything earned.
  static const Color rose = Color(0xFFFFB2B7);

  /// The top of a night slab.
  static const Color slab = Color(0xFF1C2026);

  /// The bottom of a night slab.
  static const Color slabDeep = Color(0xFF0D1015);

  /// Ink on a night slab.
  static const Color ink = Color(0xFFE8EAF2);

  /// Quiet ink on a night slab.
  static const Color inkMuted = Color(0xFF9B95A8);
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.unread, required this.level});

  final int unread;
  final PlayerLevel level;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return Row(
      children: <Widget>[
        // The cat, not a generic controller glyph. It is the one thing up here
        // that says which app this is, and it sits on its own washed plate so
        // the mark reads as a badge rather than as a floating sticker.
        Container(
          height: 42,
          width: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.primaryWash,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: const BrandMark(size: 36, semanticLabel: 'STUPID GAMES'),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // The wordmark is drawn from glyphs that scale with the text
              // setting, which a logo has no business doing — at 1.3 it grows
              // past the space the header can give it. Scaled down to fit
              // instead, so the lockup keeps its proportions either way.
              const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BrandWordmark(height: 18),
              ),
              const SizedBox(height: 3),
              Text(
                AppBrandConfig.current.tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        LevelPill(level: level.level),
        const SizedBox(width: AppSpacing.xs),
        CountBadge(
          count: unread,
          child: AppIconButton(
            tooltip: 'Notifications',
            icon: Icons.notifications_none_rounded,
            onPressed: () => context.pushNamed(AppRoutes.notifications),
          ),
        ),
        AppIconButton(
          tooltip: 'Settings',
          icon: Icons.settings_outlined,
          onPressed: () => context.pushNamed(AppRoutes.settings),
        ),
      ],
    );
  }
}

/// The level number, as a pill.
///
/// One drawing of it, used by the header and by the hero slab, because two
/// drawings of the same number are two things that can disagree.
class LevelPill extends StatelessWidget {
  /// Creates a pill reading `LVL [level]`.
  const LevelPill({required this.level, this.onNight = false, super.key});

  /// The player's level, as the server counts it.
  final int level;

  /// Whether this pill sits on a night slab rather than on a themed surface.
  final bool onNight;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final Color tint = onNight ? HubNeon.violet : colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: onNight ? 0.16 : 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: tint.withValues(alpha: 0.32),
          width: AppSpacing.hairline,
        ),
      ),
      child: Text(
        'LVL $level',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tint,
          fontWeight: AppTypography.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The hero slab
// ---------------------------------------------------------------------------

/// The player, their standing, and the one tap that skips every decision.
///
/// Everything on it is the server's: the level and the XP bar come from
/// progression, the world rank from the leaderboard, the head count from the
/// same room discovery call the Quick Match strip below reads. Nothing here is
/// decoration pretending to be data — if a number has not arrived, its line is
/// not drawn.
class _HeroSlab extends ConsumerWidget {
  const _HeroSlab({required this.profile, required this.level});

  final PlayerProfile? profile;
  final PlayerLevel level;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final int? rank = ref.watch(myWorldRankProvider).valueOrNull?.rank;
    final RoomDiscoveryPage? rooms = ref
        .watch(roomDiscoveryProvider)
        .valueOrNull;
    final int playing =
        rooms?.items.fold<int>(
          0,
          (int sum, DiscoveredRoom room) => sum + room.playerCount,
        ) ??
        0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[HubNeon.slab, HubNeon.slabDeep],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: HubNeon.violet.withValues(alpha: 0.16),
          width: AppSpacing.hairline,
        ),
        boxShadow: AppElevation.glow(HubNeon.violetDeep),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _HeroAvatar(profile: profile, level: level.level),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      profile?.name.isNotEmpty ?? false
                          ? profile!.name
                          : 'Player',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge?.copyWith(color: HubNeon.ink),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        if (level.title.isNotEmpty) ...<Widget>[
                          const Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: HubNeon.rose,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              level.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelMedium?.copyWith(
                                color: HubNeon.ink,
                              ),
                            ),
                          ),
                        ],
                        // The rank arrives a moment after the screen does, and
                        // only if the call succeeds. No placeholder, no dash:
                        // the line simply is not there until it is true.
                        if (rank != null) ...<Widget>[
                          if (level.title.isNotEmpty)
                            Text(
                              '  •  ',
                              style: text.labelSmall?.copyWith(
                                color: HubNeon.inkMuted,
                              ),
                            ),
                          Flexible(
                            child: Text(
                              'Global #$rank',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall?.copyWith(
                                color: HubNeon.cyan,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (playing > 0) _LivePill(label: '$playing playing'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _XpPanel(level: level),
          const SizedBox(height: AppSpacing.lg),
          const _QuickPartyMatchButton(),
        ],
      ),
    );
  }
}

/// The avatar with its level badge hung off the corner.
class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.profile, required this.level});

  final PlayerProfile? profile;
  final int level;

  @override
  Widget build(BuildContext context) {
    final PlayerProfile? profile = this.profile;

    return PressableScale(
      semanticLabel: 'Your profile',
      onTap: () => context.pushNamed(
        profile == null ? AppRoutes.editProfile : AppRoutes.profile,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: AppElevation.glow(HubNeon.violet),
            ),
            child: profile == null
                ? Container(
                    height: 60,
                    width: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: HubNeon.slab,
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: HubNeon.inkMuted,
                    ),
                  )
                : PlayerAvatar.ofProfile(profile, size: 60),
          ),
          Positioned(
            bottom: -4,
            right: -6,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: HubNeon.slabDeep,
                borderRadius: BorderRadius.all(
                  Radius.circular(AppSpacing.radiusPill),
                ),
              ),
              child: LevelPill(level: level, onNight: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// The XP track, in its own sunken well on the slab.
class _XpPanel extends StatelessWidget {
  const _XpPanel({required this.level});

  final PlayerLevel level;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int? remaining = level.xpForNextLevel == null
        ? null
        : level.xpForNextLevel! - level.xpIntoLevel;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Experience',
                  style: text.labelMedium?.copyWith(color: HubNeon.inkMuted),
                ),
              ),
              Text(
                level.progressLabel,
                style: text.labelMedium?.copyWith(
                  color: HubNeon.violet,
                  fontWeight: AppTypography.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _XpBar(fraction: level.progress),
          const SizedBox(height: AppSpacing.sm),
          Text(
            level.isMaxLevel || remaining == null
                ? 'Top level. Nothing left to climb.'
                : '$remaining XP to level ${level.level + 1}',
            style: text.labelSmall?.copyWith(color: HubNeon.rose),
          ),
        ],
      ),
    );
  }
}

/// The bar itself: a lit capsule in an unlit track.
class _XpBar extends StatelessWidget {
  const _XpBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final double value = fraction.clamp(0, 1).toDouble();

    return Semantics(
      label: 'Level progress',
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          height: 8,
          color: Colors.white.withValues(alpha: 0.08),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    HubNeon.violetDeep,
                    HubNeon.violet,
                    HubNeon.cyan,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tap, no decisions: the busiest open room, whatever game it is.
///
/// It is the Quick Match strip's top row with the reading step removed, so it
/// obeys the same server rules — a player already holding a seat is sent back
/// to it rather than being handed a second one, and a room that filled while
/// the screen sat there gets the server's own sentence and a refreshed list.
/// With nothing open at all it falls through to creating a room, because the
/// player pressed a button that promised a game either way.
class _QuickPartyMatchButton extends ConsumerStatefulWidget {
  const _QuickPartyMatchButton();

  @override
  ConsumerState<_QuickPartyMatchButton> createState() =>
      _QuickPartyMatchButtonState();
}

class _QuickPartyMatchButtonState
    extends ConsumerState<_QuickPartyMatchButton> {
  bool _busy = false;

  Future<void> _play() async {
    if (_busy) return;

    final RoomDiscoveryPage? page = ref.read(roomDiscoveryProvider).valueOrNull;

    if (page != null && page.isSeatedElsewhere) {
      context.goNamed(AppRoutes.lobby);
      return;
    }

    final DiscoveredRoom? target = page?.items
        .where((DiscoveredRoom room) => room.freeSeats > 0)
        .firstOrNull;

    if (target == null) {
      unawaited(context.pushNamed(AppRoutes.createRoom));
      return;
    }

    setState(() => _busy = true);
    final Result<JoinedRoomDestination> result = await ref
        .read(roomInviteActionsProvider)
        .joinDiscovered(target);

    if (!mounted) return;
    setState(() => _busy = false);
    landOnJoin(context, ref, result);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return PressableScale(
      semanticLabel: 'Quick party match',
      onTap: _busy ? null : _play,
      child: Container(
        height: AppSpacing.controlHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[HubNeon.violetDeep, HubNeon.violet, HubNeon.cyan],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          boxShadow: AppElevation.glow(HubNeon.violet),
        ),
        child: _busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(HubNeon.slabDeep),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.casino_rounded,
                    size: 22,
                    color: HubNeon.slabDeep,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Flexible, because at the largest text scale this label is
                  // wider than a 400pt phone and the button is not allowed to
                  // grow: the label shrinks to fit rather than the row tearing
                  // through the edge of the slab.
                  Flexible(
                    child: Text(
                      'QUICK PARTY MATCH',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        color: HubNeon.slabDeep,
                        fontWeight: AppTypography.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: HubNeon.slabDeep,
                  ),
                ],
              ),
      ),
    );
  }
}

/// A cyan dot and a count: the house style for "this is happening now".
class _LivePill extends StatelessWidget {
  const _LivePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: HubNeon.slabDeep.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: HubNeon.cyan.withValues(alpha: 0.28),
          width: AppSpacing.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _LiveDot(),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: HubNeon.cyan),
          ),
        ],
      ),
    );
  }
}

/// The pulse behind a live count.
///
/// Stops dead — not slowly, not at a lower amplitude — when the platform asks
/// for reduced motion, because a thing that blinks forever is exactly what that
/// setting is asking us to turn off.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.ambient,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          height: 7,
          width: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: HubNeon.cyan,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: HubNeon.cyan.withValues(
                  alpha: 0.25 + 0.45 * _controller.value,
                ),
                blurRadius: 4 + 5 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Quick access
// ---------------------------------------------------------------------------

/// Three tiles for the three things a player does that are not "find me a game
/// now": open a room of their own, join one by code, and look at what is left
/// to earn.
class _QuickAccessRow extends ConsumerWidget {
  const _QuickAccessRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final AchievementsPage? achievements = ref
        .watch(progressionProvider)
        .valueOrNull
        ?.achievements;

    // IntrinsicHeight, because the three captions are different lengths and
    // three tiles of three different heights is the one thing this row must
    // not be. A stretched Row inside a ListView would be given an infinite
    // height instead; this measures the tallest tile and matches the others.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _QuickTile(
              icon: Icons.lock_open_rounded,
              tint: colors.primary,
              title: 'Custom room',
              caption: 'Your rules',
              onTap: () => context.pushNamed(AppRoutes.createRoom),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _QuickTile(
              icon: Icons.pin_rounded,
              tint: colors.tertiary,
              title: 'Join code',
              caption: 'Straight in',
              onTap: () => context.pushNamed(AppRoutes.joinRoom),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _QuickTile(
              icon: Icons.emoji_events_rounded,
              tint: colors.secondary,
              title: 'Trophies',
              // Until progression answers there is no count to show, so the
              // tile says what it is for instead of showing a hopeful zero.
              caption: achievements == null
                  ? 'What you have won'
                  : '${achievements.unlockedCount} of '
                        '${achievements.totalCount}',
              onTap: () => context.pushNamed(AppRoutes.achievements),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      semanticLabel: '$title. $caption',
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      radius: AppSpacing.radiusMd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: colors.wash(tint),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text.labelLarge?.copyWith(color: colors.text),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text.labelSmall?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Match
// ---------------------------------------------------------------------------

/// Public rooms with people already in them — every game, live from the server.
///
/// Every state this can be in is drawn, because every one of them happens:
/// loading on a cold open, empty at four in the morning, failed on a dead
/// connection, and a list the rest of the time. The empty state is not a dead
/// end — it offers the thing a player with nobody to join actually wants,
/// which is to start a room of their own.
class _QuickMatchSection extends ConsumerWidget {
  const _QuickMatchSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RoomDiscoveryPage> rooms = ref.watch(
      roomDiscoveryProvider,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeading(
          title: 'Quick Match',
          subtitle: 'Open rooms waiting for players.',
          trailing: AppIconButton(
            tooltip: 'Refresh',
            icon: Icons.refresh_rounded,
            onPressed: () => ref.read(roomDiscoveryProvider.notifier).refresh(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        rooms.when(
          loading: () => const _QuickMatchSkeleton(),
          error: (Object error, StackTrace stack) => AppCard(
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.cloud_off_rounded,
                  size: 20,
                  color: context.palette.danger,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    error is Failure
                        ? error.message
                        : 'Could not load open rooms.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  label: 'Retry',
                  size: AppButtonSize.compact,
                  onPressed: () =>
                      ref.read(roomDiscoveryProvider.notifier).refresh(),
                ),
              ],
            ),
          ),
          data: (RoomDiscoveryPage page) => _QuickMatchList(page: page),
        ),
      ],
    );
  }
}

class _QuickMatchList extends StatelessWidget {
  const _QuickMatchList({required this.page});

  final RoomDiscoveryPage page;

  @override
  Widget build(BuildContext context) {
    if (page.isSeatedElsewhere) {
      return _SeatedNotice(code: page.currentRoomCode);
    }

    if (page.items.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: context.palette.wash(context.palette.secondary),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                  ),
                  child: Icon(
                    Icons.bedtime_rounded,
                    size: 20,
                    color: context.palette.secondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Nobody is waiting right now.',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open a room and let the Stupids fill it up.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            // An empty Quick Match is the exact moment somebody needs the
            // Stupids, so the empty state offers them rather than sending the
            // player back to scroll for a game themselves.
            AppButton(
              label:
                  'PLAY WITH ${AppBrandConfig.current.botLabelPlural.toUpperCase()}',
              icon: Icons.psychology_alt_rounded,
              variant: AppButtonVariant.primary,
              expand: true,
              onPressed: () {
                final GameDefinition game = GameCatalog.all.firstWhere(
                  (GameDefinition candidate) => candidate.supportsBots,
                  orElse: () => GameCatalog.all.first,
                );
                context.pushNamed(
                  AppRoutes.gameLobby,
                  pathParameters: <String, String>{'gameId': game.gameId.wire},
                  queryParameters: const <String, String>{'mode': 'stupid'},
                );
              },
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final DiscoveredRoom room in page.items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: QuickMatchCard(room: room),
          ),
      ],
    );
  }
}

/// Shown when the player already holds a seat, with the way back to it.
///
/// The server refuses a second room outright, so this is not a warning about
/// something that might go wrong — it is the refusal, stated before the tap.
class _SeatedNotice extends StatelessWidget {
  const _SeatedNotice({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      selected: true,
      tone: context.palette.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: context.palette.info,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'You are already in a room. Leave it before joining another.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Back to your room ($code)',
            icon: Icons.meeting_room_outlined,
            expand: true,
            onPressed: () => context.goNamed(AppRoutes.lobby),
          ),
        ],
      ),
    );
  }
}

/// Three inert placeholder rows, sized like the real ones.
///
/// A spinner here would collapse the strip to nothing and shove the games list
/// up the screen, then shove it back down a moment later. Placeholders hold the
/// layout still.
class _QuickMatchSkeleton extends StatelessWidget {
  const _QuickMatchSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppSkeleton(height: 80, semanticLabel: 'Loading open rooms'),
          ),
      ],
    );
  }
}

/// Acts on the result of a join: navigates, or says why it could not.
///
/// One function rather than a copy in each caller, because the two places a
/// player can join from — the hero button and a Quick Match row — must land in
/// the same place and refuse in the same words.
void landOnJoin(
  BuildContext context,
  WidgetRef ref,
  Result<JoinedRoomDestination> result,
) {
  switch (result) {
    case Ok<JoinedRoomDestination>(:final JoinedRoomDestination value):
      switch (value.route) {
        case RoomJoinRoute.room:
          context.goNamed(AppRoutes.lobby);
        case RoomJoinRoute.gamePlatform:
          // The platform lobby is per-game and renders from its own room
          // document, so it is named rather than the shared lobby.
          final GameDefinition? game = value.game;
          if (game == null) {
            // The seat was taken — the server said so — but this build has no
            // lobby for that game. Saying so beats a blank screen, or a silent
            // no-op on a tap that actually did something.
            notify(context, 'Update the app to play this game.', isError: true);
          } else {
            unawaited(
              context.pushNamed(
                AppRoutes.gameLobby,
                pathParameters: <String, String>{'gameId': game.gameId.wire},
              ),
            );
          }
      }
    case Err<JoinedRoomDestination>(:final Failure failure):
      notify(context, failure.message, isError: true);
      unawaited(ref.read(roomDiscoveryProvider.notifier).refresh());
  }
}

/// One open room in Quick Match, with its Join button.
///
/// Joining goes through the route the *server* tagged the row with, so this
/// card works for a game this build has never heard of.
class QuickMatchCard extends ConsumerStatefulWidget {
  /// Creates a card for [room].
  const QuickMatchCard({required this.room, super.key});

  /// The room, as the server described it.
  final DiscoveredRoom room;

  @override
  ConsumerState<QuickMatchCard> createState() => _QuickMatchCardState();
}

class _QuickMatchCardState extends ConsumerState<QuickMatchCard> {
  bool _busy = false;

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);

    final Result<JoinedRoomDestination> result = await ref
        .read(roomInviteActionsProvider)
        .joinDiscovered(widget.room);

    if (!mounted) return;
    setState(() => _busy = false);
    landOnJoin(context, ref, result);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final DiscoveredRoom room = widget.room;
    final GameDefinition? game = room.game;
    final Color tint = game?.color ?? colors.accentBlue;

    // One seat left is the thing a player scanning this list is actually
    // looking for, so it is the one piece of metadata allowed to be loud.
    final bool almostFull = room.freeSeats <= 1;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          GameGlyph(gameId: room.gameId, color: tint, size: 46),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  room.gameName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(color: colors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    HudBadge(
                      label: room.occupancy,
                      icon: Icons.group_rounded,
                      color: almostFull ? colors.secondary : colors.textMuted,
                    ),
                    if (almostFull) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs + 2),
                      HudBadge(label: 'LAST SEAT', color: colors.warning),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: 'Join',
            variant: AppButtonVariant.primary,
            size: AppButtonSize.compact,
            busy: _busy,
            onPressed: _busy ? null : _join,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The catalogue
// ---------------------------------------------------------------------------

/// The lenses the catalogue can be read through.
///
/// Client-side, and on purpose: five games is a list a phone filters in a frame
/// and a server round trip would only make it slower. The tags live beside the
/// filter rather than on [GameDefinition] because they are a browsing aid, not
/// a property of the game the server has an opinion about.
enum GameFilter {
  /// Everything in the catalogue.
  all('All games'),

  /// Loud, quick, and good with a crowd.
  party('Party'),

  /// Played with a deck.
  cards('Cards'),

  /// Somebody at the table is lying.
  deduction('Deduction'),

  /// Played on a board.
  board('Board');

  const GameFilter(this.label);

  /// What the chip reads.
  final String label;

  /// Whether [game] belongs under this lens.
  bool matches(GameDefinition game) =>
      this == GameFilter.all ||
      (_gameTags[game.gameId] ?? const <GameFilter>[]).contains(this);

  /// The line above a game's name on its card: its first tag.
  static String kickerOf(GameId? gameId) =>
      (_gameTags[gameId] ?? const <GameFilter>[GameFilter.party]).first.label;
}

const Map<GameId, List<GameFilter>> _gameTags = <GameId, List<GameFilter>>{
  GameId.scribbleGuess: <GameFilter>[GameFilter.party],
  GameId.kazhutha: <GameFilter>[GameFilter.cards, GameFilter.party],
  GameId.bluffBar: <GameFilter>[GameFilter.cards, GameFilter.deduction],
  GameId.spaceMystery: <GameFilter>[GameFilter.deduction, GameFilter.party],
  GameId.ludo: <GameFilter>[GameFilter.board],
};

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.selected, required this.onSelect});

  final GameFilter selected;
  final ValueChanged<GameFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          for (final GameFilter filter in GameFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AppChip(
                label: filter.label,
                selected: filter == selected,
                onTap: () => onSelect(filter),
              ),
            ),
        ],
      ),
    );
  }
}

/// One game, with both ways into it.
///
/// **PLAY ONLINE** and **PLAY WITH STUPID** are given equal weight on purpose.
/// Playing against bots is not a consolation prize on this platform — the
/// Stupids are characters in it, and a player alone at midnight should not feel
/// they are using the fallback.
///
/// A consumer, because the head of the card carries the one number that makes a
/// catalogue feel inhabited: how many people are in open rooms of this game
/// right now, off the same discovery call the Quick Match strip reads. When
/// that is nobody, no badge is drawn — an empty game does not get to claim a
/// crowd.
class GameCard extends ConsumerWidget {
  /// Creates a card for [game].
  const GameCard({required this.game, super.key});

  /// The catalogue entry.
  final GameDefinition game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    final RoomDiscoveryPage? rooms = ref
        .watch(roomDiscoveryProvider)
        .valueOrNull;
    final int playing =
        rooms?.items
            .where((DiscoveredRoom room) => room.gameId == game.gameId)
            .fold<int>(
              0,
              (int sum, DiscoveredRoom room) => sum + room.playerCount,
            ) ??
        0;

    return Semantics(
      container: true,
      label:
          '${game.displayName}, ${game.minPlayers} to ${game.maxPlayers} players',
      // The whole card opens the game's lobby, and sinks slightly while it is
      // held — the same feel every other tappable surface in the shell has,
      // because it is the same widget.
      child: PressableScale(
        semanticLabel: 'Open ${game.displayName}',
        onTap: () => _open(context, bots: false),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _GameArtPlate(game: game, playing: playing),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      game.description,
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.xs + 2,
                      runSpacing: AppSpacing.xs + 2,
                      children: <Widget>[
                        HudBadge(
                          label:
                              '${game.minPlayers}-${game.maxPlayers} PLAYERS',
                          icon: Icons.group_rounded,
                          color: game.color,
                        ),
                        // Whether this one can be played right now on its own.
                        // The single most useful thing on the card for somebody
                        // opening the app with nobody around: "online" games
                        // need a queue, a game with bots starts on the press.
                        if (game.supportsBots)
                          HudBadge(
                            label: 'BOTS',
                            icon: Icons.smart_toy_rounded,
                            color: colors.success,
                          ),
                        if (game.supportsVoice)
                          HudBadge(
                            label: 'VOICE',
                            icon: Icons.mic_rounded,
                            color: colors.textMuted,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Wrap rather than Row: "PLAY WITH STUPID" is a long label,
                    // and on a narrow phone at large text scale two buttons
                    // side by side would either clip or overflow. This lets
                    // them stack instead.
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        AppButton(
                          label: 'PLAY ONLINE',
                          icon: Icons.public_rounded,
                          variant: AppButtonVariant.primary,
                          // The one sanctioned use of a per-instance tone: this
                          // button belongs to the game, not to the app.
                          tone: game.color,
                          onPressed: () => _open(context, bots: false),
                        ),
                        if (game.supportsBots)
                          AppButton(
                            label:
                                'PLAY WITH ${AppBrandConfig.current.botLabel.toUpperCase()}',
                            icon: Icons.psychology_alt_rounded,
                            onPressed: () => _open(context, bots: true),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, {required bool bots}) {
    context.pushNamed(
      AppRoutes.gameLobby,
      pathParameters: <String, String>{'gameId': game.gameId.wire},
      queryParameters: <String, String>{if (bots) 'mode': 'stupid'},
    );
  }
}

/// The illustrated head of a game card — for now, without the illustration.
///
/// The plate is built to the shape real artwork will arrive in: a 168pt band,
/// the game's name and tag burned into the bottom-left corner over a scrim, its
/// badges along the top. What fills it today is the game's own colour, a wash
/// of light from the top corner, and its glyph blown up as a watermark. When
/// `game.banner` becomes a real asset, it drops in as a `Positioned.fill` image
/// beneath the scrim and nothing else on this card has to move.
class _GameArtPlate extends StatelessWidget {
  const _GameArtPlate({required this.game, required this.playing});

  final GameDefinition game;
  final int playing;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color deep = Color.lerp(HubNeon.slabDeep, game.color, 0.35)!;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg - 1),
      ),
      child: SizedBox(
        height: 168,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[deep, HubNeon.slabDeep],
                ),
              ),
            ),
            // The glyph, oversized and half off the edge: enough to give the
            // plate a subject without pretending to be the artwork.
            Positioned(
              right: -26,
              bottom: -22,
              child: Icon(
                GameGlyph.iconFor(game.gameId),
                size: 172,
                color: game.color.withValues(alpha: 0.16),
              ),
            ),
            Positioned(
              left: -40,
              top: -60,
              child: Container(
                height: 180,
                width: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      game.color.withValues(alpha: 0.28),
                      game.color.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // The scrim reaches the card's own surface colour, so the plate
            // hands off to the body rather than stopping against it.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      HubNeon.slabDeep.withValues(alpha: 0.45),
                      colors.surface,
                    ],
                    stops: const <double>[0.35, 0.75, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              top: AppSpacing.md,
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs + 1,
                    ),
                    decoration: BoxDecoration(
                      color: game.color.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusPill,
                      ),
                      border: Border.all(
                        color: game.color.withValues(alpha: 0.4),
                        width: AppSpacing.hairline,
                      ),
                    ),
                    child: Text(
                      GameFilter.kickerOf(game.gameId).toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: game.color,
                        fontWeight: AppTypography.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (playing > 0) _LivePill(label: '$playing playing'),
                ],
              ),
            ),
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.md,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  GameGlyph(gameId: game.gameId, color: game.color, size: 48),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          GameFilter.kickerOf(game.gameId).toUpperCase(),
                          style: text.labelSmall?.copyWith(
                            color: game.color,
                            letterSpacing: 1.4,
                          ),
                        ),
                        Text(
                          game.displayName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.headlineSmall?.copyWith(
                            color: colors.text,
                            fontWeight: AppTypography.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The square colour tile that stands in for a game's artwork.
///
/// A single place for the game-to-glyph mapping, so the home card, the Quick
/// Match row and the lobby header cannot drift apart. It takes a nullable id
/// because Quick Match can surface a game this build does not know about.
class GameGlyph extends StatelessWidget {
  /// Creates a glyph for [gameId].
  const GameGlyph({
    required this.gameId,
    required this.color,
    this.size = 52,
    super.key,
  });

  /// The game, or null for one this build has no definition for.
  final GameId? gameId;

  /// The tile colour.
  final Color color;

  /// Edge of the square.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: AppElevation.glow(color),
      ),
      child: Icon(
        iconFor(gameId),
        color: context.palette.onFill(color),
        size: size * 0.48,
      ),
    );
  }

  /// The glyph for one game. Public so the lobby uses the same mapping.
  static IconData iconFor(GameId? gameId) => switch (gameId) {
    GameId.scribbleGuess => Icons.brush_rounded,
    GameId.kazhutha => Icons.style_rounded,
    GameId.bluffBar => Icons.casino_rounded,
    GameId.spaceMystery => Icons.rocket_launch_rounded,
    GameId.ludo => Icons.grid_view_rounded,
    null => Icons.sports_esports_rounded,
  };
}

// ---------------------------------------------------------------------------
// The shell bar
// ---------------------------------------------------------------------------

/// The five places the hub can send you.
///
/// There is no Chat tab: chat in this app belongs to a room, and a tab that
/// opened an empty transcript would be a promise the product does not keep.
/// Invites takes that seat instead, since it is the one destination that can
/// arrive with something waiting on it.
enum HubTab {
  /// The hub itself.
  games('Games', Icons.sports_esports_rounded, AppRoutes.home),

  /// The friend list.
  friends('Friends', Icons.group_rounded, AppRoutes.friends),

  /// The leaderboard.
  rank('Rank', Icons.emoji_events_rounded, AppRoutes.leaderboard),

  /// Room invitations.
  invites(
    'Invites',
    Icons.mark_email_unread_rounded,
    AppRoutes.roomInvitations,
  ),

  /// This player.
  profile('Profile', Icons.person_rounded, AppRoutes.profile);

  const HubTab(this.label, this.icon, this.route);

  /// What the tab reads.
  final String label;

  /// Its glyph.
  final IconData icon;

  /// The named route it opens.
  final String route;
}

/// The hub's bottom bar.
///
/// It pushes rather than swapping a body, because these are five real screens
/// with their own back behaviour, not five panes of one. The current tab is
/// inert: pressing the tab you are already on should do nothing, and a stack of
/// eleven copies of the hub is what happens when it does not.
class HubNavBar extends StatelessWidget {
  /// Creates the bar, with [current] drawn as selected.
  const HubNavBar({required this.current, this.invitations = 0, super.key});

  /// The tab this screen is.
  final HubTab current;

  /// How many invitations are waiting, for the badge on that tab.
  final int invitations;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // Five equal columns rather than five intrinsic widths: the labels are
        // different lengths and the bar has to survive a 360pt phone at large
        // text scale without a single pixel of overflow.
        for (final HubTab tab in HubTab.values)
          Expanded(
            child: _NavItem(
              tab: tab,
              selected: tab == current,
              badge: tab == HubTab.invites ? invitations : 0,
              onTap: tab == current ? null : () => context.pushNamed(tab.route),
            ),
          ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final HubTab tab;
  final bool selected;
  final int badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final Color ink = selected ? colors.primary : colors.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: PressableScale(
        onTap: onTap,
        child: CountBadge(
          count: badge,
          child: AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.instant),
            curve: AppMotion.standard,
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTapTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? colors.wash(colors.primary)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(tab.icon, size: 22, color: ink),
                const SizedBox(height: 2),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.labelSmall?.copyWith(
                    color: ink,
                    fontWeight: selected
                        ? AppTypography.bold
                        : AppTypography.medium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scribble & Guess Quick Play
// ---------------------------------------------------------------------------

/// The authoritative Scribble & Guess Quick Play button.
///
/// Kept here, and kept working, because it is that game's own matchmaker —
/// it will create a room when there is nothing to join, which the cross-game
/// Quick Match list deliberately does not do. Used from the Scribble lobby.
class QuickPlayButton extends ConsumerStatefulWidget {
  /// Creates the button.
  const QuickPlayButton({super.key});

  @override
  ConsumerState<QuickPlayButton> createState() => _QuickPlayButtonState();
}

class _QuickPlayButtonState extends ConsumerState<QuickPlayButton> {
  bool _busy = false;

  Future<void> _play() async {
    if (_busy) return;
    final PlayerProfile? profile = ref.read(profileProvider);
    if (profile == null) {
      unawaited(context.pushNamed(AppRoutes.editProfile));
      return;
    }

    setState(() => _busy = true);
    final Result<Room> result = await ref
        .read(quickPlayServiceProvider)
        .play(profile);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<Room>():
        context.goNamed(AppRoutes.lobby);
      case Err<Room>(:final Failure failure):
        notify(context, failure.message, isError: true);
        ref.read(quickPlayServiceProvider).reset();
    }
  }

  @override
  Widget build(BuildContext context) => AppButton.primary(
    label: _busy ? 'Finding a room…' : 'PLAY ONLINE',
    icon: Icons.public_rounded,
    busy: _busy,
    expand: true,
    onPressed: _busy ? null : _play,
  );
}
