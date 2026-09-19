import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';

/// A strip that appears only while the connection is unhealthy.
///
/// Connected is the silent case: a permanent "you are online" badge would be
/// noise, and the absence of this banner already says it.
///
/// Disconnected is silent too. "Offline" named a state the player could do
/// nothing about and that the app recovers from on its own, so the strip was
/// pure alarm. The states that remain are the ones worth a word: the two that
/// say a recovery is under way, and the one that says it has given up.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ConnectionStatus status = ref.watch(connectionProvider);
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    final (String message, Color tint, bool spinner) = switch (status) {
      ConnectionStatus.idle ||
      ConnectionStatus.connected ||
      ConnectionStatus.disconnected =>
        ('', Colors.transparent, false),
      ConnectionStatus.connecting => (
          context.l10n.statusConnecting,
          colors.info,
          true,
        ),
      ConnectionStatus.reconnecting => (
          context.l10n.statusReconnecting,
          colors.warning,
          true,
        ),
      ConnectionStatus.failed => (
          context.l10n.errorConnectionLost,
          colors.danger,
          false,
        ),
    };

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.wash(tint),
          border: Border(
            bottom: BorderSide(
              color: colors.washBorder(tint),
              width: AppSpacing.hairline,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (spinner) ...<Widget>[
              SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(tint),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: text.labelMedium?.copyWith(color: tint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
