import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/app/push_navigation.dart';
import 'package:scribble_guess/app/router.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/tap_feedback.dart';
import 'package:scribble_guess/features/rooms/room_invitation_dialog.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/services/sound_service.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The application widget.
class ScribbleGuessApp extends ConsumerWidget {
  const ScribbleGuessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final bool reducedMotion = ref.watch(reducedMotionProvider);

    // Above the router on purpose: the game sounds react to server state, and
    // several of them fire during exactly the phase changes that are also
    // swapping one screen for another. Installed here they cannot be missed
    // because the screen that would have played them was being disposed.
    ref.watch(gameSoundsProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      // The player's chosen interface language. Naming a locale here rather
      // than following the device means a phone set to a language the game
      // does not carry still lands somewhere deliberate, and a player can
      // pick Tamil on an English handset.
      locale: ref.watch(localeProvider),
      supportedLocales: AppLanguage.values.map((AppLanguage l) => l.locale),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        // Ours first: a delegate list is searched in order, and this is the
        // one that carries the app's own copy. The three Global delegates
        // behind it supply Material's strings and, through
        // GlobalWidgetsLocalizations, the text direction.
        AppTextDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        // Honour the player's reduced-motion preference app-wide, and stop the
        // system font scale from growing past the point where the game's
        // fixed-height chrome breaks (§59).
        final MediaQueryData media = MediaQuery.of(context);
        return TapFeedback(
          // Every press in the widget kit routes through here, so the click and
          // the bump are defined once instead of at several hundred call sites.
          onPress: () => ref.read(soundServiceProvider).play(SoundEffect.tap),
          // Above the router for the same reason the game sounds are: a room
          // invitation is addressed to the *player*, so it can land on any
          // screen, and a listener mounted per screen would either miss it
          // where somebody forgot or raise two dialogs where they did not.
          // Above the router for the same reason as the invitation listener
          // below it: a notification is addressed to the player rather than to
          // a screen, and a tap that launched the app from cold arrives before
          // any screen exists to receive it.
          child: PushNavigationListener(
            child: RoomInvitationListener(
              child: MediaQuery(
                data: media.copyWith(
                  disableAnimations: media.disableAnimations || reducedMotion,
                  textScaler: media.textScaler.clamp(
                    minScaleFactor: 0.9,
                    maxScaleFactor: 1.4,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shown when Firebase configuration is missing entirely.
///
/// Without a project the app cannot sign in, create a room or do anything else
/// worth doing, so rather than failing screen by screen it says so once, here,
/// with the exact command that fixes it. This is a developer-facing state: a
/// released build always has its configuration compiled in.
class FirebaseSetupRequiredApp extends StatelessWidget {
  const FirebaseSetupRequiredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Firebase is not configured',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Scribble & Guess needs a Firebase project before it can '
                    'sign in or host a room.\n\n'
                    'Run this from the project root:',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const SelectableText(
                    'dart pub global activate flutterfire_cli\n'
                    'flutterfire configure',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Or pass the FIREBASE_* values with --dart-define. '
                    'See README.md for the full setup, including running '
                    'entirely against the local emulator suite.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
