import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/config/app_brand_config.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/features/games/common/game_orientation.dart';
import 'package:scribble_guess/features/home/home_screen.dart';
import 'package:scribble_guess/models/game_definition.dart';
import 'package:scribble_guess/models/platform_room.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// One game's front door: what it is, and the two ways into it.
///
/// Preserves the original Scribble & Guess flow — which has its own mature
/// room service and its own matchmaker — and drives the newer games through
/// the generic platform API. The split is deliberate and lives here rather
/// than leaking into every caller.
class GameLobbyScreen extends ConsumerStatefulWidget {
  const GameLobbyScreen({required this.game, this.wantsStupids = false, super.key});

  /// The catalogue entry for this game.
  final GameDefinition game;

  /// Whether the player arrived by tapping PLAY WITH STUPID.
  ///
  /// Only a hint about intent: it cannot seat a bot on its own, because a
  /// Stupid is seated into a *room* and there is no room yet. What it does is
  /// send the player down the hosting path rather than the matchmaking one, so
  /// the lobby they land in is theirs and the Stupid controls are enabled.
  final bool wantsStupids;

  @override
  ConsumerState<GameLobbyScreen> createState() => _GameLobbyScreenState();
}

class _GameLobbyScreenState extends ConsumerState<GameLobbyScreen> {
  bool _busy = false;

  /// How hard any Stupids seated from here will play.
  ///
  /// Kept on the screen rather than on the room because it describes the
  /// *next* batch: a host can seat two easy bots and then two hard ones, and
  /// the server records the difficulty on each seat as it is filled.
  BotDifficulty _difficulty = BotDifficulty.medium;

  /// True once this screen has sent the player into the match, so a rebuild
  /// arriving a frame later does not push a second copy of the game screen.
  bool _entered = false;

  /// The room, as the socket last reported it.
  ///
  /// Read from the session rather than held here: seating a bot, somebody
  /// joining and the match starting all arrive as broadcasts, and a local
  /// copy updated only by this screen's own REST replies would show the host
  /// a room nobody else was in.
  PlatformRoom? get _room => ref.watch(platformSessionProvider).room;

  /// Opens a room: private when [private], matched otherwise.
  Future<void> _open({required bool private}) async {
    if (_busy) return;

    if (widget.game.gameId == GameId.scribbleGuess) {
      unawaited(context.pushNamed(private ? AppRoutes.createRoom : AppRoutes.joinRoom));
      return;
    }

    setState(() => _busy = true);
    final Result<PlatformRoom> result = private
        ? await ref.read(gamesApiProvider).createPrivateRoom(widget.game)
        : await ref.read(gamesApiProvider).quickMatch(widget.game);
    if (!mounted) return;

    if (result case Err<PlatformRoom>(:final Failure failure)) {
      setState(() => _busy = false);
      notify(context, failure.message, isError: true);
      return;
    }

    final PlatformRoom room = (result as Ok<PlatformRoom>).value;

    // The bridge between the REST lobby and the realtime game.
    //
    // The call above created the room over HTTP, and an HTTP call has no
    // socket — so this connection is in none of the room's channels and would
    // receive nothing at all. `open` attaches it. Without this line the lobby
    // works perfectly and the match never arrives, which is exactly the state
    // this screen used to be in.
    final Result<PlatformRoom> attached = await ref
        .read(platformSessionProvider.notifier)
        .open(widget.game.gameId, room.roomId);
    if (!mounted) return;

    setState(() => _busy = false);
    if (attached case Err<PlatformRoom>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
    }
  }

  /// Seats [count] Stupids in the room this screen opened.
  ///
  /// The count comes back from the server rather than being assumed: an ask of
  /// three into two free seats fills two, and the card should say two.
  Future<void> _addStupids(int count) async {
    final PlatformRoom? room = _room;
    if (room == null || _busy) return;

    setState(() => _busy = true);
    final Result<PlatformRoom> result = await ref
        .read(gamesApiProvider)
        .addStupids(widget.game, room.roomId, count: count, difficulty: _difficulty);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err<PlatformRoom>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
    }
    // On success nothing is applied here: the server broadcasts the new roster
    // to everybody in the room, this client included, and the session picks it
    // up. One room, one copy of it.
  }

  Future<void> _clearStupids() async {
    final PlatformRoom? room = _room;
    if (room == null || _busy) return;

    setState(() => _busy = true);
    final Result<PlatformRoom> result = await ref
        .read(gamesApiProvider)
        .clearStupids(widget.game, room.roomId);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err<PlatformRoom>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
    }
  }

  Future<void> _ready() async {
    final PlatformRoom? room = _room;
    if (room == null || _busy) return;

    setState(() => _busy = true);
    final Result<PlatformRoom> result = await ref
        .read(gamesApiProvider)
        .ready(widget.game, room.roomId);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err<PlatformRoom>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
    }
    // Whether that started the match is not decided here. The server starts it
    // when every seat is ready, and says so by broadcasting a match — which is
    // what `_enterMatch` below is watching for. A host who readies up last and
    // a guest who readied first therefore travel on the same signal.
  }

  /// Sends the player into the match, once there is one.
  ///
  /// Driven by the broadcast rather than by the ready call's reply, because
  /// the match can start because of *somebody else's* action — and that player
  /// has to arrive at the table too.
  void _enterMatch() {
    if (_entered) return;

    final PlatformSession session = ref.read(platformSessionProvider);
    if (!session.hasMatch) return;
    if (session.room?.gameId != widget.game.gameId) return;

    _entered = true;
    // After the frame: this runs from `build`, and navigating during a build
    // is what produces the "setState during build" crash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.pushNamed(
        AppRoutes.platformGame,
        pathParameters: <String, String>{'gameId': widget.game.gameId.wire},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final GameDefinition game = widget.game;
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final PlatformRoom? room = _room;

    // Watched here so the screen rebuilds when the match starts, whoever
    // caused it.
    _enterMatch();

    // Space Mystery is landscape from the front door, not from the match.
    //
    // The brief asks for the whole flow sideways, and the lobby is the first
    // screen of it: a player who readies up in portrait and is thrown into a
    // landscape ship has watched the device rotate under them mid-tap. The
    // claim is counted, so pushing the match — which takes its own — and
    // coming back here leaves this screen's lock still standing.
    return OrientationLock(
      enabled: game.gameId == GameId.spaceMystery,
      child: AppScaffold(
        title: game.displayName,
        padded: false,
        child: ListView(
          padding: pagePadding(context),
          children: <Widget>[
            _GameBanner(game: game),
            const SizedBox(height: AppSpacing.xl),

            if (game.gameId == GameId.scribbleGuess) ...<Widget>[
              const QuickPlayButton(),
              const SizedBox(height: AppSpacing.md),
            ] else ...<Widget>[
              AppButton(
                label: 'PLAY ONLINE',
                icon: Icons.public_rounded,
                variant: AppButtonVariant.primary,
                expand: true,
                busy: _busy,
                onPressed: _busy ? null : () => _open(private: false),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // PLAY WITH STUPID, where the game can actually play them.
            //
            // It opens a room rather than starting a match: a Stupid is seated
            // into a room, so the host makes one and fills it from the lobby.
            // The card below says so, because a button that silently lands
            // somebody on a room-settings screen has not explained itself.
            if (game.supportsBots) ...<Widget>[
              AppButton(
                label: 'PLAY WITH ${AppBrandConfig.current.botLabel.toUpperCase()}',
                icon: Icons.psychology_alt_rounded,
                expand: true,
                onPressed: _busy ? null : () => _open(private: true),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (widget.wantsStupids)
                _StupidsHint(botLabel: AppBrandConfig.current.botLabelPlural),
              const SizedBox(height: AppSpacing.sm),
            ],

            AppButton(
              label: 'Create private room',
              icon: Icons.lock_outline,
              expand: true,
              onPressed: _busy ? null : () => _open(private: true),
            ),
            const SizedBox(height: AppSpacing.xl),

            if (room != null) ...<Widget>[
              _RoomStatus(room: room, onReady: _ready, busy: _busy),
              const SizedBox(height: AppSpacing.md),
              _Roster(room: room),
              const SizedBox(height: AppSpacing.md),
              // Only once a room exists: a Stupid is seated *into* a room, so
              // there is nothing to add one to before this point. This is where
              // PLAY WITH STUPID actually lands.
              if (game.supportsBots) ...<Widget>[
                _StupidsCard(
                  room: room,
                  botLabel: AppBrandConfig.current.botLabel,
                  busy: _busy,
                  difficulty: _difficulty,
                  onDifficulty: (BotDifficulty level) => setState(() => _difficulty = level),
                  onAdd: _addStupids,
                  onClear: _clearStupids,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              const SizedBox(height: AppSpacing.md),
            ],

            Text('Rules', style: text.titleLarge?.copyWith(color: colors.text)),
            const SizedBox(height: AppSpacing.sm),
            for (final String rule in game.rules)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.check_circle_outline, color: game.color, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(rule, style: text.bodyMedium)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),

            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _FeatureChip(
                  icon: Icons.people_outline,
                  label: '${game.minPlayers}–${game.maxPlayers} players',
                ),
                if (game.supportsBots)
                  _FeatureChip(
                    icon: Icons.psychology_alt_rounded,
                    label: AppBrandConfig.current.botLabelPlural,
                  ),
                if (game.supportsVoice)
                  const _FeatureChip(icon: Icons.mic_none_outlined, label: 'Voice chat'),
                if (game.supportsTextChat)
                  const _FeatureChip(icon: Icons.chat_bubble_outline, label: 'Text chat'),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Who is actually in the room, people and Stupids alike.
///
/// Added because the lobby used to show only a count, which was enough when it
/// was a waiting screen and is not now: a host seating bots at three
/// difficulties needs to see what they have built, and a player joining a
/// stranger's room deserves to know that four of the five seats are machines
/// before they ready up.
class _Roster extends StatelessWidget {
  const _Roster({required this.room});

  final PlatformRoom room;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('At the table', style: text.titleSmall?.copyWith(color: colors.text)),
          const SizedBox(height: AppSpacing.sm),
          for (final PlatformSeat seat in room.seats)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  PlayerAvatar(
                    avatarId: seat.avatarId,
                    colorIndex: seat.avatarColorIndex,
                    size: 30,
                    dimmed: !seat.connected,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      seat.username,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: colors.text),
                    ),
                  ),
                  if (seat.isBot)
                    _DifficultyTag(difficulty: seat.botDifficulty)
                  else if (seat.isReady)
                    Icon(Icons.check_circle_rounded, color: colors.success, size: 18)
                  else
                    Text('not ready', style: text.labelSmall?.copyWith(color: colors.textMuted)),
                ],
              ),
            ),
          if (room.freeSeats > 0)
            Text(
              '${room.freeSeats} seat${room.freeSeats == 1 ? '' : 's'} still open',
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// The BOT badge, in the lobby's own palette rather than a game skin's.
class _DifficultyTag extends StatelessWidget {
  const _DifficultyTag({required this.difficulty});

  final BotDifficulty? difficulty;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryWash,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      ),
      child: Text(
        difficulty == null ? 'BOT' : 'BOT · ${difficulty!.label.toUpperCase()}',
        style: TextStyle(
          color: colors.primary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// The game's header block: its glyph, name and one-line pitch.
class _GameBanner extends StatelessWidget {
  const _GameBanner({required this.game});

  final GameDefinition game;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    // The banner is the one full-bleed colour field on the screen, so its
    // foreground is computed from the fill rather than assumed to be white:
    // a game tint can arrive from the server, and a pale one would erase the
    // title it is printed under.
    final Color ink = palette.onFill(game.color);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: game.color,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(GameGlyph.iconFor(game.gameId), color: ink, size: 26),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(game.displayName, style: text.headlineMedium?.copyWith(color: ink)),
                const SizedBox(height: 3),
                Text(
                  game.description,
                  style: text.bodyMedium?.copyWith(color: ink.withValues(alpha: 0.86)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// PLAY WITH STUPID, in a platform game's room.
///
/// The twin of the Scribble lobby's card, and deliberately the same shape: a
/// host filling empty seats should not have to learn two controls because two
/// games happen to run on different engines.
class _StupidsCard extends StatelessWidget {
  const _StupidsCard({
    required this.room,
    required this.botLabel,
    required this.busy,
    required this.difficulty,
    required this.onDifficulty,
    required this.onAdd,
    required this.onClear,
  });

  final PlatformRoom room;
  final String botLabel;
  final bool busy;

  /// How hard the *next* batch will play. Seats already filled keep the
  /// difficulty they were seated at, which is what lets a host build a table
  /// of two easy bots and one hard one.
  final BotDifficulty difficulty;

  final ValueChanged<BotDifficulty> onDifficulty;
  final ValueChanged<int> onAdd;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final bool full = room.freeSeats == 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const BrandMark(size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'PLAY WITH ${botLabel.toUpperCase()}',
                      style: text.titleSmall?.copyWith(color: colors.text),
                    ),
                    Text(
                      room.botCount == 0
                          ? 'Short of players? Add some idiots.'
                          : '${room.botCount} in the room already.',
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Difficulty first, because it applies to whatever is seated next
          // and a host who picked "+2" and then noticed the dial would have
          // to clear the room to change it.
          Text(
            'How hard should they play?',
            style: text.bodySmall?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              for (final BotDifficulty level in BotDifficulty.values)
                ChoiceChip(
                  label: Text(level.label),
                  selected: difficulty == level,
                  onSelected: busy ? null : (_) => onDifficulty(level),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final int count in <int>[1, 2, 3])
                AppButton(
                  label: '+$count',
                  variant: AppButtonVariant.primary,
                  onPressed: busy || full ? null : () => onAdd(count),
                ),
              if (room.botCount > 0)
                AppButton(
                  label: 'Clear',
                  icon: Icons.person_remove_outlined,
                  onPressed: busy ? null : onClear,
                ),
            ],
          ),
          if (full) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text('The room is full.', style: text.bodySmall?.copyWith(color: colors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Explains where PLAY WITH STUPID actually leads.
class _StupidsHint extends StatelessWidget {
  const _StupidsHint({required this.botLabel});

  final String botLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.info_outline, size: 16, color: colors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Open a room, then add $botLabel from the lobby.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// The room this screen opened, and the way to signal ready.
class _RoomStatus extends StatelessWidget {
  const _RoomStatus({required this.room, required this.onReady, required this.busy});

  final PlatformRoom room;
  final VoidCallback onReady;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Room ${room.roomCode}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${room.playerCount} / ${room.maxPlayers} players · share this code',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Ready',
            icon: Icons.check_rounded,
            variant: AppButtonVariant.primary,
            expand: true,
            busy: busy,
            onPressed: busy ? null : onReady,
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 17), label: Text(label));
}
