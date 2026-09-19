import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/features/games/common/game_skin.dart';
import 'package:scribble_guess/features/games/common/landscape_game_scaffold.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/providers/games/platform_session.dart';
import 'package:scribble_guess/providers/profile_provider.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The chat panel, as a side drawer over the table.
///
/// ## Why an overlay and not a screen
///
/// Because the reason to open chat mid-match is to say something *about what
/// is happening*, and a full-screen panel hides the thing being talked about.
/// It takes a third of the width on a phone and a fixed column on a tablet,
/// and the table keeps playing behind it — which also means a player who
/// opened chat and then had the turn passed to them can see that it happened.
///
/// ## One panel, three games
///
/// The brief asks for chat to be reused rather than reimplemented, and this is
/// where that is honoured: it reads the shared [PlatformSession] transcript and
/// takes its colours from whichever [GameSkin] is installed above it. A card
/// table and a spaceship get the same panel in different pigments.
class GameChatOverlay extends ConsumerStatefulWidget {
  const GameChatOverlay({required this.open, required this.onClose, super.key});

  final bool open;
  final VoidCallback onClose;

  @override
  ConsumerState<GameChatOverlay> createState() => _GameChatOverlayState();
}

class _GameChatOverlayState extends ConsumerState<GameChatOverlay> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final Result<void> result =
        await ref.read(platformSessionProvider.notifier).sendChat(text);
    if (!mounted) return;

    setState(() => _sending = false);
    if (result case Ok<void>()) {
      // Cleared only on success, so a message refused for rate limiting is
      // still in the box to send again rather than lost.
      _composer.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final List<ChatMessage> messages = ref.watch(
      platformSessionProvider.select((PlatformSession s) => s.chat),
    );
    final String selfId = ref.watch(selfIdProvider);

    final double width = metrics.hasRoomForPanel
        ? 320.0
        : (metrics.size.width * 0.44).clamp(240.0, 340.0);

    return AnimatedPositioned(
      duration: AppMotion.normal,
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      right: widget.open ? 0 : -width,
      width: width,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(metrics.gutter * 0.5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: skin.surface.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: skin.edge, width: AppSpacing.border),
            ),
            child: Column(
              children: <Widget>[
                _Header(onClose: widget.onClose),
                Expanded(
                  child: messages.isEmpty
                      ? _Empty()
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.gutter * 0.75,
                            vertical: metrics.gutter * 0.5,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (BuildContext context, int index) {
                            // Reversed so new lines appear at the bottom
                            // without a scroll controller having to chase
                            // them — which is what makes a message arriving
                            // mid-turn not yank the list under a thumb.
                            final ChatMessage message =
                                messages[messages.length - 1 - index];
                            return _Line(
                              message: message,
                              isSelf: message.senderId == selfId,
                            );
                          },
                        ),
                ),
                _Composer(
                  controller: _composer,
                  sending: _sending,
                  onSend: _send,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: <Widget>[
          Text(
            'TABLE TALK',
            style: text.labelMedium?.copyWith(
              color: skin.inkMuted,
              fontFamily: skin.display,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, color: skin.inkMuted, size: 20),
            tooltip: 'Close chat',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'Nobody has said anything yet.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: skin.inkMuted),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.message, required this.isSelf});

  final ChatMessage message;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;
    final TextTheme text = Theme.of(context).textTheme;

    final bool isSystem = message.type == ChatMessageType.system ||
        message.type == ChatMessageType.playerJoined ||
        message.type == ChatMessageType.playerLeft;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(
            color: skin.inkMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment:
            isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isSelf ? 'You' : message.senderName,
            style: text.labelSmall?.copyWith(
              color: isSelf ? skin.accent : skin.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: isSelf
                  ? skin.accent.withValues(alpha: 0.16)
                  : skin.surfaceRaised,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              message.text,
              style: text.bodySmall?.copyWith(color: skin.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final GameSkin skin = context.skin;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !sending,
              maxLength: 200,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: TextStyle(color: skin.ink, fontSize: 13),
              cursorColor: skin.accent,
              decoration: InputDecoration(
                hintText: 'Say something',
                hintStyle: TextStyle(color: skin.inkMuted, fontSize: 13),
                counterText: '',
                isDense: true,
                filled: true,
                fillColor: skin.surfaceRaised,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            onPressed: sending ? null : onSend,
            icon: Icon(Icons.send_rounded, color: skin.accent, size: 20),
            tooltip: 'Send',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// A one-line banner for a server refusal, shown over the table and gone again.
///
/// A [SnackBar] would be wrong here: Material's floats at the bottom of the
/// screen, which in landscape is exactly where a player's own hand is, and it
/// steals a tap while it is up.
class GameErrorFlash extends ConsumerWidget {
  const GameErrorFlash({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GameSkin skin = context.skin;
    final GameMetrics metrics = context.metrics;
    final Failure? failure = ref.watch(
      platformSessionProvider.select((PlatformSession s) => s.lastError),
    );

    return AnimatedSwitcher(
      duration: AppMotion.normal,
      child: failure == null
          ? const SizedBox.shrink()
          : Align(
              key: ValueKey<String>(failure.message),
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 56 * metrics.scale),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: skin.danger,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    failure.message,
                    style: TextStyle(
                      color: skin.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 12 * metrics.scale,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
