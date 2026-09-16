import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/sketch_scaffold.dart';
import 'package:scribble_guess/models/chat_message.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The scrolling transcript of guesses and system notices.
class ChatList extends StatefulWidget {
  const ChatList({required this.messages, this.selfId = '', super.key});

  final List<ChatMessage> messages;
  final String selfId;

  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(ChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      _scrollToEnd();
    }
  }

  /// Keeps the newest line in view.
  ///
  /// Deferred to the next frame because the new item has not been laid out
  /// yet when `didUpdateWidget` runs, so its extent is not in the metrics.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) {
        return;
      }
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: AppMotion.normal,
        curve: AppMotion.standard,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return SketchEmptyState(
        message: context.l10n.chatEmpty,
        icon: Icons.chat_bubble_outline,
      );
    }

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: widget.messages.length,
      itemBuilder: (BuildContext context, int index) => _ChatLine(
        message: widget.messages[index],
        isSelf: widget.messages[index].senderId == widget.selfId,
      ),
    );
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.message, required this.isSelf});

  final ChatMessage message;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    // System lines are centred and italic; player lines read as a transcript.
    final bool isSystem = switch (message.type) {
      ChatMessageType.system ||
      ChatMessageType.playerJoined ||
      ChatMessageType.playerLeft ||
      ChatMessageType.hint =>
        true,
      _ => false,
    };

    final Color tint = switch (message.type) {
      ChatMessageType.correctGuess => colors.success,
      ChatMessageType.closeGuess => colors.warning,
      ChatMessageType.playerJoined => colors.success,
      ChatMessageType.playerLeft => colors.danger,
      ChatMessageType.hint => colors.info,
      ChatMessageType.system => colors.inkSoft,
      _ => colors.ink,
    };

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 3,
        ),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(
            color: tint,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final bool highlight = message.type == ChatMessageType.correctGuess ||
        message.type == ChatMessageType.closeGuess;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: highlight
          ? BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            )
          : null,
      child: RichText(
        text: TextSpan(
          style: text.bodyMedium?.copyWith(color: colors.ink),
          children: <InlineSpan>[
            TextSpan(
              text: '${message.senderName}: ',
              style: text.bodyMedium?.copyWith(
                color: isSelf ? colors.accentBlue : colors.inkSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: message.type == ChatMessageType.correctGuess
                  ? context.l10n.gameYouGuessedIt
                  : message.text,
              style: text.bodyMedium?.copyWith(
                color: highlight ? tint : colors.ink,
                fontWeight: highlight ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The guess box.
///
/// Disabled with an explanatory hint rather than hidden when the player may
/// not guess, so the layout does not jump between turns.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.onSend,
    required this.enabled,
    this.hint,
    super.key,
  });

  final ValueChanged<String> onSend;
  final bool enabled;
  final String? hint;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  void _submit() {
    final String text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) {
      return;
    }
    widget.onSend(text);
    _controller.clear();
    // Keep focus so a run of guesses does not need a tap between each.
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            maxLength: AppConstants.maxChatLength,
            textInputAction: TextInputAction.send,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(AppConstants.maxChatLength),
            ],
            decoration: InputDecoration(
              hintText: widget.hint ?? context.l10n.chatGuessHint,
              counterText: '',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          onPressed: widget.enabled ? _submit : null,
          icon: const Icon(Icons.send),
          tooltip: context.l10n.chatSend,
          color: colors.ink,
        ),
      ],
    );
  }
}
