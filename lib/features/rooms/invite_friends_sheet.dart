import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/room_invite.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/social_widgets.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The lobby's "Invite friends" sheet.
///
/// ## Why the button state comes from the server
///
/// Every row is drawn from an [InviteCandidate], and every flag on one —
/// seated, already asked, invitable, and the reason when not — was decided by
/// the server against the room's live state. The sheet renders what it is
/// given and offers nothing the server would refuse, which is what stops a
/// player tapping Invite and being told "already in this room" a second later.
///
/// The reverse would be worse than it sounds: working the rules out here would
/// mean the sheet and the invite endpoint could disagree, and the sheet is the
/// one somebody is looking at.
///
/// ## Why a sheet and not a screen
///
/// Inviting is something you do from the lobby and then stop doing. A screen
/// would take the room off-screen — the player list, the code, the Start
/// button — while they pick somebody, which is exactly the context that makes
/// the choice easy.
class InviteFriendsSheet extends ConsumerWidget {
  /// Creates the sheet for [roomId].
  const InviteFriendsSheet({
    required this.roomId,
    required this.roomCode,
    super.key,
  });

  /// The room being invited into.
  final String roomId;

  /// Its code, shown so the host can read it aloud instead if they prefer.
  final String roomCode;

  /// Opens the sheet over the current screen.
  static Future<void> open(
    BuildContext context, {
    required String roomId,
    required String roomCode,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.sketch.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (BuildContext sheetContext) => InviteFriendsSheet(
        roomId: roomId,
        roomCode: roomCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    final AsyncValue<List<InviteCandidate>> candidates =
        ref.watch(inviteCandidatesProvider(roomId));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            context.l10n.inviteSheetTitle,
                            style: text.titleLarge?.copyWith(color: colors.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${context.l10n.inviteSheetSubtitle}  $roomCode',
                            style:
                                text.bodySmall?.copyWith(color: colors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: context.l10n.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(color: colors.inkFaint, height: 1),
              Flexible(
                child: candidates.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (Object error, StackTrace stack) => SketchEmptyState(
                    message: error is Failure
                        ? error.message
                        : context.l10n.errorUnknown,
                    icon: Icons.cloud_off_outlined,
                    action: SketchButton(
                      label: context.l10n.retry,
                      onPressed: () => ref
                          .read(inviteCandidatesProvider(roomId).notifier)
                          .refresh(),
                    ),
                  ),
                  data: (List<InviteCandidate> rows) {
                    if (rows.isEmpty) {
                      return SketchEmptyState(
                        message: context.l10n.inviteNoFriends,
                        icon: Icons.group_outlined,
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: rows.length,
                      itemBuilder: (BuildContext context, int index) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: FriendInviteTile(
                          candidate: rows[index],
                          roomId: roomId,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One friend in the invite sheet, with whatever action they are eligible for.
///
/// Four states, and only one of them is a button: invitable, already invited,
/// already in the room, and un-invitable for a reason the server gave. Drawing
/// the reason rather than a disabled button with no explanation is the
/// difference between "this is broken" and "the room is full".
class FriendInviteTile extends ConsumerStatefulWidget {
  /// Creates a row for [candidate].
  const FriendInviteTile({
    required this.candidate,
    required this.roomId,
    super.key,
  });

  /// The friend, annotated for this room by the server.
  final InviteCandidate candidate;

  /// The room the invitation would be for.
  final String roomId;

  @override
  ConsumerState<FriendInviteTile> createState() => _FriendInviteTileState();
}

class _FriendInviteTileState extends ConsumerState<FriendInviteTile> {
  bool _busy = false;

  Future<void> _invite() async {
    if (_busy) return;
    setState(() => _busy = true);

    final Result<RoomInvitation> result =
        await ref.read(roomInviteActionsProvider).invite(
              roomId: widget.roomId,
              friendId: widget.candidate.card.id,
            );

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<RoomInvitation>():
        notify(context, context.l10n.inviteSentToast);
      case Err<RoomInvitation>(:final Failure failure):
        // The server's own sentence, which already says exactly why: the room
        // filled, the game started, they are already in it.
        notify(context, failure.message, isError: true);
        // And the sheet is re-read, because whatever refused this invitation
        // has probably changed the other rows too.
        unawaited(
          ref.read(inviteCandidatesProvider(widget.roomId).notifier).refresh(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final InviteCandidate candidate = widget.candidate;

    return PlayerTile(
      card: candidate.card,
      subtitle: candidate.isOnline
          ? context.l10n.inviteOnline
          : context.l10n.inviteOffline,
      leading: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: _PresenceDot(online: candidate.isOnline),
      ),
      trailing: switch (candidate) {
        InviteCandidate(isMember: true) => SketchBadge(
            label: context.l10n.inviteJoined,
            icon: Icons.check,
            color: colors.success,
          ),
        InviteCandidate(isInvited: true) => SketchBadge(
            label: context.l10n.inviteSent,
            icon: Icons.schedule,
            color: colors.accentBlue,
          ),
        InviteCandidate(canInvite: true) => SketchButton(
            label: context.l10n.inviteAction,
            icon: Icons.send_outlined,
            busy: _busy,
            onPressed: _busy ? null : _invite,
          ),
        // Un-invitable for a reason the server named: the room is full, the
        // game started, they are banned from it.
        _ => SketchBadge(
            label: candidate.blockedReason.isEmpty
                ? context.l10n.inviteOffline
                : candidate.blockedReason,
            icon: Icons.block_outlined,
            color: colors.inkSoft,
          ),
      },
    );
  }
}

/// A small filled dot marking a friend as connected.
///
/// Ink and paper rather than a colour of its own: the sketchbook has no green
/// "online" light, and inventing one here would be the first pixel of a
/// different app.
class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Semantics(
      label: online ? context.l10n.inviteOnline : context.l10n.inviteOffline,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: online ? colors.success : Colors.transparent,
          border: Border.all(
            color: online ? colors.success : colors.inkFaint,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
