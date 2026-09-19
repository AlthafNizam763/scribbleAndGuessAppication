import 'package:flutter/material.dart';
import 'package:scribble_guess/models/app_notification.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';

/// How each kind of notification is drawn and where it goes on tap.
///
/// ## Why this is a table and not a switch in the card
///
/// Three places need the same answer — the list row, the in-app banner, and
/// eventually a push payload — and a switch copied into each is how the banner
/// ends up with an icon the list disagrees with. It is also the seam an
/// unknown kind falls through: one branch here, rather than one per widget.
///
/// The colours are the doodle accents, used sparingly and only as an icon
/// tint. The card itself stays paper with an ink border, like every other card
/// in the app.
@immutable
class NotificationLook {
  /// Creates a look.
  const NotificationLook({
    required this.icon,
    required this.tint,
    this.route,
  });

  /// The doodle-style glyph on the left of the row.
  final IconData icon;

  /// Which accent tints it, read off the active [AppPalette].
  final Color Function(AppPalette colors) tint;

  /// The route name to open on tap, or null when there is nowhere to go.
  final String? route;

}

/// The look for [kind].
///
/// An unrecognised kind gets a neutral bell and no destination, which is what
/// lets the server send a notification type this build has never heard of
/// without the row becoming a dead tap that looks alive.
NotificationLook lookFor(NotificationKind kind) {
  switch (kind) {
    case NotificationKind.friendRequest:
      return NotificationLook(
        icon: Icons.person_add_alt_1_outlined,
        tint: (AppPalette colors) => colors.accentBlue,
        route: AppRoutes.friendRequests,
      );

    case NotificationKind.friendRequestAccepted:
      return NotificationLook(
        icon: Icons.people_alt_outlined,
        tint: (AppPalette colors) => colors.accentGreen,
        route: AppRoutes.friends,
      );

    case NotificationKind.roomInvitation:
      return NotificationLook(
        icon: Icons.mail_outline,
        tint: (AppPalette colors) => colors.accentPurple,
        route: AppRoutes.roomInvitations,
      );

    case NotificationKind.friendStartedPlaying:
    case NotificationKind.friendJoinedRoom:
      return NotificationLook(
        icon: Icons.sports_esports_outlined,
        tint: (AppPalette colors) => colors.accentOrange,
        route: AppRoutes.publicRooms,
      );

    case NotificationKind.userJoinedRoom:
      return NotificationLook(
        icon: Icons.login_outlined,
        tint: (AppPalette colors) => colors.accentTeal,
      );

    case NotificationKind.gameResult:
      return NotificationLook(
        icon: Icons.emoji_events_outlined,
        tint: (AppPalette colors) => colors.accentYellow,
      );

    case NotificationKind.achievementUnlocked:
      return NotificationLook(
        icon: Icons.workspace_premium_outlined,
        tint: (AppPalette colors) => colors.accentYellow,
      );

    case NotificationKind.dailyChallengeCompleted:
      return NotificationLook(
        icon: Icons.task_alt_outlined,
        tint: (AppPalette colors) => colors.accentGreen,
      );

    case NotificationKind.tournamentAnnouncement:
      return NotificationLook(
        icon: Icons.flag_outlined,
        tint: (AppPalette colors) => colors.accentRed,
        route: AppRoutes.tournaments,
      );

    case NotificationKind.tournamentCheckInOpen:
      // The listing rather than the specific tournament, because this table
      // maps a *kind* to a destination and has no row to read an id from. The
      // push path, which does have the id, pushes the detail screen on top —
      // see `app/push_navigation.dart`.
      return NotificationLook(
        icon: Icons.how_to_reg_outlined,
        tint: (AppPalette colors) => colors.accentGreen,
        route: AppRoutes.tournaments,
      );

    case NotificationKind.systemAnnouncement:
      return NotificationLook(
        icon: Icons.campaign_outlined,
        tint: (AppPalette colors) => colors.accentPink,
      );

    case NotificationKind.unknown:
      return NotificationLook(
        icon: Icons.notifications_none_outlined,
        tint: (AppPalette colors) => colors.textMuted,
      );
  }
}
