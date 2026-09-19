import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/responsive.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/validators.dart';
import 'package:scribble_guess/features/profile/locality_section.dart';
import 'package:scribble_guess/features/progression/xp_progress_widget.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/progression.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Name, face, colour and town — the editable half of a profile.
///
/// Split from `ProfileScreen`, which is the read-only card with the stats on
/// it. The two were one screen and should not have been: a profile is
/// something a player *shows* people, and an editor is something they open
/// occasionally, so putting a keyboard and a save button on the thing somebody
/// taps to look at their own record made both worse.
///
/// Doubles as the first-run screen: when there is no profile yet the back
/// arrow is hidden and saving continues to the menu, because a player without
/// a name has nowhere else to go. The router's redirect sends anybody without
/// a profile here rather than to the view, for the same reason.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late PlayerProfile _draft;
  late PlayerProfile _original;
  bool _saving = false;

  /// Whether this is the first run, decided once so that saving a new profile
  /// does not flip the screen's chrome mid-interaction.
  late final bool _isFirstRun;

  @override
  void initState() {
    super.initState();
    final PlayerProfile? existing = ref.read(profileProvider);
    _isFirstRun = existing == null;
    _original = existing ?? ProfileNotifier.blank();
    _draft = _original;
    _nameController = TextEditingController(text: _original.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _draft != _original || _nameController.text.trim() != _original.name;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);

    final PlayerProfile next =
        _draft.copyWith(name: _nameController.text.trim());
    final Result<void> result =
        await ref.read(profileProvider.notifier).save(next);

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    result.fold(
      (_) {
        _original = next;
        _draft = next;
        if (_isFirstRun) {
          context.goNamed(AppRoutes.home);
        } else {
          notify(context, context.l10n.profileSaved);
          context.pop();
        }
      },
      (Failure failure) => notify(context, failure.message, isError: true),
    );
  }

  Future<void> _handleBack() async {
    if (!_isDirty) {
      context.pop();
      return;
    }
    final bool discard = await confirm(
      context,
      title: context.l10n.profileDiscardTitle,
      message: context.l10n.profileDiscardBody,
      confirmLabel: context.l10n.discard,
      destructive: true,
    );
    if (discard && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: AppScaffold(
        title: context.l10n.profileTitle,
        showBack: !_isFirstRun,
        onBack: _handleBack,
        bottom: AppButton.primary(
          label: context.l10n.profileSave,
          icon: Icons.check,
          busy: _saving,
          onPressed: _save,
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: pagePadding(context),
            children: <Widget>[
              Center(
                child: PlayerAvatar(
                  avatarId: _draft.avatarId,
                  colorIndex: _draft.avatarColorIndex,
                  size: context.isCompact ? 96 : 112,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  AvatarCatalog.faceAt(_draft.avatarId).name,
                  style: text.labelMedium?.copyWith(color: colors.textMuted),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: AppButton(
                  label: context.l10n.profileRandomize,
                  icon: Icons.casino_outlined,
                  onPressed: () => setState(
                    () => _draft = ProfileNotifier.randomizeAppearance(_draft),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Level and XP, above the editable fields because they are the
              // one thing on this screen the player cannot change — a record
              // of what they have done, rather than a setting.
              //
              // Hidden until it loads rather than shown at zero: a bar that
              // said "level 1, 0 XP" while a read was in flight would be wrong
              // for the many players it is not true of.
              if (!_isFirstRun)
                Consumer(
                  builder: (BuildContext context, WidgetRef ref, Widget? _) {
                    final AsyncValue<Progression> progression =
                        ref.watch(progressionProvider);

                    if (!progression.hasValue) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        XpProgressWidget(level: progression.value!.level),
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: context.l10n.progressionViewAchievements,
                          icon: Icons.workspace_premium_outlined,
                          expand: true,
                          onPressed: () =>
                              context.pushNamed(AppRoutes.achievements),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    );
                  },
                ),

              Text(
                context.l10n.profileNameLabel,
                style: text.labelSmall?.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _nameController,
                maxLength: AppConstants.maxNameLength,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                autofocus: _isFirstRun,
                // `Validators` has no context, so its message is English
                // until it reaches a widget. This is that widget.
                validator: (String? value) {
                  final String? problem = Validators.username(value);
                  return problem == null
                      ? null
                      : context.l10n.fromEnglish(problem);
                },
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  hintText: context.l10n.profileNameHint,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _AvatarPicker(
                selected: _draft.avatarId,
                onSelected: (int id) =>
                    setState(() => _draft = _draft.copyWith(avatarId: id)),
              ),
              const SizedBox(height: AppSpacing.xl),
              const LocalitySection(),
              const SizedBox(height: AppSpacing.xl),
              _ColorPicker(
                selected: _draft.avatarColorIndex,
                onSelected: (int index) => setState(
                  () => _draft = _draft.copyWith(avatarColorIndex: index),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// The character grid: ten cats, one wrap.
///
/// The tabs are gone with the families. Eighteen faces across People, Animals
/// and Anime needed splitting into three; ten variations on one animal do not,
/// and a tab bar over a single family would be a control with one option.
///
/// Stateless now that there is no tab to remember, which also removes the
/// `didUpdateWidget` that existed only to follow the randomiser between
/// families.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    // Bigger targets where there is room; still at least the minimum tap
    // target on the narrowest phone.
    final double tile = switch (context.screenSize) {
      ScreenSize.compact => 56,
      ScreenSize.medium => 64,
      ScreenSize.expanded => 68,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.profileAvatarSection,
          style: text.labelSmall?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: <Widget>[
            for (final AvatarFace face in AvatarCatalog.faces)
              Semantics(
                label: face.name,
                selected: face.id == selected,
                child: ExcludeSemantics(
                  child: PlayerAvatar(
                    avatarId: face.id,
                    // Preview every character on one neutral disc so the
                    // choice is about the cat, not the colour behind it.
                    colorIndex: 0,
                    size: tile,
                    selected: face.id == selected,
                    onTap: () => onSelected(face.id),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.profileColorSection,
          style: text.labelSmall?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: <Widget>[
            for (int index = 0;
                index < AppConstants.avatarColorCount;
                index++)
              Semantics(
                button: true,
                selected: index == selected,
                label: 'Colour ${index + 1}',
                child: GestureDetector(
                  onTap: () => onSelected(index),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      // The disc the avatar will actually sit on, not the raw
                      // pigment behind it.
                      color: PlayerAvatar.discColor(colors, index),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: index == selected
                            ? colors.primary
                            : colors.border,
                        width: index == selected
                            ? AppSpacing.borderThick
                            : AppSpacing.hairline,
                      ),
                    ),
                    child: index == selected
                        ? Icon(Icons.check, size: 20, color: colors.text)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
