import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/widgets/app_button.dart';
import 'package:scribble_guess/core/widgets/app_scaffold.dart';
import 'package:scribble_guess/features/notifications/notification_card.dart';
import 'package:scribble_guess/features/notifications/notification_icons.dart';
import 'package:scribble_guess/models/app_notification.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The notification centre.
///
/// ## Every state the list can be in
///
/// Loading, error with a retry, empty, and the list itself — the same four
/// branches the invitations inbox and the friends screen render, drawn the
/// same way, because a player who has learned one of these screens has learned
/// all of them.
///
/// The empty state reads differently depending on the filter: an empty inbox
/// and a cleared backlog are not the same thing, and telling a player "nothing
/// yet" when they have just read forty notifications would be wrong.
///
/// ## What a tap does
///
/// Marks the row read and, if its kind has a destination, goes there. The mark
/// is not conditional on the navigation: a notification whose kind this build
/// does not recognise still counts as read once it has been opened, which is
/// what stops an unknown type from pinning the badge on forever.
class NotificationsScreen extends ConsumerWidget {
  /// Creates the centre.
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<NotificationPage> inbox = ref.watch(notificationsProvider);
    final NotificationsNotifier notifier =
        ref.read(notificationsProvider.notifier);

    return AppScaffold(
      title: context.l10n.notificationsTitle,
      padded: false,
      actions: <Widget>[
        if ((inbox.valueOrNull?.unreadCount ?? 0) > 0)
          AppIconButton(
            tooltip: context.l10n.notificationsMarkAllRead,
            icon: Icons.done_all_rounded,
            onPressed: () => _markAllRead(context, notifier),
          ),
      ],
      child: Column(
        children: <Widget>[
          _FilterBar(
            unreadOnly: notifier.unreadOnly,
            unreadCount: inbox.valueOrNull?.unreadCount ?? 0,
            onChanged: (bool value) => notifier.setUnreadOnly(value: value),
          ),
          Expanded(
            child: inbox.when(
              loading: () => const AppLoadingState(),
              error: (Object error, StackTrace stack) => AppEmptyState(
                message:
                    error is Failure ? error.message : context.l10n.errorUnknown,
                icon: Icons.cloud_off_outlined,
                action: AppButton(
                  label: context.l10n.retry,
                  onPressed: notifier.refresh,
                ),
              ),
              data: (NotificationPage page) => _InboxList(
                page: page,
                unreadOnly: notifier.unreadOnly,
                onRefresh: notifier.refresh,
                onLoadMore: notifier.loadMore,
                onOpen: (AppNotification row) => _open(context, ref, row),
                onDelete: (AppNotification row) =>
                    _delete(context, notifier, row),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Marks a row read, then follows its kind's destination if it has one.
  ///
  /// The read is not awaited before navigating: the row has already settled
  /// locally, and making the player wait on a round trip to change screens
  /// would be a delay with nothing behind it. The server's count arrives while
  /// the next screen is drawing.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification row,
  ) async {
    final NotificationsNotifier notifier =
        ref.read(notificationsProvider.notifier);

    if (!row.isRead) unawaited(notifier.markRead(row.id));

    final String? route = lookFor(row.kind).route;
    if (route == null || !context.mounted) return;

    unawaited(context.pushNamed(route));
  }

  Future<void> _markAllRead(
    BuildContext context,
    NotificationsNotifier notifier,
  ) async {
    final Result<int> outcome = await notifier.markAllRead();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          switch (outcome) {
            Ok<int>() => context.l10n.notificationsAllMarkedRead,
            Err<int>(:final Failure failure) => failure.message,
          },
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    NotificationsNotifier notifier,
    AppNotification row,
  ) async {
    final Result<int> outcome = await notifier.remove(row.id);
    if (!context.mounted) return;

    // A failed delete puts the row back, because the card has already been
    // swiped off screen and leaving it gone would be a lie about what the
    // server holds.
    if (outcome case Err<int>(:final Failure failure)) {
      unawaited(notifier.refresh());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.notificationsDeleted)),
    );
  }
}

/// The unread filter, and the count it is filtering against.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.unreadOnly,
    required this.unreadCount,
    required this.onChanged,
  });

  final bool unreadOnly;
  final int unreadCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              unreadCount == 0
                  ? context.l10n.notificationsAllRead
                  : '$unreadCount ${context.l10n.notificationsUnreadOnly.toLowerCase()}',
              style: text.labelMedium?.copyWith(color: colors.textMuted),
            ),
          ),
          AppButton(
            label: context.l10n.notificationsUnreadOnly,
            icon: unreadOnly
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            variant: unreadOnly
                ? AppButtonVariant.primary
                : AppButtonVariant.ghost,
            onPressed: () => onChanged(!unreadOnly),
          ),
        ],
      ),
    );
  }
}

/// The rows, with pull-to-refresh and paging.
class _InboxList extends StatelessWidget {
  const _InboxList({
    required this.page,
    required this.unreadOnly,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpen,
    required this.onDelete,
  });

  final NotificationPage page;
  final bool unreadOnly;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final ValueChanged<AppNotification> onOpen;
  final ValueChanged<AppNotification> onDelete;

  @override
  Widget build(BuildContext context) {
    if (page.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            AppEmptyState(
              message: unreadOnly
                  ? context.l10n.notificationsAllRead
                  : context.l10n.notificationsEmpty,
              icon: unreadOnly
                  ? Icons.mark_email_read_outlined
                  : Icons.notifications_none_outlined,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        // Paging on scroll rather than on a button: the list is a history, and
        // a player scrolling back through it should not have to ask for more.
        onNotification: (ScrollNotification notification) {
          final ScrollMetrics metrics = notification.metrics;
          if (page.hasMore && metrics.pixels >= metrics.maxScrollExtent - 200) {
            unawaited(onLoadMore());
          }
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: page.items.length,
          itemBuilder: (BuildContext context, int index) {
            final AppNotification row = page.items[index];

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: NotificationCard(
                notification: row,
                onTap: () => onOpen(row),
                onDelete: () => onDelete(row),
              ),
            );
          },
        ),
      ),
    );
  }
}
