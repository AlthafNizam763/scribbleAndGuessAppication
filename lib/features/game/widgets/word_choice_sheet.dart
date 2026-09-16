import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/game_state.dart';
import 'package:scribble_guess/models/word_item.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Offers the drawer their word choices, and resolves to the index they picked.
///
/// Returns `null` when the sheet closed without a choice — which is not a
/// failure but the ordinary outcome of the selection window expiring, since the
/// server picks a word on the drawer's behalf when that happens.
///
/// ## Why it closes itself
///
/// The sheet is tied to one thing only: the server saying the room is in
/// [GamePhase.wordSelection]. It watches for that to stop being true and pops.
/// Nothing else can leave it on screen — not the selection timing out, not the
/// round being abandoned because the room fell below the minimum number of
/// players, not another device of the drawer's choosing first. Owning the
/// dismissal here rather than at the call site is what keeps the sheet and the
/// authoritative phase from disagreeing.
///
/// Not dismissible by the player: the turn cannot proceed without a word.
Future<int?> showWordChoiceSheet(
  BuildContext context, {
  required List<WordItem> choices,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (BuildContext sheetContext) => _WordChoiceSheet(choices: choices),
  );
}

class _WordChoiceSheet extends ConsumerWidget {
  const _WordChoiceSheet({required this.choices});

  final List<WordItem> choices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    // The phase is the authority on whether there is still a word to choose.
    ref.listen<GameState>(gameProvider, (GameState? previous, GameState next) {
      if (next.phase != GamePhase.wordSelection && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    return PopScope(
      // A back gesture must not strand the room waiting on a sheet that is no
      // longer on screen.
      canPop: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                context.l10n.gameChooseWord,
                style: text.titleLarge?.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (int i = 0; i < choices.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SketchCard(
                    onTap: () => Navigator.of(context).pop(i),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            choices[i].text,
                            style: text.titleMedium?.copyWith(color: colors.ink),
                          ),
                        ),
                        SketchBadge(
                          label: choices[i].difficulty.label,
                          color: switch (choices[i].difficulty) {
                            WordDifficulty.easy => colors.success,
                            WordDifficulty.medium => colors.warning,
                            WordDifficulty.hard => colors.danger,
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
