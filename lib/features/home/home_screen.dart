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
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/social_widgets.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The STUPID GAMES home.
///
/// Two jobs, in this order, because it is the order a player wants them in:
///
/// 1. **Quick Match** — rooms with actual people in them, right now, across
///    every game. Read from the server on every visit; nothing on this strip
///    is hardcoded, and it is not limited to one game.
/// 2. **The games** — the catalogue, each with its two ways in: online, or
///    against Stupids.
///
/// Note what is *not* here: a Scribble & Guess title. Scribble & Guess is one
/// of the games. The application is STUPID GAMES, and that distinction is the
/// whole point of this screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerProfile? profile = ref.watch(profileProvider);
    final int invitations = ref.watch(pendingInvitationCountProvider);
    final int unread = ref.watch(unreadNotificationCountProvider);

    return AppScaffold(
      banner: const ConnectionBanner(),
      padded: false,
      child: RefreshIndicator(
        onRefresh: () => ref.read(roomDiscoveryProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pagePadding(context),
          children: <Widget>[
            const SizedBox(height: AppSpacing.xs),
            _HubHeader(profile: profile, unread: unread),
            const SizedBox(height: AppSpacing.xl),
            const _QuickMatchSection(),
            const SizedBox(height: AppSpacing.xxl),
            const AppSectionHeading(
              title: 'Games',
              subtitle: 'Play with people, or with Stupids.',
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final GameDefinition game in GameCatalog.all) ...<Widget>[
              GameCard(game: game),
              const SizedBox(height: AppSpacing.md),
            ],
            const SizedBox(height: AppSpacing.md),
            _SocialRow(invitations: invitations),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.profile, required this.unread});

  final PlayerProfile? profile;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // The cat, not a generic controller glyph. It is the one thing on this
        // screen that says which app this is. It sits on its own washed plate
        // so the mark reads as a badge rather than as a floating sticker.
        Container(
          height: 46,
          width: 46,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.primaryWash,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: const BrandMark(size: 40, semanticLabel: 'STUPID GAMES'),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const BrandWordmark(height: 20),
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
        CountBadge(
          count: unread,
          child: AppIconButton(
            tooltip: 'Notifications',
            icon: Icons.notifications_none_rounded,
            onPressed: () => context.pushNamed(AppRoutes.notifications),
          ),
        ),
        if (profile != null) ...<Widget>[
          const SizedBox(width: AppSpacing.sm),
          PressableScale(
            semanticLabel: 'Your profile',
            onTap: () => context.pushNamed(AppRoutes.profile),
            child: PlayerAvatar.ofProfile(profile!, size: 44),
          ),
        ],
      ],
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

/// One open room in Quick Match, with its Join button.
///
/// Joining goes through the route the *server* tagged the row with, so this
/// card works for a game this build has never heard of. A refusal — the room
/// filled while the list sat on screen — shows the server's own sentence and
/// refreshes the list, because a room that just filled is a room somebody else
/// just joined and the rest of the list has probably moved too.
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
              // The seat was taken — the server said so — but this build has
              // no lobby for that game. Saying so beats a blank screen or a
              // silent no-op on a tap that actually did something.
              notify(
                context,
                'Update the app to play this game.',
                isError: true,
              );
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

/// One game, with both ways into it.
///
/// **PLAY ONLINE** and **PLAY WITH STUPID** are given equal weight on purpose.
/// Playing against bots is not a consolation prize on this platform — the
/// Stupids are characters in it, and a player alone at midnight should not feel
/// they are using the fallback.
class GameCard extends StatelessWidget {
  /// Creates a card for [game].
  const GameCard({required this.game, super.key});

  /// The catalogue entry.
  final GameDefinition game;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

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
              // The head of the card is washed in the game's own colour. It is
              // the only place a non-primary colour fills a surface, and it is
              // what makes five cards in a column instantly distinguishable
              // while they are being scrolled past.
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: colors.wash(game.color),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusLg - 1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    GameGlyph(gameId: game.gameId, color: game.color, size: 56),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            game.displayName,
                            style: text.headlineSmall?.copyWith(
                              color: colors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            game.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: <Widget>[
                              HudBadge(
                                label:
                                    '${game.minPlayers}-${game.maxPlayers} PLAYERS',
                                icon: Icons.group_rounded,
                                color: game.color,
                              ),
                              // Whether this one can be played right now on its
                              // own. The single most useful thing on the card
                              // for somebody opening the app with nobody around:
                              // "online" games need a queue, a game with bots
                              // starts the moment you press it.
                              if (game.supportsBots) ...<Widget>[
                                const SizedBox(width: AppSpacing.xs + 2),
                                HudBadge(
                                  label: 'BOTS',
                                  icon: Icons.smart_toy_rounded,
                                  color: colors.success,
                                ),
                              ],
                              if (game.supportsVoice) ...<Widget>[
                                const SizedBox(width: AppSpacing.xs + 2),
                                HudBadge(
                                  label: 'VOICE',
                                  icon: Icons.mic_rounded,
                                  color: colors.textMuted,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                // Wrap rather than Row: "PLAY WITH STUPID" is a long label, and
                // on a narrow phone at large text scale two buttons side by side
                // would either clip or overflow. This lets them stack instead.
                child: Wrap(
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
// Social
// ---------------------------------------------------------------------------

class _SocialRow extends StatelessWidget {
  const _SocialRow({required this.invitations});

  final int invitations;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: CountBadge(
            count: invitations,
            child: AppButton(
              label: 'Invites',
              icon: Icons.mail_outline_rounded,
              expand: true,
              onPressed: () => context.pushNamed(AppRoutes.roomInvitations),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppButton(
            label: 'Friends',
            icon: Icons.group_outlined,
            expand: true,
            onPressed: () => context.pushNamed(AppRoutes.friends),
          ),
        ),
      ],
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
