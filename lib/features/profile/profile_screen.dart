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

/// Name, face and colour.
///
/// Doubles as the first-run screen: when there is no profile yet the back
/// arrow is hidden and saving continues to the menu, because a player without
/// a name has nowhere else to go.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
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
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: SketchScaffold(
        title: context.l10n.profileTitle,
        showBack: !_isFirstRun,
        onBack: _handleBack,
        bottom: SketchButton.primary(
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
                  style: text.labelMedium?.copyWith(color: colors.inkSoft),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: SketchButton(
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
                        SketchButton(
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
                style: text.labelSmall?.copyWith(color: colors.inkSoft),
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

/// The character grid, split into people, animals and anime.
///
/// The families are tabbed rather than laid out end to end: eighteen faces in
/// one wrap is a wall, and the tab a player lands on tells them at a glance
/// that the other kinds exist.
class _AvatarPicker extends StatefulWidget {
  const _AvatarPicker({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  /// Opens on the family the current avatar belongs to, so the player can see
  /// what they are wearing before they see the alternatives.
  late AvatarKind _kind = AvatarCatalog.faceAt(widget.selected).kind;

  @override
  void didUpdateWidget(_AvatarPicker old) {
    super.didUpdateWidget(old);
    // Follow the avatar when it changes from outside — the randomiser can
    // land on any family.
    if (widget.selected != old.selected) {
      _kind = AvatarCatalog.faceAt(widget.selected).kind;
    }
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final List<AvatarFace> faces = AvatarCatalog.of(_kind);

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
          style: text.labelSmall?.copyWith(color: colors.inkSoft),
        ),
        const SizedBox(height: AppSpacing.sm),
        SketchChipGroup<AvatarKind>(
          options: AvatarKind.values,
          labelOf: (AvatarKind kind) => kind.label,
          isSelected: (AvatarKind kind) => kind == _kind,
          onToggle: (AvatarKind kind) => setState(() => _kind = kind),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: <Widget>[
            for (final AvatarFace face in faces)
              PlayerAvatar(
                avatarId: face.id,
                // Preview every character on one neutral disc so the choice
                // is about the character, not the colour behind it.
                colorIndex: 0,
                size: tile,
                selected: face.id == widget.selected,
                onTap: () => widget.onSelected(face.id),
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
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.profileColorSection,
          style: text.labelSmall?.copyWith(color: colors.inkSoft),
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
                        color: colors.ink,
                        width: index == selected
                            ? AppSpacing.border + 2
                            : AppSpacing.border,
                      ),
                    ),
                    child: index == selected
                        ? Icon(Icons.check, size: 20, color: colors.ink)
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
