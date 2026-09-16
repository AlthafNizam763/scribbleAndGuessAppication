import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/rooms_api.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_invite.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The public room browser.
///
/// ## What is on the list, and who decided
///
/// The server: public, waiting, not full, not started, not closed, nothing the
/// player is banned from and nothing shared with anybody they have blocked.
/// There is no filter control on this screen, because there is nothing here
/// worth filtering that the server has not already decided — and a client-side
/// filter would be a second opinion about joinability that the Join button
/// would then contradict.
///
/// ## The list is a snapshot
///
/// Occupancy was read when the page was built, so a room can fill between the
/// draw and the tap. The Join button stays live anyway and the server refuses
/// with `Room is full`, which is both the truth and more useful than a button
/// greyed out from stale numbers. Pull to refresh re-reads.
class PublicRoomsScreen extends ConsumerWidget {
  /// Creates the browser.
  const PublicRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<PublicRoomPage> rooms = ref.watch(publicRoomsProvider);

    return SketchScaffold(
      title: context.l10n.publicRoomsTitle,
      padded: false,
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: context.l10n.retry,
          onPressed: () => ref.read(publicRoomsProvider.notifier).refresh(),
        ),
      ],
      child: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => SketchEmptyState(
          message: error is Failure ? error.message : context.l10n.errorUnknown,
          icon: Icons.cloud_off_outlined,
          action: SketchButton(
            label: context.l10n.retry,
            onPressed: () => ref.read(publicRoomsProvider.notifier).refresh(),
          ),
        ),
        data: (PublicRoomPage page) => RefreshIndicator(
          onRefresh: () => ref.read(publicRoomsProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              Text(
                context.l10n.publicRoomsSubtitle,
                style: text.bodySmall?.copyWith(color: colors.inkSoft),
              ),
              const SizedBox(height: AppSpacing.md),
              if (page.isSeatedElsewhere) ...<Widget>[
                _AlreadySeatedNotice(code: page.currentRoomCode),
                const SizedBox(height: AppSpacing.md),
              ],
              if (page.items.isEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.sizeOf(context).height * 0.12,
                  ),
                  child: SketchEmptyState(
                    message: context.l10n.publicRoomsEmpty,
                    icon: Icons.meeting_room_outlined,
                  ),
                )
              else
                for (final PublicRoom room in page.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: PublicRoomCard(room: room),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the player already holds a seat, with the way back to it.
///
/// The server refuses a second room outright, so this is not a warning about
/// something that might go wrong — it is the refusal, stated before the tap,
/// with the one action that resolves it.
class _AlreadySeatedNotice extends StatelessWidget {
  const _AlreadySeatedNotice({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return SketchCard(
      borderColor: colors.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.info_outline, size: 18, color: colors.inkSoft),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l10n.publicRoomsLeaveFirst,
                  style: text.bodySmall?.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SketchButton(
            label: '${context.l10n.publicRoomsBackToRoom} ($code)',
            icon: Icons.meeting_room_outlined,
            expand: true,
            onPressed: () => context.goNamed(AppRoutes.lobby),
          ),
        ],
      ),
    );
  }
}

/// One room in the browser, with its Join button.
class PublicRoomCard extends ConsumerStatefulWidget {
  /// Creates a card for [room].
  const PublicRoomCard({required this.room, super.key});

  /// The room, as the server described it.
  final PublicRoom room;

  @override
  ConsumerState<PublicRoomCard> createState() => _PublicRoomCardState();
}

class _PublicRoomCardState extends ConsumerState<PublicRoomCard> {
  bool _busy = false;

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);

    final Result<Room> result =
        await ref.read(roomInviteActionsProvider).joinPublic(widget.room);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<Room>():
        context.goNamed(AppRoutes.lobby);
      case Err<Room>(:final Failure failure):
        notify(context, failure.message, isError: true);
        // Whatever refused this has probably changed the rest of the list too
        // — a room that just filled is a room somebody else just joined.
        unawaited(ref.read(publicRoomsProvider.notifier).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final PublicRoom room = widget.room;

    return SketchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      room.name,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${context.l10n.publicRoomsHostedBy} ${room.hostName}',
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: colors.inkSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                room.code,
                style: text.titleSmall?.copyWith(
                  color: colors.inkSoft,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              SketchBadge(
                label: room.occupancy,
                icon: Icons.group_outlined,
                color: room.freeSeats <= 1
                    ? colors.accentOrange
                    : colors.accentGreen,
              ),
              SketchBadge(
                label: room.status.label,
                icon: Icons.schedule,
                color: colors.accentBlue,
              ),
              SketchBadge(
                label: '${room.rounds} rounds',
                icon: Icons.repeat,
                color: colors.inkSoft,
              ),
              SketchBadge(
                label: '${room.drawTimeSeconds}s',
                icon: Icons.timer_outlined,
                color: colors.inkSoft,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SketchButton(
            label: context.l10n.publicRoomsJoin,
            icon: Icons.login,
            expand: true,
            variant: SketchButtonVariant.primary,
            busy: _busy,
            onPressed: _busy ? null : _join,
          ),
        ],
      ),
    );
  }
}
