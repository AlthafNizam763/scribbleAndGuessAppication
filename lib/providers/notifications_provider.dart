import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/socket_events.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/notifications_api.dart';
import 'package:scribble_guess/models/app_notification.dart';
import 'package:scribble_guess/models/json_utils.dart';
import 'package:scribble_guess/providers/auth_provider.dart';
import 'package:scribble_guess/providers/core_providers.dart';

/// The notification centre.
///
/// ## Where the truth is
///
/// The server, exactly as in [roomInvitationsProvider]. The list is a cache of
/// a REST read, and every action is a call whose response decides what
/// happened. In particular the *unread count is never computed here*: each
/// mutation returns the server's new figure and the badge renders that. A
/// client that decremented its own counter would drift the first time it
/// missed a push — which happens on every backgrounded app — and the drift
/// would never correct itself.
///
/// ## Realtime is a hint, with one deliberate exception
///
/// `s:notification:unread` means "your count is stale" and the badge re-reads.
/// `s:notification:new` carries the row, and [latestNotificationProvider]
/// parses it so a toast can be drawn the instant it lands — the same exception
/// [incomingInvitationProvider] makes, for the same reason: a banner that
/// waited for a REST round trip would appear a beat late or, on a poor
/// connection, not at all.
///
/// The list itself still re-reads over REST, and that read wins wherever the
/// two disagree.

/// The notification endpoints.
final Provider<NotificationsApi> notificationsApiProvider =
    Provider<NotificationsApi>(
  (Ref ref) => NotificationsApi(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------------------
// Realtime
// ---------------------------------------------------------------------------

/// Both notification pushes, as a stream of the count each one carried.
///
/// The count rides on the payload, so the common case — the badge — is served
/// without a request. A push whose payload has no count yields null, and the
/// badge falls back to re-reading rather than guessing.
final StreamProvider<int?> notificationCountEventsProvider =
    StreamProvider<int?>(
  (Ref ref) => ref
      .watch(gatewayProvider)
      .inbound
      .where(
        (({String event, Map<String, dynamic> data}) message) =>
            SocketEvents.notificationEvents.contains(message.event),
      )
      .map((({String event, Map<String, dynamic> data}) message) {
    AppLogger.d('Notifications: ${message.event}');
    final dynamic raw = message.data['unreadCount'];
    return raw == null ? null : asInt(raw);
  }),
);

/// Notifications as they arrive, parsed, for an in-app banner.
///
/// Only [SocketEvents.serverNotificationNew] carries a row; the unread push
/// deliberately does not, because it is emitted by this player's *own* reads
/// on another device and interrupting them with it would be noise.
///
/// Malformed payloads are dropped rather than surfaced.
final StreamProvider<AppNotification> latestNotificationProvider =
    StreamProvider<AppNotification>(
  (Ref ref) => ref
      .watch(gatewayProvider)
      .inbound
      .where(
        (({String event, Map<String, dynamic> data}) message) =>
            message.event == SocketEvents.serverNotificationNew,
      )
      .map(
        (({String event, Map<String, dynamic> data}) message) =>
            AppNotification.fromJson(asMap(message.data['notification'])),
      )
      .where((AppNotification row) => !row.isEmpty),
);

// ---------------------------------------------------------------------------
// The inbox
// ---------------------------------------------------------------------------

/// The local player's notifications.
///
/// Not autodisposing: the badge reads the count off this provider from the
/// home screen, and a list that was thrown away every time the player
/// navigated would mean the badge flickering back to zero on every return.
class NotificationsNotifier extends AsyncNotifier<NotificationPage> {
  NotificationsApi get _api => ref.read(notificationsApiProvider);

  /// Whether the list is narrowed to unread rows.
  bool _unreadOnly = false;

  /// Whether the filter chip is on.
  bool get unreadOnly => _unreadOnly;

  @override
  Future<NotificationPage> build() async {
    // `listen` rather than `watch`: a push should refresh the list, not
    // rebuild this provider and re-enter `build` from the top.
    ref.listen<AsyncValue<int?>>(
      notificationCountEventsProvider,
      (AsyncValue<int?>? previous, AsyncValue<int?> next) {
        if (next.hasValue) unawaited(refresh());
      },
    );

    return _load(page: 1);
  }

  Future<NotificationPage> _load({required int page}) async {
    final Result<NotificationPage> result = await _api.list(
      page: page,
      unreadOnly: _unreadOnly,
    );

    return switch (result) {
      Ok<NotificationPage>(:final NotificationPage value) => value,
      // Thrown rather than returned so the screen's error branch renders,
      // which is where the retry button lives. The server's own message is
      // carried through, so the player reads the sentence it wrote.
      Err<NotificationPage>(:final Failure failure) => throw failure,
    };
  }

  /// Re-reads the first page. Used by pull-to-refresh and after every action.
  Future<void> refresh() async {
    try {
      state = AsyncValue<NotificationPage>.data(await _load(page: 1));
    } on Failure catch (failure, stack) {
      state = AsyncValue<NotificationPage>.error(failure, stack);
    }
  }

  /// Switches between the whole history and the unread backlog.
  Future<void> setUnreadOnly({required bool value}) async {
    if (_unreadOnly == value) return;
    _unreadOnly = value;

    state = const AsyncValue<NotificationPage>.loading();
    await refresh();
  }

  /// Appends the next page, keeping what is already on screen.
  ///
  /// A failure here leaves the current rows in place rather than replacing the
  /// list with an error: the player can still read and act on what loaded, and
  /// scrolling again retries.
  Future<void> loadMore() async {
    final NotificationPage? current = state.valueOrNull;
    if (current == null || !current.hasMore) return;

    final Result<NotificationPage> result = await _api.list(
      page: current.page + 1,
      unreadOnly: _unreadOnly,
    );

    if (result case Ok<NotificationPage>(:final NotificationPage value)) {
      state = AsyncValue<NotificationPage>.data(
        value.copyWith(
          items: <AppNotification>[...current.items, ...value.items],
        ),
      );
    }
  }

  /// Marks one row read.
  ///
  /// The row settles locally first — it has been tapped, and the server is
  /// about to agree — but the *count* comes back from the server and is not
  /// derived here. That asymmetry is the point: a wrong row is visible and
  /// self-correcting on the next read, a wrong badge is neither.
  Future<Result<int>> markRead(String notificationId) async {
    final NotificationPage? current = state.valueOrNull;

    if (current != null) {
      final int now = DateTime.now().millisecondsSinceEpoch;

      state = AsyncValue<NotificationPage>.data(
        current.copyWith(
          items: <AppNotification>[
            for (final AppNotification row in current.items)
              row.id == notificationId && !row.isRead ? row.asRead(now) : row,
          ],
        ),
      );
    }

    final Result<int> outcome = await _api.markRead(notificationId);

    _applyCount(outcome);
    return outcome;
  }

  /// Clears the whole backlog.
  Future<Result<int>> markAllRead() async {
    final Result<int> outcome = await _api.markAllRead();

    if (outcome.isOk) unawaited(refresh());
    return outcome;
  }

  /// Deletes one row.
  ///
  /// Removed locally as soon as the server confirms, so the card does not sit
  /// there looking tappable for the length of the refresh that follows.
  Future<Result<int>> remove(String notificationId) async {
    final Result<int> outcome = await _api.remove(notificationId);

    if (outcome.isOk) {
      final NotificationPage? current = state.valueOrNull;

      if (current != null) {
        state = AsyncValue<NotificationPage>.data(
          current.copyWith(
            items: current.items
                .where((AppNotification row) => row.id != notificationId)
                .toList(growable: false),
            total: current.total > 0 ? current.total - 1 : 0,
          ),
        );
      }

      _applyCount(outcome);
    }

    return outcome;
  }

  /// Writes the server's unread count onto the current page.
  void _applyCount(Result<int> outcome) {
    if (outcome case Ok<int>(value: final int unreadCount)) {
      final NotificationPage? current = state.valueOrNull;
      if (current == null) return;

      state = AsyncValue<NotificationPage>.data(
        current.copyWith(unreadCount: unreadCount),
      );
    }
  }
}

/// The notification inbox, as the screens read it.
final AsyncNotifierProvider<NotificationsNotifier, NotificationPage>
    notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, NotificationPage>(
  NotificationsNotifier.new,
);

/// How many notifications are unread, for the badge on the home screen.
///
/// Zero while the list is loading or failed, which is the right default: a
/// badge that guesses is worse than no badge. The figure is always the
/// server's — see the note on [NotificationsNotifier.markRead] for why this
/// app never does the arithmetic itself.
final Provider<int> unreadNotificationCountProvider = Provider<int>(
  (Ref ref) => ref.watch(notificationsProvider).valueOrNull?.unreadCount ?? 0,
);
