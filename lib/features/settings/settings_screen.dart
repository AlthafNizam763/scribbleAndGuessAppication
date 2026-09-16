import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/features/profile/location_flow.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// App preferences.
///
/// Every control writes through immediately; there is no save button, because
/// a settings screen that can be abandoned half-applied is a bug factory.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _resetAll() async {
    final bool yes = await confirm(
      context,
      title: context.l10n.settingsResetTitle,
      message: context.l10n.settingsResetBody,
      confirmLabel: context.l10n.settingsResetAll,
      destructive: true,
    );
    if (!yes || !mounted) {
      return;
    }
    await ref.read(settingsProvider.notifier).resetAll();
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsNotifier notifier = ref.read(settingsProvider.notifier);

    return SketchScaffold(
      title: context.l10n.settingsTitle,
      child: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          SketchSection(
            title: context.l10n.settingsFeedbackSection,
            children: <Widget>[
              SketchToggleTile(
                label: context.l10n.settingsSound,
                value: settings.soundEnabled,
                onChanged: notifier.setSoundEnabled,
              ),
              SketchToggleTile(
                label: context.l10n.settingsHaptics,
                value: settings.hapticsEnabled,
                onChanged: notifier.setHapticsEnabled,
              ),
              SketchToggleTile(
                label: context.l10n.settingsReducedMotion,
                subtitle: context.l10n.settingsReducedMotionHint,
                value: settings.reducedMotion,
                onChanged: notifier.setReducedMotion,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SketchSection(
            title: context.l10n.settingsAppearanceSection,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.settingsTheme,
                      style: text.bodyLarge?.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SketchChipGroup<SketchThemeMode>(
                      options: SketchThemeMode.values,
                      labelOf: (SketchThemeMode m) => m.label,
                      isSelected: (SketchThemeMode m) => m == settings.themeMode,
                      onToggle: notifier.setThemeMode,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SketchSection(
            title: context.l10n.settingsLanguageSection,
            children: const <Widget>[_LanguageTile()],
          ),
          const SizedBox(height: AppSpacing.xl),
          SketchSection(
            title: context.l10n.settingsLocationSection,
            children: const <Widget>[_LocationTile()],
          ),
          const SizedBox(height: AppSpacing.xl),
          SketchSection(
            title: context.l10n.settingsAboutSection,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        context.l10n.settingsVersion,
                        style: text.bodyLarge?.copyWith(color: colors.ink),
                      ),
                    ),
                    Text(
                      AppConstants.appVersion,
                      style: text.bodyMedium?.copyWith(color: colors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SketchButton(
            label: context.l10n.settingsResetAll,
            icon: Icons.restart_alt,
            variant: SketchButtonVariant.danger,
            expand: true,
            onPressed: _resetAll,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// The interface language picker.
///
/// Endonyms rather than English names, because somebody hunting for their own
/// language scans for the word they call it by, not for the word we do.
///
/// The hint underneath is deliberate and not a placeholder: choosing Arabic
/// today mirrors the layout, localises dates and numbers, and leaves most of
/// the game's own copy in English, because those strings have not been
/// translated yet. Saying so here is better than letting a player conclude the
/// setting is broken.
class _LanguageTile extends ConsumerWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final AppLanguage current = ref.watch(appLanguageProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.settingsLanguage,
            style: text.bodyLarge?.copyWith(color: colors.ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.settingsLanguageHint,
            style: text.bodySmall?.copyWith(color: colors.inkSoft),
          ),
          const SizedBox(height: AppSpacing.sm),
          SketchChipGroup<AppLanguage>(
            options: AppLanguage.values,
            labelOf: (AppLanguage l) => l.label,
            isSelected: (AppLanguage l) => l == current,
            onToggle: ref.read(settingsProvider.notifier).setLanguage,
          ),
        ],
      ),
    );
  }
}

/// The second way into the location flow, for a player who is not renaming
/// themselves.
///
/// The profile section is where the locality is edited in full — detected,
/// typed or cleared. This is only the refresh, because that is the thing
/// somebody comes back for: they moved, and the board they are on is the one
/// they left. It runs the same [runLocationUpdate] as the profile does, so the
/// explanation and every refusal path are identical from here.
///
/// Hidden entirely on a build that cannot detect, where it would be a button
/// that only ever apologises. Those players set their town on the profile.
class _LocationTile extends ConsumerWidget {
  const _LocationTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    // Asked of the service rather than of the notifier, because the notifier
    // fetches the locality when it is first read. On a build that cannot
    // detect there is nothing to draw here, and a Settings screen that has
    // never needed the network should not start needing it to render nothing.
    if (!ref.watch(locationServiceProvider).isSupported) {
      return const SizedBox.shrink();
    }

    final Locality? saved = ref.watch(localityProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            saved?.display ?? context.l10n.locationNoneSet,
            style: text.bodyLarge?.copyWith(
              color: saved == null ? colors.inkSoft : colors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.locationSettingsHint,
            style: text.bodySmall?.copyWith(color: colors.inkSoft),
          ),
          const SizedBox(height: AppSpacing.sm),
          SketchButton(
            label: context.l10n.locationSettingsRow,
            icon: Icons.my_location,
            expand: true,
            onPressed: () => runLocationUpdate(context, ref),
          ),
        ],
      ),
    );
  }
}
