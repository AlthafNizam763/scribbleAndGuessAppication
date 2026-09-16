import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/social_widgets.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Another player's profile, and every friend action that applies to them.
///
/// ## The buttons are a pure function of the server's relation
///
/// `PublicProfile.relation` is computed server-side and is the only input to
/// which buttons appear. Nothing here infers a relation from a friends list it
/// happens to have loaded, because that list can be stale and the server would
/// then refuse an action this screen had offered.
///
/// It is also why being blocked *by* somebody is not a state here: the server
/// reports `none` in that case, so a blocked player sees an ordinary Add
/// Friend button and a refusal that does not say why. That is deliberate — the
/// alternative tells them they were blocked.
class PlayerProfileScreen extends ConsumerStatefulWidget {
  /// Creates the profile screen for [userId].
  const PlayerProfileScreen({required this.userId, super.key});

  /// The server-issued id of the player being viewed.
  final String userId;

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen> {
  PublicProfile? _profile;
  Failure? _failure;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    final Result<PublicProfile> result =
        await ref.read(friendActionsProvider).profile(widget.userId);

    if (!mounted) return;

    setState(() {
      _loading = false;
      _profile = result.valueOrNull;
      _failure = result.failureOrNull;
    });
  }

  /// Runs a friend action and re-reads the profile it changed.
  ///
  /// The re-read is what keeps the buttons honest: rather than guessing the
  /// new relation, the screen asks the server what it is now. One extra round
  /// trip per action, on a screen where the player has just tapped and is
  /// already waiting.
  Future<void> _act(Future<Result<void>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);

    final Result<void> result = await action();

    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err<void>(:final Failure failure)) {
      notify(context, failure.message, isError: true);
      return;
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final PublicProfile? profile = _profile;

    return SketchScaffold(
      title: profile?.card.name.isNotEmpty ?? false
          ? profile!.card.name
          : context.l10n.playerProfileTitle,
      child: switch ((_loading, profile)) {
        (true, null) => const Center(child: CircularProgressIndicator()),
        (_, null) => SketchEmptyState(
            message: _failure?.message ?? context.l10n.errorUnknown,
            icon: Icons.person_off_outlined,
            action: SketchButton(
              label: context.l10n.retry,
              onPressed: _load,
            ),
          ),
        (_, final PublicProfile loaded) => _Body(
            profile: loaded,
            busy: _busy,
            onAct: _act,
          ),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.profile,
    required this.busy,
    required this.onAct,
  });

  final PublicProfile profile;
  final bool busy;
  final Future<void> Function(Future<Result<void>> Function()) onAct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        SketchCard(
          child: Column(
            children: <Widget>[
              PlayerAvatar(
                avatarId: profile.card.avatarId,
                colorIndex: profile.card.avatarColorIndex,
                size: 88,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                profile.card.name,
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(color: colors.ink),
              ),
              if (profile.locality != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  profile.locality!.display,
                  style: text.bodySmall?.copyWith(color: colors.inkSoft),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                profile.rank != null
                    ? '${context.l10n.playerProfileRank}  #${profile.rank}'
                    : context.l10n.playerProfileUnranked,
                style: text.labelMedium?.copyWith(color: colors.inkSoft),
              ),
              StatsStrip(stats: profile.stats),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Actions(profile: profile, busy: busy, onAct: onAct),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// The action buttons, chosen entirely by [PublicProfile.relation].
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.profile,
    required this.busy,
    required this.onAct,
  });

  final PublicProfile profile;
  final bool busy;
  final Future<void> Function(Future<Result<void>> Function()) onAct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FriendActions actions = ref.read(friendActionsProvider);
    final String userId = profile.card.id;

    return switch (profile.relation) {
      // Reached by tapping your own row somewhere that did not suppress it.
      // Nothing here applies to yourself.
      SocialRelation.self => const SizedBox.shrink(),

      SocialRelation.none => Column(
          children: <Widget>[
            SketchButton.primary(
              label: context.l10n.friendAdd,
              icon: Icons.person_add_alt,
              busy: busy,
              onPressed: () => onAct(() => actions.sendRequest(userId)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BlockButton(profile: profile, busy: busy, onAct: onAct),
          ],
        ),

      SocialRelation.requestSent => Column(
          children: <Widget>[
            SketchCard(
              child: Row(
                children: <Widget>[
                  Icon(Icons.schedule, size: 18, color: context.sketch.inkSoft),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    context.l10n.friendRequested,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: context.sketch.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SketchButton(
              label: context.l10n.friendCancelRequest,
              expand: true,
              busy: busy,
              onPressed: profile.pendingRequestId.isEmpty
                  ? null
                  : () => onAct(() => actions.cancel(profile.pendingRequestId)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BlockButton(profile: profile, busy: busy, onAct: onAct),
          ],
        ),

      SocialRelation.requestReceived => Column(
          children: <Widget>[
            SketchButton.primary(
              label: context.l10n.friendAccept,
              icon: Icons.check,
              busy: busy,
              onPressed: profile.pendingRequestId.isEmpty
                  ? null
                  : () => onAct(() => actions.accept(profile.pendingRequestId)),
            ),
            const SizedBox(height: AppSpacing.sm),
            SketchButton(
              label: context.l10n.friendReject,
              expand: true,
              onPressed: busy || profile.pendingRequestId.isEmpty
                  ? null
                  : () => onAct(() => actions.reject(profile.pendingRequestId)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BlockButton(profile: profile, busy: busy, onAct: onAct),
          ],
        ),

      SocialRelation.friends => Column(
          children: <Widget>[
            SketchCard(
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.people_alt_outlined,
                    size: 18,
                    color: context.sketch.ink,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    context.l10n.friendsAlready,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: context.sketch.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ConfirmButton(
              label: context.l10n.friendRemove,
              title: context.l10n.friendRemoveTitle,
              message: context.l10n.friendRemoveBody(profile.card.name),
              confirmLabel: context.l10n.friendRemove,
              busy: busy,
              onConfirmed: () => onAct(() => actions.removeFriend(userId)),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BlockButton(profile: profile, busy: busy, onAct: onAct),
          ],
        ),

      SocialRelation.blocked => Column(
          children: <Widget>[
            SketchCard(
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.block,
                    size: 18,
                    color: context.sketch.danger,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      context.l10n.friendBlocked,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: context.sketch.danger),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ConfirmButton(
              label: context.l10n.friendUnblock,
              title: context.l10n.friendUnblockTitle,
              message: context.l10n.friendUnblockBody,
              confirmLabel: context.l10n.friendUnblock,
              destructive: false,
              busy: busy,
              onConfirmed: () => onAct(() => actions.unblock(userId)),
            ),
          ],
        ),
    };
  }
}

/// The Block button, which every non-blocked state offers.
class _BlockButton extends ConsumerWidget {
  const _BlockButton({
    required this.profile,
    required this.busy,
    required this.onAct,
  });

  final PublicProfile profile;
  final bool busy;
  final Future<void> Function(Future<Result<void>> Function()) onAct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ConfirmButton(
      label: context.l10n.friendBlock,
      title: context.l10n.friendBlockTitle,
      message: context.l10n.friendBlockBody,
      confirmLabel: context.l10n.friendBlock,
      busy: busy,
      onConfirmed: () => onAct(
        () => ref.read(friendActionsProvider).block(profile.card.id),
      ),
    );
  }
}

/// A destructive button that asks first.
///
/// Removing a friend, blocking and unblocking all go through here, because all
/// three are things a player cannot simply undo with a second tap: a removed
/// friendship has to be re-requested and re-accepted, and a block tears down
/// the friendship on its way in.
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.label,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.busy,
    required this.onConfirmed,
    this.destructive = true,
  });

  final String label;
  final String title;
  final String message;
  final String confirmLabel;
  final bool busy;
  final bool destructive;
  final Future<void> Function() onConfirmed;

  @override
  Widget build(BuildContext context) {
    return SketchButton(
      label: label,
      expand: true,
      variant: destructive
          ? SketchButtonVariant.danger
          : SketchButtonVariant.secondary,
      busy: busy,
      onPressed: busy
          ? null
          : () async {
              final bool yes = await confirm(
                context,
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                destructive: destructive,
              );
              if (yes) await onConfirmed();
            },
    );
  }
}
