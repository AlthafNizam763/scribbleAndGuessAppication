import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/features/rooms/room_invitation_dialog.dart';
import 'package:scribble_guess/models/room_invite.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Every room invitation waiting for the local player.
///
/// ## Why this exists beside the pop-up
///
/// The pop-up only catches invitations that arrive while the app is open and
/// the player is not mid-turn. Everything else lands here: an invitation sent
/// while the phone was locked, one that arrived during a round, one the player
/// tapped "Later" on. Without the inbox those would be invisible, and the
/// server would be holding an invitation nobody could answer.
///
/// The list is the authoritative one — it is a REST read — so wherever it and
/// a pushed card disagree, this wins.
class RoomInvitationsScreen extends ConsumerWidget {
  /// Creates the inbox.
  const RoomInvitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RoomInvitation>> invitations =
        ref.watch(roomInvitationsProvider);

    return SketchScaffold(
      title: context.l10n.invitationsTitle,
      padded: false,
      child: invitations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => SketchEmptyState(
          message: error is Failure ? error.message : context.l10n.errorUnknown,
          icon: Icons.cloud_off_outlined,
          action: SketchButton(
            label: context.l10n.retry,
            onPressed: () => ref.read(roomInvitationsProvider.notifier).refresh(),
          ),
        ),
        data: (List<RoomInvitation> rows) {
          if (rows.isEmpty) {
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(roomInvitationsProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                  SketchEmptyState(
                    message: context.l10n.invitationsEmpty,
                    icon: Icons.mail_outline,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(roomInvitationsProvider.notifier).refresh(),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: rows.length,
              itemBuilder: (BuildContext context, int index) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: RoomInvitationCard(
                  invitation: rows[index],
                  // Answering removes the row here, so the card does not need
                  // to do anything else on its way out — the notifier already
                  // dropped it and re-read the list.
                  onAnswered: () {},
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
