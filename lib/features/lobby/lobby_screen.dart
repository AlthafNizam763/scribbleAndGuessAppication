import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/config/app_brand_config.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/rules/room_state_machine.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/features/rooms/invite_friends_sheet.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/repositories/repositories.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The waiting room: who is here, the code to share, and the start button.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _busy = false;

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      notify(context, context.l10n.copied);
    }
  }

  /// Opens the invite sheet for this room.
  ///
  /// Offered to every seated player, not only the host. The server allows any
  /// member to invite — see the note on that in `invitation.service.ts` — and
  /// the reasoning holds here too: everybody in this lobby can already read
  /// the code aloud, so sending it as a notification grants nothing new.
  Future<void> _invite(Room room) async {
    await InviteFriendsSheet.open(
      context,
      roomId: room.id,
      roomCode: room.code,
    );
  }

  Future<void> _toggleReady(bool ready) async {
    setState(() => _busy = true);
    final Result<void> result =
        await ref.read(roomRepositoryProvider).setReady(ready);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    result.whenErr(
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  /// Seats [count] Stupids, and says how many actually arrived.
  ///
  /// The server clamps the ask to the seats left, so the message quotes the
  /// number it returned rather than the number requested — a host who asked
  /// for four into two free seats should not be told four turned up.
  Future<void> _addStupids(int count) async {
    setState(() => _busy = true);
    final Result<int> result =
        await ref.read(roomRepositoryProvider).addStupids(count);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    switch (result) {
      case Ok<int>(:final int value):
        notify(
          context,
          value == 1 ? '1 Stupid joined.' : '$value Stupids joined.',
        );
      case Err<int>(:final Failure failure):
        notify(context, failure.message, isError: true);
    }
  }

  Future<void> _clearStupids() async {
    setState(() => _busy = true);
    final Result<int> result =
        await ref.read(roomRepositoryProvider).clearStupids();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    result.whenErr(
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    final Result<void> result =
        await ref.read(gameRepositoryProvider).startGame();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    result.whenErr(
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  Future<void> _leave() async {
    final bool yes = await confirm(
      context,
      title: context.l10n.lobbyLeaveTitle,
      message: context.l10n.lobbyLeaveBody,
      confirmLabel: context.l10n.leave,
      destructive: true,
    );
    if (!yes || !mounted) {
      return;
    }
    await ref.read(roomControllerProvider).leaveRoom();
    if (mounted) {
      context.goNamed(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    final Room? room = ref.watch(roomProvider);
    final bool isHost = ref.watch(isHostProvider);
    final Player? self = ref.watch(selfPlayerProvider);
    final List<Player> players = ref.watch(playersProvider);

    // The server moves everyone into the game by advancing the phase; the
    // lobby's job is to notice and follow.
    ref.listen<GameState>(gameProvider, (GameState? previous, GameState next) {
      if (next.phase != GamePhase.lobby && next.phase != GamePhase.gameEnd) {
        context.goNamed(AppRoutes.game);
      }
    });

    if (room == null) {
      return AppScaffold(
        title: context.l10n.lobbyTitle,
        showBack: false,
        banner: const ConnectionBanner(),
        child: const AppLoadingState(),
      );
    }

    final bool canStart = RoomStateMachine.canStart(room);
    final bool isReady = self?.isReady ?? false;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _leave();
        }
      },
      child: AppScaffold(
        title: context.l10n.lobbyTitle,
        showBack: false,
        banner: const ConnectionBanner(),
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.lg),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppIconButton(
              icon: Icons.close_rounded,
              tooltip: context.l10n.leave,
              onPressed: _leave,
            ),
          ),
        ),
        bottom: isHost
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (!canStart)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        context.l10n.lobbyNeedMorePlayers,
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(color: colors.textMuted),
                      ),
                    ),
                  AppButton.primary(
                    label: context.l10n.lobbyStart,
                    icon: Icons.play_arrow_rounded,
                    busy: _busy,
                    onPressed: canStart ? _start : null,
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      context.l10n.lobbyWaitingForHost,
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ),
                  AppButton(
                    label: isReady
                        ? context.l10n.lobbyNotReady
                        : context.l10n.lobbyReady,
                    icon: isReady ? Icons.close : Icons.check,
                    expand: true,
                    variant: isReady
                        ? AppButtonVariant.secondary
                        : AppButtonVariant.primary,
                    busy: _busy,
                    onPressed: () => _toggleReady(!isReady),
                  ),
                ],
              ),
        child: ListView(
          padding: pagePadding(context),
          children: <Widget>[
            _RoomCodeCard(
              code: room.code,
              onCopy: () => _copyCode(room.code),
              onInvite: () => _invite(room),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (isHost) ...<Widget>[
              _StupidsCard(
                room: room,
                seated: players.where((Player player) => player.isBot).length,
                busy: _busy,
                onAdd: _addStupids,
                onClear: _clearStupids,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            _RulesSummary(room: room),
            const SizedBox(height: AppSpacing.xl),
            // The pushed room snapshot is the list: `s:room:state` arrives on
            // every membership change, so an invited friend accepting appears
            // here without this screen asking for anything.
            RoomMembersList(
              players: players,
              maxPlayers: room.settings.maxPlayers,
              selfId: self?.id,
              title: context.l10n.lobbyPlayers,
              trailingOf: (Player player) => isHost && player.id != self?.id
                  ? _HostMenu(player: player)
                  : null,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// PLAY WITH STUPID, in the lobby: fill the empty seats with bots.
///
/// Host only, because seating a Stupid changes the room for everybody in it.
/// Offered here rather than only at room creation because the moment a host
/// actually wants it is *after* waiting two minutes for a fourth player who
/// never came — which is a moment that happens in the lobby, not before it.
class _StupidsCard extends StatelessWidget {
  const _StupidsCard({
    required this.room,
    required this.seated,
    required this.busy,
    required this.onAdd,
    required this.onClear,
  });

  final Room room;

  /// How many Stupids are already in the room.
  final int seated;

  final bool busy;
  final ValueChanged<int> onAdd;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final bool full = room.players.length >= room.settings.maxPlayers;

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
                      'PLAY WITH ${AppBrandConfig.current.botLabel.toUpperCase()}',
                      style: text.titleSmall?.copyWith(color: colors.text),
                    ),
                    Text(
                      seated == 0
                          ? 'Short of players? Add some idiots.'
                          : '$seated in the room already.',
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
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
              if (seated > 0)
                AppButton(
                  label: 'Clear',
                  icon: Icons.person_remove_outlined,
                  onPressed: busy ? null : onClear,
                ),
            ],
          ),
          if (full) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The room is full.',
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The share code, big enough to read aloud across a room.
class _RoomCodeCard extends StatelessWidget {
  const _RoomCodeCard({
    required this.code,
    required this.onCopy,
    required this.onInvite,
  });

  final String code;
  final VoidCallback onCopy;

  /// Opens the invite sheet.
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        children: <Widget>[
          Text(
            context.l10n.lobbyRoomCode.toUpperCase(),
            style: text.labelSmall?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            code,
            style: text.displaySmall?.copyWith(
              color: colors.text,
              letterSpacing: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: AppButton(
                  label: context.l10n.lobbyCopyCode,
                  icon: Icons.copy,
                  variant: AppButtonVariant.ghost,
                  onPressed: onCopy,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: AppButton(
                  label: context.l10n.lobbyInvite,
                  icon: Icons.person_add_alt_1_outlined,
                  onPressed: onInvite,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A one-line recap of the rules the host chose.
class _RulesSummary extends StatelessWidget {
  const _RulesSummary({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.center,
      children: <Widget>[
        HudBadge(
          label: '${room.settings.rounds} rounds',
          icon: Icons.repeat,
          color: colors.accentBlue,
        ),
        HudBadge(
          label: '${room.settings.drawTimeSeconds}s',
          icon: Icons.timer_outlined,
          color: colors.accentOrange,
        ),
        HudBadge(
          label: '${room.settings.hintCount} hints',
          icon: Icons.lightbulb_outline,
          color: colors.accentYellow,
        ),
        HudBadge(
          label: room.settings.wordMode.label,
          icon: Icons.spellcheck,
          color: colors.accentGreen,
        ),
        if (room.settings.isPrivate)
          HudBadge(
            label: 'Private',
            icon: Icons.lock_outline,
            color: colors.textMuted,
          ),
      ],
    );
  }
}

/// Host-only moderation for one player.
class _HostMenu extends ConsumerWidget {
  const _HostMenu({required this.player});

  final Player player;

  Future<void> _run(
    BuildContext context,
    Future<Result<void>> Function() action,
  ) async {
    final Result<void> result = await action();
    if (!context.mounted) {
      return;
    }
    result.whenErr(
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RoomRepository repository = ref.read(roomRepositoryProvider);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'mute',
          child: Text(
            player.isMuted
                ? context.l10n.moderationUnmute
                : context.l10n.moderationMute,
          ),
        ),
        PopupMenuItem<String>(
          value: 'host',
          child: Text(context.l10n.moderationTransferHost),
        ),
        PopupMenuItem<String>(
          value: 'kick',
          child: Text(context.l10n.moderationKick),
        ),
        PopupMenuItem<String>(
          value: 'ban',
          child: Text(context.l10n.moderationBan),
        ),
      ],
      onSelected: (String choice) async {
        switch (choice) {
          case 'mute':
            await _run(
              context,
              () => repository.mutePlayer(player.id, !player.isMuted),
            );
          case 'host':
            if (await confirm(
              context,
              title: context.l10n.moderationTransferTitle,
              message: context.l10n.moderationTransferBody,
            )) {
              if (context.mounted) {
                await _run(
                  context,
                  () => repository.transferHost(player.id),
                );
              }
            }
          case 'kick':
            if (await confirm(
              context,
              title: context.l10n.moderationKickTitle,
              message: context.l10n.moderationKickBody,
              confirmLabel: context.l10n.moderationKick,
              destructive: true,
            )) {
              if (context.mounted) {
                await _run(
                  context,
                  () => repository.kickPlayer(player.id),
                );
              }
            }
          case 'ban':
            if (await confirm(
              context,
              title: context.l10n.moderationBanTitle,
              message: context.l10n.moderationBanBody,
              confirmLabel: context.l10n.moderationBan,
              destructive: true,
            )) {
              if (context.mounted) {
                await _run(
                  context,
                  () => repository.banPlayer(player.id),
                );
              }
            }
        }
      },
    );
  }
}
