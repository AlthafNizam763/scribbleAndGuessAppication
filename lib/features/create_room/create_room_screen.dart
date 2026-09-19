import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/constants/game_defaults.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/validators.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/models/room_settings.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Room rules, then host.
class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  RoomSettings _settings = RoomSettings.defaults;
  final TextEditingController _wordController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  void _update(RoomSettings next) => setState(() => _settings = next);

  void _addCustomWord() {
    final String word = _wordController.text.trim();
    final String? problem = Validators.customWord(word);
    if (problem != null) {
      notify(context, problem, isError: true);
      return;
    }
    if (_settings.customWords.any(
      (String existing) => existing.toLowerCase() == word.toLowerCase(),
    )) {
      _wordController.clear();
      return;
    }
    _update(
      _settings.copyWith(
        customWords: <String>[..._settings.customWords, word],
      ),
    );
    _wordController.clear();
  }

  Future<void> _create() async {
    final List<String> problems = _settings.validate();
    if (problems.isNotEmpty) {
      notify(context, problems.first, isError: true);
      return;
    }

    setState(() => _creating = true);
    final Result<Room> result =
        await ref.read(roomControllerProvider).createRoom(_settings);

    if (!mounted) {
      return;
    }
    setState(() => _creating = false);

    result.fold(
      (Room room) => context.goNamed(AppRoutes.lobby),
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final bool customMode = _settings.customWords.isNotEmpty;

    return AppScaffold(
      title: context.l10n.createTitle,
      banner: const ConnectionBanner(),
      actions: <Widget>[
        TextButton(
          onPressed: _creating ? null : () => _update(RoomSettings.defaults),
          child: Text(context.l10n.createReset),
        ),
      ],
      bottom: AppButton.primary(
        label: context.l10n.createSubmit,
        icon: Icons.play_arrow,
        busy: _creating,
        onPressed: _create,
      ),
      child: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          AppSection(
            title: context.l10n.createRulesSection,
            children: <Widget>[
              AppStepperTile(
                label: context.l10n.createMaxPlayers,
                value: _settings.maxPlayers,
                range: GameDefaults.maxPlayersRange,
                onChanged: (int v) => _update(_settings.copyWith(maxPlayers: v)),
              ),
              AppStepperTile(
                label: context.l10n.createRounds,
                value: _settings.rounds,
                range: GameDefaults.roundsRange,
                onChanged: (int v) => _update(_settings.copyWith(rounds: v)),
              ),
              AppStepperTile(
                label: context.l10n.createDrawTime,
                value: _settings.drawTimeSeconds,
                range: GameDefaults.drawTimeRange,
                step: GameDefaults.drawTimeStepSeconds,
                suffix: 's',
                onChanged: (int v) =>
                    _update(_settings.copyWith(drawTimeSeconds: v)),
              ),
              AppStepperTile(
                label: context.l10n.createHints,
                value: _settings.hintCount,
                range: GameDefaults.hintRange,
                onChanged: (int v) => _update(_settings.copyWith(hintCount: v)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          AppSection(
            title: context.l10n.createWordsSection,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.createWordMode,
                      style: text.bodyLarge?.copyWith(color: colors.text),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppChipGroup<WordMode>(
                      options: WordMode.values,
                      labelOf: (WordMode m) => m.label,
                      isSelected: (WordMode m) => m == _settings.wordMode,
                      onToggle: (WordMode m) =>
                          _update(_settings.copyWith(wordMode: m)),
                    ),
                  ],
                ),
              ),
              AppStepperTile(
                label: context.l10n.createWordChoices,
                value: _settings.wordChoiceCount,
                range: GameDefaults.wordChoiceRange,
                onChanged: (int v) =>
                    _update(_settings.copyWith(wordChoiceCount: v)),
              ),
              AppStepperTile(
                label: context.l10n.createWordSelectTime,
                value: _settings.wordSelectSeconds,
                range: GameDefaults.wordSelectRange,
                step: GameDefaults.wordSelectStepSeconds,
                suffix: 's',
                onChanged: (int v) =>
                    _update(_settings.copyWith(wordSelectSeconds: v)),
              ),
            ],
          ),
          if (customMode) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            _CustomWords(
              words: _settings.customWords,
              controller: _wordController,
              onAdd: _addCustomWord,
              onRemove: (String word) => _update(
                _settings.copyWith(
                  customWords: <String>[
                    for (final String w in _settings.customWords)
                      if (w != word) w,
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppSection(
            title: context.l10n.createRoomSection,
            children: <Widget>[
              AppToggleTile(
                label: context.l10n.createAllowVoteKick,
                value: _settings.allowVoteKick,
                onChanged: (bool v) =>
                    _update(_settings.copyWith(allowVoteKick: v)),
              ),
              AppToggleTile(
                label: context.l10n.createPrivate,
                subtitle: context.l10n.createPrivateHint,
                value: _settings.isPrivate,
                onChanged: (bool v) => _update(_settings.copyWith(isPrivate: v)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _CustomWords extends StatelessWidget {
  const _CustomWords({
    required this.words,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> words;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final int needed = GameDefaults.minCustomWords - words.length;

    return AppSection(
      title: context.l10n.createCustomWords,
      trailing: Text(
        '${words.length}',
        style: text.labelSmall?.copyWith(color: colors.textMuted),
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAdd(),
                  decoration: InputDecoration(
                    hintText: context.l10n.createCustomWordHint,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                color: colors.text,
              ),
            ],
          ),
        ),
        if (words.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              context.l10n.createCustomWordsEmpty,
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final String word in words)
                  InputChip(
                    label: Text(word),
                    onDeleted: () => onRemove(word),
                  ),
              ],
            ),
          ),
        if (needed > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Add $needed more to start.',
              style: text.bodySmall?.copyWith(color: colors.warning),
            ),
          ),
      ],
    );
  }
}
