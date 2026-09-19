import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/app/router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_invite.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The card an invitation is answered from, in a dialog or in a list.
///
/// ## Why one widget serves both
///
/// An invitation reaches a player two ways — pushed while they are looking at
/// something else, or waiting in the inbox when they open it — and it must
/// look and behave the same in both. Two implementations would be two places
/// for the accept flow to drift, and the flow is the part with the
/// consequences: it seats an account, opens a socket and navigates.
///
/// ## Every refusal comes from the server
///
/// The buttons are always live. A room that had space when this card was drawn
/// may be full by the time somebody taps Accept, and the only honest way to
/// find out is to ask — so the card shows what it knew, the server decides,
/// and its message is what the player reads: `Room is full`, `Game already
/// started`, `Invitation expired`.
class RoomInvitationCard extends ConsumerStatefulWidget {
  /// Creates a card for [invitation].
  const RoomInvitationCard({
    required this.invitation,
    this.onAnswered,
    this.showDismiss = false,
    super.key,
  });

  /// The invitation being answered.
  final RoomInvitation invitation;

  /// Called after the server accepted an answer, so a dialog can close itself.
  final VoidCallback? onAnswered;

  /// Whether to offer "Later", which leaves the invitation in the inbox.
  final bool showDismiss;

  @override
  ConsumerState<RoomInvitationCard> createState() => _RoomInvitationCardState();
}

class _RoomInvitationCardState extends ConsumerState<RoomInvitationCard> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);

    // Captured before the await, because [onAnswered] closes the dialog this
    // card lives in and a popped route's context can no longer find either.
    final GoRouter router = GoRouter.of(context);

    final Result<Room> result =
        await ref.read(roomInviteActionsProvider).accept(widget.invitation);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<Room>():
        widget.onAnswered?.call();
        // `go` rather than `push`: the lobby replaces whatever the player was
        // looking at, so backing out of the room does not land them on a
        // screen stacked under a live game.
        router.goNamed(AppRoutes.lobby);
      case Err<Room>(:final Failure failure):
        // Before the dialog closes, while there is still a messenger to show
        // it on. The server's own sentence: `Room is full`, `Game already
        // started`, `Invitation expired`.
        notify(context, failure.message, isError: true);

        // A connection that never came up spent nothing: the accept is one
        // server call made *over* the socket, so failing to open one leaves
        // the invitation exactly as it was. The card stays, and its own button
        // is the retry — which is the whole point of doing it in that order.
        //
        // Every other refusal is the server's verdict on the invitation
        // itself, and it will give the same verdict to the same tap, so the
        // card goes rather than sitting there offering a button that cannot
        // work.
        if (!failure.code.isRetryable) widget.onAnswered?.call();
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);

    final Result<void> result =
        await ref.read(roomInviteActionsProvider).reject(widget.invitation);

    if (!mounted) return;
    setState(() => _busy = false);

    // Both before [onAnswered], which may close the dialog out from under
    // the messenger this is shown on.
    switch (result) {
      case Ok<void>():
        notify(context, context.l10n.invitationRejected);
      case Err<void>(:final Failure failure):
        notify(context, failure.message, isError: true);
    }

    widget.onAnswered?.call();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final RoomInvitation invitation = widget.invitation;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              PlayerAvatar(
                avatarId: invitation.inviter.avatarId,
                colorIndex: invitation.inviter.avatarColorIndex,
                size: 44,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      invitation.inviter.name.isEmpty
                          ? '...'
                          : invitation.inviter.name,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(color: colors.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.invitationTitle.toLowerCase(),
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _Fact(
                  label: context.l10n.invitationRoom,
                  value: invitation.roomCode,
                ),
              ),
              Expanded(
                child: _Fact(
                  label: context.l10n.invitationPlayers,
                  value: invitation.occupancy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              HudBadge(
                label: invitation.isPublic
                    ? context.l10n.invitationPublic
                    : context.l10n.invitationPrivate,
                icon: invitation.isPublic
                    ? Icons.public
                    : Icons.lock_outline,
                color: invitation.isPublic
                    ? colors.accentGreen
                    : colors.textMuted,
              ),
              HudBadge(
                label: invitation.roomStatus.label,
                icon: Icons.meeting_room_outlined,
                color: colors.accentBlue,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: context.l10n.invitationReject,
                  icon: Icons.close,
                  expand: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : _reject,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: context.l10n.invitationAccept,
                  icon: Icons.check,
                  expand: true,
                  variant: AppButtonVariant.primary,
                  busy: _busy,
                  onPressed: _busy ? null : _accept,
                ),
              ),
            ],
          ),
          if (widget.showDismiss) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: context.l10n.invitationLater,
              expand: true,
              variant: AppButtonVariant.ghost,
              // Deliberately answers nothing. The invitation stays pending and
              // stays in the inbox, which is the right outcome for somebody
              // who was in the middle of something.
              onPressed: _busy ? null : () => widget.onAnswered?.call(),
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled fact on an invitation card.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: text.labelSmall?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: text.titleSmall?.copyWith(color: colors.text),
        ),
      ],
    );
  }
}

/// The pop-up that appears when an invitation arrives while the app is open.
///
/// Shown by [RoomInvitationListener], never constructed directly: one listener
/// high in the tree is what stops two screens both deciding to interrupt for
/// the same invitation.
class RoomInvitationDialog extends StatelessWidget {
  /// Creates the dialog for [invitation].
  const RoomInvitationDialog({required this.invitation, super.key});

  /// The invitation that just arrived.
  final RoomInvitation invitation;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: RoomInvitationCard(
          invitation: invitation,
          showDismiss: true,
          onAnswered: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}

/// Puts an invitation on screen the moment it arrives, wherever the player is.
///
/// ## Why this is one widget near the root
///
/// The push is addressed to a person, not to a screen, so it can land while
/// the player is on the menu, a leaderboard or their own lobby. Letting each
/// screen listen would mean either missing it on the screens that forgot, or
/// two dialogs for one invitation on the screens that did not.
///
/// ## Where it deliberately stays quiet
///
/// Not during a game. Interrupting somebody mid-turn with a modal over the
/// canvas would cost them the round, and the invitation is not lost — it is in
/// the inbox, with its own badge on the menu, for as long as it is good.
class RoomInvitationListener extends ConsumerStatefulWidget {
  /// Wraps [child] with the listener.
  const RoomInvitationListener({required this.child, super.key});

  /// The app below it.
  final Widget child;

  @override
  ConsumerState<RoomInvitationListener> createState() =>
      _RoomInvitationListenerState();
}

class _RoomInvitationListenerState
    extends ConsumerState<RoomInvitationListener> {
  /// Whether a dialog is already up, so a second push does not stack another.
  bool _showing = false;

  /// Invitations already shown, so a reconnect that replays one does not
  /// interrupt twice for the same thing.
  final Set<String> _seen = <String>{};

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RoomInvitation>>(
      incomingInvitationProvider,
      (AsyncValue<RoomInvitation>? previous, AsyncValue<RoomInvitation> next) {
        final RoomInvitation? invitation = next.valueOrNull;
        if (invitation == null || !invitation.isOpen) return;
        if (_showing || !_seen.add(invitation.id)) return;

        // A push is also a reason to re-read the inbox, so the badge on the
        // menu is right whether or not the dialog below is shown.
        ref.read(roomInvitationsProvider.notifier).refresh();

        if (_isPlaying()) return;

        _show(invitation);
      },
    );

    return widget.child;
  }

  /// Whether a turn is under way, in which case nothing may interrupt.
  bool _isPlaying() {
    final Room? room = ref.read(roomProvider);
    return room != null && room.status.isPlaying;
  }

  Future<void> _show(RoomInvitation invitation) async {
    // This widget is mounted in `MaterialApp.builder`, which runs *above* the
    // Navigator, so its own context has nothing to push a route onto. The root
    // navigator key is the way back in — see `rootNavigatorKey`.
    final BuildContext? navigator = rootNavigatorKey.currentContext;
    if (navigator == null) return;

    _showing = true;
    try {
      await showDialog<void>(
        context: navigator,
        barrierDismissible: true,
        builder: (BuildContext dialogContext) =>
            RoomInvitationDialog(invitation: invitation),
      );
    } finally {
      _showing = false;
    }
  }
}
