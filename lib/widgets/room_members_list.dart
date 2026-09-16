import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/sketch_scaffold.dart';
import 'package:scribble_guess/models/player.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/player_row.dart';

/// Who is in the room, with the count against the cap.
///
/// ## Why it takes a list rather than reading one
///
/// The lobby already holds the authoritative player list: it arrives on
/// `s:room:state` and is pushed again on every membership change, which is
/// what makes the list update the instant somebody accepts an invitation. A
/// widget that fetched its own would be a second, slower copy of something
/// already on screen — and the two would disagree for as long as the fetch
/// took.
///
/// So this renders what it is handed. `GET /api/rooms/:roomId/members` exists
/// for the cold read — a screen opened before the socket finished its
/// handshake — and it produces exactly these [Player] rows.
class RoomMembersList extends StatelessWidget {
  /// Creates the list.
  const RoomMembersList({
    required this.players,
    required this.maxPlayers,
    this.selfId,
    this.trailingOf,
    this.title,
    super.key,
  });

  /// Everybody seated, in the order the server sent them.
  final List<Player> players;

  /// The room's cap, for the count beside the heading.
  final int maxPlayers;

  /// The local player, whose row is highlighted.
  final String? selfId;

  /// Builds the trailing widget for one row — the host's moderation menu.
  ///
  /// A builder rather than a widget per row so the caller decides who gets one
  /// without this widget needing to know what a host is.
  final Widget? Function(Player player)? trailingOf;

  /// The heading above the list.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                (title ?? context.l10n.roomMembersTitle).toUpperCase(),
                style: text.labelSmall?.copyWith(color: colors.inkSoft),
              ),
            ),
            Text(
              '${players.length}/$maxPlayers',
              style: text.labelSmall?.copyWith(color: colors.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (players.isEmpty)
          SketchEmptyState(
            message: context.l10n.lobbyEmptyPlayers,
            icon: Icons.person_outline,
          )
        else
          for (final Player player in players)
            PlayerRow(
              player: player,
              isSelf: player.id == selfId,
              trailing: trailingOf?.call(player),
            ),
      ],
    );
  }
}
