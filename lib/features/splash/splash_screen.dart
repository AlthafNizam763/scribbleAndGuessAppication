import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/widgets/brand_logo.dart';
import 'package:scribble_guess/core/widgets/sketch_button.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/services/fcm_service.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The opening beat: the wordmark, a session, then straight on to wherever the
/// player belongs.
///
/// This screen owns one genuinely important job beyond looking nice — it is
/// where the anonymous session is guaranteed to exist (§6). Every screen after
/// it assumes a uid, because room membership, drawer identity and every
/// Firestore rule are written against one, so nothing is allowed past here
/// without it.
///
/// A player with no profile has never played before and is sent to make one;
/// everyone else goes to the menu.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// How long the wordmark holds before routing on. Long enough to read, short
  /// enough not to feel like a loading screen.
  static const Duration dwell = Duration(milliseconds: 900);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  /// Waits for both the dwell and the session, then routes.
  ///
  /// The two run concurrently rather than in sequence: on a warm start the
  /// session is already there, and the player should not pay for a round trip
  /// that already happened.
  Future<void> _bootstrap() async {
    final Duration wait =
        ref.read(reducedMotionProvider) ? Duration.zero : SplashScreen.dwell;

    try {
      await Future.wait<void>(<Future<void>>[
        Future<void>.delayed(wait),
        ref.read(authServiceProvider).ensureSignedIn().then((_) {}),
      ]);
    } on Object catch (error, stack) {
      // Logged, not just shown: the screen can only offer one generic "no
      // connection" line, but the cause is as often a misaimed emulator host
      // or a disabled sign-in provider as it is a real dead network.
      AppLogger.e('Splash bootstrap failed', error, stack);
      if (mounted) setState(() => _failed = true);
      return;
    }

    if (!mounted) return;

    // Push, once there is a session to register the device against.
    //
    // Here rather than in `main` because the registration is keyed to a
    // *player*: a token posted before sign-in would have no owner, and the
    // check-in fan-out finds devices by user id. Here rather than on the
    // tournament screen because a player who registers for a tournament and
    // then closes the app is the exact case this exists for — by the time
    // they need it, the app is gone.
    //
    // Deliberately not awaited. Everything it does is best-effort, none of it
    // is on the path to the first screen, and a slow token fetch on a poor
    // connection must not hold the splash up.
    unawaited(_startPush());

    final bool hasProfile = ref.read(hasProfileProvider);
    context.goNamed(hasProfile ? AppRoutes.home : AppRoutes.profile);
  }

  /// Brings push up and registers this device. Never throws.
  Future<void> _startPush() async {
    final FcmService fcm = ref.read(fcmServiceProvider);

    final bool started = await fcm.start();
    if (!started) return;

    await fcm.registerToken();
  }

  Future<void> _retry() async {
    setState(() => _failed = false);
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Scaffold(
      backgroundColor: colors.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              BrandLogo(
                markSize: 96,
                caption: _failed
                    ? context.l10n.errorNetwork
                    : context.l10n.appTagline,
                captionColor: _failed ? colors.danger : colors.inkSoft,
              ),
              if (_failed) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                SketchButton(
                  label: context.l10n.retry,
                  onPressed: _retry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
