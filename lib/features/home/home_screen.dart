import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/services/quick_play_service.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/social_widgets.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The main menu.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerProfile? profile = ref.watch(profileProvider);
    final int pending = ref.watch(pendingRequestCountProvider);
    // Reading this is also what keeps the invitations inbox alive while the
    // menu is open, so a pushed invitation updates the badge whether or not
    // the pop-up was shown.
    final int invitations = ref.watch(pendingInvitationCountProvider);
    // Same argument: reading this keeps the inbox alive while the menu is
    // open, so the badge tracks a push without the centre being on screen.
    final int unread = ref.watch(unreadNotificationCountProvider);

    return SketchScaffold(
      banner: const ConnectionBanner(),
      child: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          const SizedBox(height: AppSpacing.xl),
          BrandLogo(markSize: 72, caption: context.l10n.appTagline),
          const SizedBox(height: AppSpacing.xl),
          if (profile != null) _ProfileCard(profile: profile),
          const SizedBox(height: AppSpacing.xl),
          // The primary action. Above create and join because it is the one
          // that needs no decisions: a player who just wants to play taps this
          // and is in a room, rather than choosing between hosting and typing
          // somebody else's code.
          const QuickPlayButton(),
          const SizedBox(height: AppSpacing.lg),
          SketchButton(
            label: context.l10n.homeCreateRoom,
            icon: Icons.add_circle_outline,
            expand: true,
            onPressed: () => context.pushNamed(AppRoutes.createRoom),
          ),
          const SizedBox(height: AppSpacing.md),
          SketchButton(
            label: context.l10n.homeJoinRoom,
            icon: Icons.login,
            expand: true,
            onPressed: () => context.pushNamed(AppRoutes.joinRoom),
          ),
          const SizedBox(height: AppSpacing.md),
          // Below the two room buttons rather than beside them: practice is
          // what somebody reaches for when there is nobody to play with, so it
          // should be findable without competing with the real thing.
          SketchButton(
            label: context.l10n.practiceTitle,
            icon: Icons.brush_outlined,
            expand: true,
            onPressed: () => context.pushNamed(AppRoutes.practice),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: SketchButton(
                  label: context.l10n.publicRoomsTitle,
                  icon: Icons.meeting_room_outlined,
                  expand: true,
                  onPressed: () => context.pushNamed(AppRoutes.publicRooms),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                // The badge sits on the button rather than beside it, so an
                // unanswered invitation is visible from the menu without
                // opening anything — the same arrangement the friend requests
                // badge uses below.
                child: CountBadge(
                  count: invitations,
                  child: SketchButton(
                    label: context.l10n.invitationsTitle,
                    icon: Icons.mail_outline,
                    expand: true,
                    onPressed: () =>
                        context.pushNamed(AppRoutes.roomInvitations),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: SketchButton(
                  label: context.l10n.homeLeaderboard,
                  icon: Icons.emoji_events_outlined,
                  expand: true,
                  onPressed: () => context.pushNamed(AppRoutes.leaderboard),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                // The badge sits on the button rather than beside it, so an
                // unanswered request is visible from the menu without opening
                // anything.
                child: CountBadge(
                  count: pending,
                  child: SketchButton(
                    label: context.l10n.friendsTitle,
                    icon: Icons.group_outlined,
                    expand: true,
                    onPressed: () => context.pushNamed(AppRoutes.friends),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Full width, and on its own row, because it is not a peer of the
          // pairs above it: everything they lead to also arrives here. The
          // badge is the same one the invitation and request buttons carry,
          // and its number is the server's — see `unreadNotificationCountProvider`.
          CountBadge(
            count: unread,
            child: SketchButton(
              label: context.l10n.notificationsTitle,
              icon: Icons.notifications_none_outlined,
              expand: true,
              onPressed: () => context.pushNamed(AppRoutes.notifications),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Beside the leaderboard in spirit — both are "where do I stand" —
          // but on its own row because an event is a thing with a deadline,
          // and burying it next to a permanent board loses that.
          SketchButton(
            label: context.l10n.tournamentsTitle,
            icon: Icons.military_tech_outlined,
            expand: true,
            onPressed: () => context.pushNamed(AppRoutes.tournaments),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: SketchButton(
                  label: context.l10n.homeHowToPlay,
                  icon: Icons.help_outline,
                  expand: true,
                  onPressed: () => context.pushNamed(AppRoutes.howToPlay),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SketchButton(
                  label: context.l10n.homeSettings,
                  icon: Icons.settings_outlined,
                  expand: true,
                  onPressed: () => context.pushNamed(AppRoutes.settings),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// The Play button: finds a public room and goes there.
///
/// ## Why it is a widget and not a call site
///
/// It is on the home screen and could be on others, and everywhere it appears
/// it has to do the same four things: refuse a second tap, relabel itself
/// through the stages, navigate on success, and report a failure in a way the
/// player can retry. Putting that in one widget is what keeps a second Play
/// button from behaving differently.
///
/// ## Duplicate taps
///
/// Guarded three times over, and each guard covers a case the others cannot.
/// `_busy` here stops a second tap in the same frame. `QuickPlayService` holds
/// an in-flight flag that covers another widget starting one. The server keeps
/// a per-user gate that covers the player's other device.
class QuickPlayButton extends ConsumerStatefulWidget {
  /// Creates the Play button.
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
      // Every route already redirects to the profile screen without one, so
      // this only catches a race on a very first run. Nothing here waits on
      // the player finishing that screen; they come back and tap Play again.
      unawaited(context.pushNamed(AppRoutes.profile));
      return;
    }

    setState(() => _busy = true);

    final Result<Room> result =
        await ref.read(quickPlayServiceProvider).play(profile);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok<Room>():
        // `go` rather than `push`: the lobby replaces the menu, so backing out
        // of a room does not land on a home screen stacked under a live game.
        context.goNamed(AppRoutes.lobby);
      case Err<Room>(:final Failure failure):
        notify(context, failure.message, isError: true);
        ref.read(quickPlayServiceProvider).reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final QuickPlayStage stage = ref.watch(quickPlayProvider);
    final SketchColors colors = context.sketch;

    // The stage is shown as the label rather than as a separate line, so the
    // button is the only thing that moves while it works.
    final String label = switch (stage) {
      QuickPlayStage.connecting => context.l10n.quickPlayConnecting,
      QuickPlayStage.finding => context.l10n.quickPlayFinding,
      QuickPlayStage.joining => context.l10n.quickPlayJoining,
      QuickPlayStage.creating => context.l10n.quickPlayCreating,
      QuickPlayStage.failed => context.l10n.retry,
      QuickPlayStage.idle || QuickPlayStage.done => context.l10n.quickPlay,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          enabled: !_busy,
          label: context.l10n.quickPlay,
          hint: context.l10n.quickPlayHint,
          child: SketchButton.primary(
            label: label,
            icon: Icons.play_arrow_rounded,
            busy: _busy,
            onPressed: _busy ? null : _play,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          stage == QuickPlayStage.failed
              ? context.l10n.quickPlayFailed
              : context.l10n.quickPlayHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: stage == QuickPlayStage.failed
                    ? colors.danger
                    : colors.inkSoft,
              ),
        ),
      ],
    );
  }
}

/// Who you are playing as, with a shortcut to change it.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return SketchCard(
      onTap: () => context.pushNamed(AppRoutes.profile),
      child: Row(
        children: <Widget>[
          PlayerAvatar.ofProfile(profile, size: 48),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  context.l10n.homePlayingAs,
                  style: text.labelSmall?.copyWith(color: colors.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.name,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(color: colors.ink),
                ),
              ],
            ),
          ),
          Icon(Icons.edit_outlined, size: 20, color: colors.inkSoft),
        ],
      ),
    );
  }
}
