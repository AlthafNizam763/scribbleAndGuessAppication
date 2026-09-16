import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final SketchColors colors = context.sketch;
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
      return SketchScaffold(
        title: context.l10n.lobbyTitle,
        showBack: false,
        banner: const ConnectionBanner(),
        child: const Center(child: CircularProgressIndicator()),
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
      child: SketchScaffold(
        title: context.l10n.lobbyTitle,
        showBack: false,
        banner: const ConnectionBanner(),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: context.l10n.leave,
          onPressed: _leave,
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
                        style: text.bodySmall?.copyWith(color: colors.inkSoft),
                      ),
                    ),
                  SketchButton.primary(
                    label: context.l10n.lobbyStart,
                    icon: Icons.play_arrow,
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
                      style: text.bodySmall?.copyWith(color: colors.inkSoft),
                    ),
                  ),
                  SketchButton(
                    label: isReady
                        ? context.l10n.lobbyNotReady
                        : context.l10n.lobbyReady,
                    icon: isReady ? Icons.close : Icons.check,
                    expand: true,
                    variant: isReady
                        ? SketchButtonVariant.secondary
                        : SketchButtonVariant.primary,
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
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return SketchCard(
      child: Column(
        children: <Widget>[
          Text(
            context.l10n.lobbyRoomCode.toUpperCase(),
            style: text.labelSmall?.copyWith(color: colors.inkSoft),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            code,
            style: text.displaySmall?.copyWith(
              color: colors.ink,
              letterSpacing: 10,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: SketchButton(
                  label: context.l10n.lobbyCopyCode,
                  icon: Icons.copy,
                  variant: SketchButtonVariant.ghost,
                  onPressed: onCopy,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: SketchButton(
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
    final SketchColors colors = context.sketch;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.center,
      children: <Widget>[
        SketchBadge(
          label: '${room.settings.rounds} rounds',
          icon: Icons.repeat,
          color: colors.accentBlue,
        ),
        SketchBadge(
          label: '${room.settings.drawTimeSeconds}s',
          icon: Icons.timer_outlined,
          color: colors.accentOrange,
        ),
        SketchBadge(
          label: '${room.settings.hintCount} hints',
          icon: Icons.lightbulb_outline,
          color: colors.accentYellow,
        ),
        SketchBadge(
          label: room.settings.wordMode.label,
          icon: Icons.spellcheck,
          color: colors.accentGreen,
        ),
        if (room.settings.isPrivate)
          SketchBadge(
            label: 'Private',
            icon: Icons.lock_outline,
            color: colors.inkSoft,
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
