import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/config/app_brand_config.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/features/profile/location_flow.dart';
import 'package:scribble_guess/features/settings/account_actions.dart';
import 'package:scribble_guess/models/app_settings.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/models/player_profile.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/models/user_preferences.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Everything about this account and this device, in six sections.
///
/// ## The one distinction that organises this screen
///
/// Some of these settings belong to a **device** and some belong to an
/// **account**, and they are stored in different places for a reason that
/// matters. Sound, music, haptics, motion, theme and language never leave the
/// phone: somebody who mutes the game on a train has not asked for silence on
/// their tablet. Notifications and privacy live on the server, because the
/// server is what acts on them — a push is composed and delivered while the
/// app is closed, so a mute stored here would run on a handset that has
/// already buzzed.
///
/// Both write through immediately; there is no save button, because a settings
/// screen that can be abandoned half-applied is a bug factory. The account
/// switches are optimistic and roll back if the server refuses, which the
/// preferences notifier owns.
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
    if (!yes || !mounted) return;
    await ref.read(settingsProvider.notifier).resetAll();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsNotifier notifier = ref.read(settingsProvider.notifier);

    return AppScaffold(
      title: context.l10n.settingsTitle,
      child: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          const _AccountSection(),
          const SizedBox(height: AppSpacing.xl),

          // ---- Game -------------------------------------------------------
          AppSection(
            title: 'Game',
            children: <Widget>[
              AppToggleTile(
                label: context.l10n.settingsSound,
                value: settings.soundEnabled,
                onChanged: notifier.setSoundEnabled,
              ),
              AppToggleTile(
                label: context.l10n.settingsHaptics,
                value: settings.hapticsEnabled,
                onChanged: notifier.setHapticsEnabled,
              ),
              AppToggleTile(
                label: context.l10n.settingsReducedMotion,
                subtitle: context.l10n.settingsReducedMotionHint,
                value: settings.reducedMotion,
                onChanged: notifier.setReducedMotion,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Notifications ---------------------------------------------
          const _NotificationsSection(),
          const SizedBox(height: AppSpacing.xl),

          // ---- Privacy ----------------------------------------------------
          const _PrivacySection(),
          const SizedBox(height: AppSpacing.xl),

          // ---- Appearance -------------------------------------------------
          AppSection(
            title: context.l10n.settingsAppearanceSection,
            children: <Widget>[
              _ChoiceTile<AppThemeMode>(
                label: context.l10n.settingsTheme,
                options: AppThemeMode.values,
                labelOf: (AppThemeMode m) => m.label,
                isSelected: (AppThemeMode m) => m == settings.themeMode,
                onToggle: notifier.setThemeMode,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          AppSection(
            title: context.l10n.settingsLanguageSection,
            children: const <Widget>[_LanguageTile()],
          ),
          const SizedBox(height: AppSpacing.xl),

          AppSection(
            title: context.l10n.settingsLocationSection,
            children: const <Widget>[_LocationTile()],
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Support ----------------------------------------------------
          const _SupportSection(),
          const SizedBox(height: AppSpacing.xl),

          // ---- About ------------------------------------------------------
          AppSection(
            title: context.l10n.settingsAboutSection,
            children: <Widget>[
              _ValueRow(
                label: context.l10n.settingsVersion,
                value: AppConstants.appVersion,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: context.l10n.settingsResetAll,
                icon: Icons.restart_alt,
                expand: true,
                onPressed: _resetAll,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Account actions --------------------------------------------
          // Last, and visually separated: these are the two things on this
          // screen somebody cannot undo, and neither should sit next to a
          // volume switch where a mis-tap lands.
          const AccountActionsSection(),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

/// Who this device is signed in as, and the ways to change that.
///
/// A guest sees an invitation to secure the account rather than a warning:
/// registering upgrades the row they are already playing on, so nothing is at
/// risk *unless* they lose the device — which is exactly what signing up
/// prevents.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isGuest = ref.watch(isAnonymousProvider);
    final PlayerProfile? profile = ref.watch(profileProvider);

    return AppSection(
      title: context.l10n.settingsAccountSection,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              if (profile != null) ...<Widget>[
                PlayerAvatar.ofProfile(profile, size: 44),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      profile?.name ?? context.l10n.loginAsGuest,
                      style: text.bodyLarge?.copyWith(color: colors.text),
                    ),
                    Text(
                      isGuest
                          ? context.l10n.settingsAccountGuest
                          : context.l10n.settingsAccountLinked,
                      style: text.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Edit profile',
          icon: Icons.edit_outlined,
          expand: true,
          onPressed: () => context.pushNamed(AppRoutes.editProfile),
        ),
        if (isGuest) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: context.l10n.registerAction,
            icon: Icons.shield_outlined,
            variant: AppButtonVariant.primary,
            expand: true,
            onPressed: () => context.pushNamed(AppRoutes.register),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications and privacy
// ---------------------------------------------------------------------------

/// The four push switches, read from and written to the account.
class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<UserPreferences> prefs = ref.watch(userPreferencesProvider);

    return AppSection(
      title: 'Notifications',
      children: <Widget>[
        prefs.when(
          loading: () => const _PreferenceSkeleton(rows: 4),
          error: (Object error, StackTrace stack) => _PreferenceError(
            message:
                error is Failure ? error.message : context.l10n.errorUnknown,
            onRetry: () => ref.read(userPreferencesProvider.notifier).refresh(),
          ),
          data: (UserPreferences value) => Column(
            children: <Widget>[
              // Said out loud, because somebody who muted all four and then
              // wonders why invitations never arrive has no other way to
              // discover what they did.
              if (!value.anyNotificationEnabled)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _Notice(
                    icon: Icons.notifications_off_outlined,
                    message:
                        'Every notification is off. Nothing will reach you '
                        'while the app is closed.',
                  ),
                ),
              _PreferenceTile(
                label: 'Game invites',
                subtitle: 'When somebody asks you to join a room.',
                value: value.notifyGameInvites,
                settingKey: 'notifyGameInvites',
              ),
              _PreferenceTile(
                label: 'Friend activity',
                subtitle: 'Friend requests, and when they are accepted.',
                value: value.notifyFriendActivity,
                settingKey: 'notifyFriendActivity',
              ),
              _PreferenceTile(
                label: 'Room activity',
                subtitle: 'When a room you are in needs you.',
                value: value.notifyRoomActivity,
                settingKey: 'notifyRoomActivity',
              ),
              _PreferenceTile(
                label: 'Announcements',
                subtitle: 'News and tournaments. Never marketing.',
                value: value.notifySystem,
                settingKey: 'notifySystem',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What other players may see, and who may find this account.
class _PrivacySection extends ConsumerWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<UserPreferences> prefs = ref.watch(userPreferencesProvider);

    return AppSection(
      title: 'Privacy',
      children: <Widget>[
        prefs.when(
          loading: () => const _PreferenceSkeleton(rows: 2),
          // One error message per screen is enough: the notifications section
          // above already offers the retry, and this reads from the same call.
          error: (Object error, StackTrace stack) => const SizedBox.shrink(),
          data: (UserPreferences value) => Column(
            children: <Widget>[
              _PreferenceTile(
                label: 'Show when I am online',
                subtitle: 'Friends always see this.',
                value: value.showOnlineStatus,
                settingKey: 'showOnlineStatus',
              ),
              _PreferenceTile(
                label: 'Findable by username',
                subtitle: 'Turn off to stay out of player search.',
                value: value.discoverable,
                settingKey: 'discoverable',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One account switch. Optimistic, and says so when the server refuses.
class _PreferenceTile extends ConsumerWidget {
  const _PreferenceTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.settingKey,
  });

  final String label;
  final String subtitle;
  final bool value;

  /// The wire key, which is also what the server's patch names.
  final String settingKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppToggleTile(
      label: label,
      subtitle: subtitle,
      value: value,
      onChanged: (bool next) async {
        final Failure? failure = await ref
            .read(userPreferencesProvider.notifier)
            .set(settingKey, next);

        // The notifier has already rolled the switch back; this only explains
        // why it moved and then moved again.
        if (failure != null && context.mounted) {
          notify(context, failure.message, isError: true);
        }
      },
    );
  }
}

/// Inert rows while the switches load, so the section does not jump.
class _PreferenceSkeleton extends StatelessWidget {
  const _PreferenceSkeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading your preferences',
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: AppSkeleton(height: 36, radius: AppSpacing.radiusSm),
            ),
        ],
      ),
    );
  }
}

/// Shown when the account switches could not be read.
class _PreferenceError extends StatelessWidget {
  const _PreferenceError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Notice(icon: Icons.cloud_off_outlined, message: message),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: context.l10n.retry,
          icon: Icons.refresh,
          expand: true,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

/// A quiet inline note.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: colors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Support
// ---------------------------------------------------------------------------

/// How to play, and how to reach a person.
class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: 'Support',
      children: <Widget>[
        AppButton(
          label: context.l10n.howToPlayTitle,
          icon: Icons.help_outline,
          expand: true,
          onPressed: () => context.pushNamed(AppRoutes.howToPlay),
        ),
        const SizedBox(height: AppSpacing.sm),
        // A plain, copyable address rather than a mailto: link. A tap that
        // opens nothing — no mail app configured, a launcher the platform
        // refuses — is worse than an address somebody can read and use.
        _ValueRow(
          label: 'Contact',
          value: AppBrandConfig.current.supportEmail,
          selectable: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _Notice(
          icon: Icons.flag_outlined,
          message:
              'To report a player, open their profile from the scoreboard and '
              'use Report — it sends us the room and the round.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

/// A label with a value on the right.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: text.bodyLarge?.copyWith(color: colors.text)),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (selectable)
            Flexible(
              child: SelectableText(
                value,
                textAlign: TextAlign.end,
                style: text.bodySmall?.copyWith(color: colors.textMuted),
              ),
            )
          else
            Text(value, style: text.bodyMedium?.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}

/// A labelled row of chips.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.options,
    required this.labelOf,
    required this.isSelected,
    required this.onToggle,
    this.hint,
  });

  final String label;
  final String? hint;
  final List<T> options;
  final String Function(T) labelOf;
  final bool Function(T) isSelected;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: text.bodyLarge?.copyWith(color: colors.text)),
          if (hint != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(hint!, style: text.bodySmall?.copyWith(color: colors.textMuted)),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppChipGroup<T>(
            options: options,
            labelOf: labelOf,
            isSelected: isSelected,
            onToggle: onToggle,
          ),
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
    final AppLanguage current = ref.watch(appLanguageProvider);

    return _ChoiceTile<AppLanguage>(
      label: context.l10n.settingsLanguage,
      hint: context.l10n.settingsLanguageHint,
      options: AppLanguage.values,
      labelOf: (AppLanguage l) => l.label,
      isSelected: (AppLanguage l) => l == current,
      onToggle: ref.read(settingsProvider.notifier).setLanguage,
    );
  }
}

/// The second way into the location flow, for a player who is not renaming
/// themselves.
///
/// The profile editor is where the locality is set in full — detected, typed
/// or cleared. This is only the refresh, because that is the thing somebody
/// comes back for: they moved, and the board they are on is the one they left.
///
/// Hidden entirely on a build that cannot detect, where it would be a button
/// that only ever apologises. Those players set their town in the editor.
class _LocationTile extends ConsumerWidget {
  const _LocationTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette colors = context.palette;
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
              color: saved == null ? colors.textMuted : colors.text,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.locationSettingsHint,
            style: text.bodySmall?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: context.l10n.locationSettingsRow,
            icon: Icons.my_location,
            expand: true,
            onPressed: () => unawaited(runLocationUpdate(context, ref)),
          ),
        ],
      ),
    );
  }
}
