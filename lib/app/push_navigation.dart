import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/app/router.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/models/push_message.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';

/// Takes the player where a tapped notification pointed.
///
/// ## Why this sits above the router rather than on a screen
///
/// For the same reason `RoomInvitationListener` does: a notification is
/// addressed to the *player*, so it can be tapped from any screen or from no
/// screen at all. A listener mounted per screen would miss it wherever
/// somebody forgot to add one, and would navigate twice where they added two.
///
/// ## The two arrivals, and why they are handled separately
///
/// A tap on a notification while the app was merely backgrounded arrives on
/// the stream, with a navigator already mounted and ready. A tap that *launched*
/// the app from cold does not: `getInitialMessage` resolves during startup,
/// before this widget — before any widget — exists, so there is nothing
/// listening and the message would be dropped.
///
/// That dropped message is exactly the "I tapped the notification and it just
/// opened the home screen" complaint, so [FcmService] holds the first one in
/// `pendingTap` and this widget collects it on its first frame.
///
/// ## Why navigation is deliberately shallow
///
/// The most a notification does is open the tournament screen, pushing the
/// detail screen for the tournament it named. It does not check in, does not
/// enter a match, and does not assume the tournament is still in the state it
/// was when the message was written — which for a check-in with a two-minute
/// window it very often is not. The screen re-reads the tournament over REST
/// and shows whatever is true now, including "this tournament has finished".
class PushNavigationListener extends ConsumerStatefulWidget {
  /// Wraps [child].
  const PushNavigationListener({required this.child, super.key});

  /// The app below this listener.
  final Widget child;

  @override
  ConsumerState<PushNavigationListener> createState() =>
      _PushNavigationListenerState();
}

class _PushNavigationListenerState
    extends ConsumerState<PushNavigationListener> {
  @override
  void initState() {
    super.initState();

    // After the first frame, so there is a navigator to push onto. A cold
    // start resolves its message while the splash screen is still deciding
    // where the player belongs, and pushing before that lands would put the
    // tournament under a screen that is about to replace it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainPending());
  }

  /// Collects the message that launched the app, if one did.
  void _drainPending() {
    final PushMessage? pending = ref.read(fcmServiceProvider).pendingTap;
    if (pending == null) return;

    ref.read(fcmServiceProvider).pendingTap = null;
    _open(pending);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<PushMessage>>(pushTapProvider, (
      AsyncValue<PushMessage>? previous,
      AsyncValue<PushMessage> next,
    ) {
      final PushMessage? message = next.valueOrNull;
      if (message != null) _open(message);
    });

    return widget.child;
  }

  /// Routes one message.
  ///
  /// Never throws and never navigates on a payload it cannot use: an unknown
  /// kind, or a known kind with no id, leaves the player wherever they are.
  /// The app has already been opened by the tap, which is most of what they
  /// asked for.
  void _open(PushMessage message) {
    final BuildContext? navigator = rootNavigatorKey.currentContext;
    if (navigator == null || !navigator.mounted) {
      AppLogger.w('[FCM] no navigator to open $message');
      return;
    }

    switch (message.kind) {
      case PushKind.tournamentCheckInOpen:
        AppLogger.i('[FCM] opening tournament ${message.tournamentId}');

        // The listing first, so the back button from the detail screen lands
        // somewhere sensible rather than on whatever happened to be open when
        // the notification arrived.
        navigator.goNamed(AppRoutes.tournaments);

        if (message.hasTournament) {
          navigator.pushNamed(
            AppRoutes.tournamentDetail,
            pathParameters: <String, String>{
              'tournamentId': message.tournamentId,
            },
          );
        }

      case PushKind.roomInvitation:
        AppLogger.i('[FCM] opening invitations for ${message.invitationId}');

        // The inbox, not the room. Deliberately, and for the same reason the
        // tournament case opens a screen rather than checking in: the payload
        // was written when the invitation was sent and says nothing about
        // whether the room still has space, has started, or exists. The inbox
        // re-reads over REST and draws whatever is true now — including
        // nothing at all, when the invitation has since lapsed.
        //
        // `go` rather than `push`: a notification tap is the player choosing
        // where to be, and stacking the inbox on top of whatever was open
        // would leave them backing into a screen they had already left.
        navigator.goNamed(AppRoutes.roomInvitations);

        // The list re-reads itself, so the badge and the rows are right even
        // when this arrived while the app was alive and the socket was not.
        ref.read(roomInvitationsProvider.notifier).refresh();

      case PushKind.unknown:
        // A kind this build has never heard of. The server is free to start
        // sending a new one before every installed app can act on it, and the
        // notification's own text has already told the player what happened.
        AppLogger.i('[FCM] no destination for $message');
    }
  }
}
