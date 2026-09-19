import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/app_card.dart';
import 'package:scribble_guess/features/notifications/notification_icons.dart';
import 'package:scribble_guess/models/app_notification.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/player_avatar.dart';

/// One row of the notification centre.
///
/// ## What marks a row unread
///
/// A washed primary fill, a heavier title and a small filled dot in the
/// notification kind own colour. No shadow and no second card shape — an
/// unread row is the same card as a read one, tinted. That distinction reads
/// at a glance in both themes and costs no extra palette.
///
/// ## The avatar, when there is one
///
/// A notification caused by a person shows that person's doodle avatar; a
/// system one shows the kind's glyph. Both occupy the same square, so a mixed
/// list does not jog left and right as it scrolls.
class NotificationCard extends StatelessWidget {
  /// Creates a row.
  const NotificationCard({
    required this.notification,
    required this.onTap,
    this.onDelete,
    super.key,
  });

  /// The row to draw.
  final AppNotification notification;

  /// Called when the card is tapped. Marks read and navigates.
  final VoidCallback onTap;

  /// Called when the row is dismissed. Null hides the gesture.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final NotificationLook look = lookFor(notification.kind);
    final UserCard? actor = notification.actor;

    final Widget card = AppCard(
      onTap: onTap,
      // The unread cue. `selected` washes the card in the primary and thickens
      // its keyline, which is legible without turning the list into stripes.
      selected: !notification.isRead,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (actor != null)
            PlayerAvatar(
              avatarId: actor.avatarId,
              colorIndex: actor.avatarColorIndex,
              size: 40,
            )
          else
            _KindGlyph(look: look, colors: colors),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        notification.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          color: colors.text,
                          fontWeight: notification.isRead
                              ? AppTypography.semibold
                              : AppTypography.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      context.l10n.relativeShort(
                        notification.createdAtMs,
                        DateTime.now().millisecondsSinceEpoch,
                      ),
                      style: text.labelSmall?.copyWith(color: colors.textFaint),
                    ),
                    if (!notification.isRead) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      _UnreadDot(color: look.tint(colors)),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  notification.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onDelete == null) return card;

    return Dismissible(
      key: ValueKey<String>('notification-${notification.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (DismissDirection _) => onDelete?.call(),
      background: _DeleteBackground(colors: colors),
      child: card,
    );
  }
}

/// The square a system notification draws instead of an avatar.
class _KindGlyph extends StatelessWidget {
  const _KindGlyph({required this.look, required this.colors});

  final NotificationLook look;
  final AppPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.wash(look.tint(colors)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
          color: colors.washBorder(look.tint(colors)),
          width: AppSpacing.hairline,
        ),
      ),
      child: Icon(look.icon, size: 20, color: look.tint(colors)),
    );
  }
}

/// The small filled dot beside an unread row's timestamp.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// What shows behind a row being swiped away.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.colors});

  final AppPalette colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.wash(colors.danger),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Icon(Icons.delete_outline_rounded, color: colors.danger),
    );
  }
}

