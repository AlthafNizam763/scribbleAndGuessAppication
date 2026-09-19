import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/social_widgets.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Incoming and outgoing friend requests.
///
/// Reachable on its own from the home screen's badge, and embedded as a tab of
/// [FriendsScreen] — which is why the list itself is [FriendRequestsView]
/// rather than being built into this screen. One implementation, two places to
/// find it.
class FriendRequestsScreen extends StatelessWidget {
  /// Creates the requests screen.
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: context.l10n.friendRequestsTitle,
      padded: false,
      constrained: false,
      child: const FriendRequestsView(),
    );
  }
}

/// The requests list: who is waiting on you, and who you are waiting on.
class FriendRequestsView extends ConsumerWidget {
  /// Creates the requests list.
  const FriendRequestsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FriendsState> friends = ref.watch(friendsProvider);

    return friends.when(
      loading: () => const AppLoadingState(),
      error: (Object error, StackTrace stack) => AppEmptyState(
        message: error is Failure ? error.message : context.l10n.errorUnknown,
        icon: Icons.cloud_off_outlined,
        action: AppButton(
          label: context.l10n.retry,
          onPressed: () => ref.read(friendsProvider.notifier).refresh(),
        ),
      ),
      data: (FriendsState state) {
        if (state.incoming.isEmpty && state.outgoing.isEmpty) {
          return _Refreshable(
            ref: ref,
            child: AppEmptyState(
              message: context.l10n.friendRequestsEmpty,
              icon: Icons.mark_email_unread_outlined,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              if (state.incoming.isNotEmpty) ...<Widget>[
                _Heading(label: context.l10n.friendRequestsIncoming),
                for (final FriendRequest request in state.incoming)
                  _IncomingRow(request: request),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (state.outgoing.isNotEmpty) ...<Widget>[
                _Heading(label: context.l10n.friendRequestsOutgoing),
                for (final FriendRequest request in state.outgoing)
                  _OutgoingRow(request: request),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Wraps an empty state in something a pull-to-refresh can act on.
class _Refreshable extends StatelessWidget {
  const _Refreshable({required this.ref, required this.child});

  final WidgetRef ref;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
          child,
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: context.palette.textMuted),
      ),
    );
  }
}

/// A request waiting on the local player: accept, reject, or open the profile.
class _IncomingRow extends ConsumerStatefulWidget {
  const _IncomingRow({required this.request});

  final FriendRequest request;

  @override
  ConsumerState<_IncomingRow> createState() => _IncomingRowState();
}

class _IncomingRowState extends ConsumerState<_IncomingRow> {
  /// Blocks a second tap while the first is in flight.
  ///
  /// The server makes a repeated accept a no-op — the request has already left
  /// `pending` — but without this the player sees two spinners and then an
  /// error for the tap that lost, which reads as a failure when nothing
  /// actually went wrong.
  bool _busy = false;

  Future<void> _run(Future<Result<void>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);

    final Result<void> result = await action();

    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err<void>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final FriendActions actions = ref.read(friendActionsProvider);
    final UserCard card = widget.request.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        children: <Widget>[
          PlayerTile(
            card: card,
            onTap: () => context.pushNamed(
              AppRoutes.playerProfile,
              pathParameters: <String, String>{'userId': card.id},
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    label: context.l10n.friendAccept,
                    icon: Icons.check,
                    expand: true,
                    variant: AppButtonVariant.primary,
                    busy: _busy,
                    onPressed: () =>
                        _run(() => actions.accept(widget.request.id)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: context.l10n.friendReject,
                    expand: true,
                    onPressed: _busy
                        ? null
                        : () => _run(() => actions.reject(widget.request.id)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A request the local player sent, with the option to withdraw it.
class _OutgoingRow extends ConsumerStatefulWidget {
  const _OutgoingRow({required this.request});

  final FriendRequest request;

  @override
  ConsumerState<_OutgoingRow> createState() => _OutgoingRowState();
}

class _OutgoingRowState extends ConsumerState<_OutgoingRow> {
  bool _busy = false;

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);

    final Result<void> result =
        await ref.read(friendActionsProvider).cancel(widget.request.id);

    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err<void>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UserCard card = widget.request.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: PlayerTile(
        card: card,
        subtitle: context.l10n.friendRequested,
        onTap: () => context.pushNamed(
          AppRoutes.playerProfile,
          pathParameters: <String, String>{'userId': card.id},
        ),
        trailing: AppButton(
          label: context.l10n.cancel,
          busy: _busy,
          onPressed: _busy ? null : _cancel,
        ),
      ),
    );
  }
}
