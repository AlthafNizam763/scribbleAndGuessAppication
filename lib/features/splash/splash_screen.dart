import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/app_logger.dart';
import 'package:scribble_guess/core/widgets/app_button.dart';
import 'package:scribble_guess/core/widgets/brand_logo.dart';
import 'package:scribble_guess/data/api/auth_api.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/services/fcm_service.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The opening beat: the cat loses it, the wordmark lands, then straight on to
/// wherever the player belongs.
///
/// This screen owns one genuinely important job beyond looking nice — it is
/// where a stored session is resolved. Every screen after it assumes a player
/// id, because room membership, drawer identity and every server-side check
/// are written against one, so nothing is allowed past here without it.
///
/// It resolves a session; it does not invent one. A device with no stored
/// token goes to the sign-in gate. A player signed in but with no profile has
/// never played before and is sent to make one; everyone else goes to the hub.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// How long the animation holds before routing on.
  ///
  /// Long enough for the cat to hop, rock and settle; short enough that nobody
  /// waiting to play resents it. The session check runs underneath and usually
  /// finishes first, so on a warm start this is the only thing anyone waits for.
  static const Duration dwell = Duration(milliseconds: 1400);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _failed = false;
  late final AnimationController _laugh;

  @override
  void initState() {
    super.initState();
    _laugh = AnimationController(vsync: this, duration: SplashScreen.dwell);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _laugh.dispose();
    super.dispose();
  }

  /// Waits for both the animation and the session check, then routes.
  ///
  /// The two run concurrently rather than in sequence: on a warm start the
  /// session is already there, and the player should not pay for a round trip
  /// that already happened.
  ///
  /// This *resumes* a session; it no longer creates one. A device with no
  /// stored token goes to the sign-in gate, where creating a guest account is
  /// something the player taps rather than something that happens to them.
  Future<void> _bootstrap() async {
    final bool reducedMotion = ref.read(reducedMotionProvider);

    // Started before the session check and awaited after it, so the two
    // overlap. Under reduced motion there is nothing to watch, so there is
    // nothing to wait for either — the logo is simply there, and the app moves
    // on as soon as the session resolves.
    final Future<void> dwell = reducedMotion
        ? Future<void>.value()
        : _laugh.forward(from: 0).orCancel.catchError((Object _) {});

    late final ({AuthSession? session, bool offline}) outcome;
    try {
      outcome = await ref.read(authServiceProvider).resumeSession();
      await dwell;
    } on Object catch (error, stack) {
      // Logged, not just shown: the screen can only offer one generic "no
      // connection" line, but the cause is as often a misaimed emulator host
      // as it is a real dead network.
      AppLogger.e('Splash bootstrap failed', error, stack);
      if (mounted) setState(() => _failed = true);
      return;
    }

    if (!mounted) return;

    // Could not reach the server to check a token we do have. Offer a retry
    // rather than a login form: the stored session may well be fine, and
    // sending them to sign in would ask for a round trip that just failed.
    if (outcome.offline) {
      setState(() => _failed = true);
      return;
    }

    // No resumable session. The gate decides what happens next.
    if (outcome.session == null) {
      context.goNamed(AppRoutes.login);
      return;
    }

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
    context.goNamed(hasProfile ? AppRoutes.home : AppRoutes.editProfile);
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
    final AppPalette colors = context.palette;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _LaughingLogo(
                animation: _laugh,
                caption: _failed
                    ? context.l10n.errorNetwork
                    : context.l10n.appTagline,
                captionColor: _failed ? colors.danger : colors.textMuted,
              ),
              if (_failed) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: context.l10n.retry,
                  icon: Icons.refresh_rounded,
                  variant: AppButtonVariant.primary,
                  expand: false,
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

/// The brand lockup, animated once on open.
///
/// Three beats, in one pass of a single controller:
///
/// 1. **The hop.** The cat is thrown up and drops back, landing hard.
/// 2. **The laugh.** It rocks about the base of its haunches, fast at first
///    and settling — a decaying wobble, not a metronome.
/// 3. **The wordmark.** Lands a beat after the cat, so the eye reads the cat
///    first and the name second, which is the order the brand is built in.
///
/// Deliberately one controller and no staggered widgets: the whole thing is a
/// function of a single `t` from 0 to 1, which makes it trivial to check and
/// impossible to desynchronise.
class _LaughingLogo extends StatelessWidget {
  const _LaughingLogo({
    required this.animation,
    required this.caption,
    required this.captionColor,
  });

  final Animation<double> animation;
  final String caption;
  final Color captionColor;

  /// Where in the pass the wordmark starts arriving.
  static const double _nameAt = 0.42;

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, _) {
        final double t = animation.value;

        // Under reduced motion the controller never runs, so `t` sits at 0 and
        // every term below has to resolve to "finished, at rest" rather than
        // "frame one" — otherwise the logo would be stuck mid-hop, invisible.
        final bool still = !animation.isAnimating && t == 0;

        // One arc up and down over the first third of the pass.
        final double hop = still ? 0 : math.sin(math.pi * (t / 0.33).clamp(0.0, 1.0));

        // A wobble that decays to nothing: full swing on landing, still by the
        // end. `e^-5t` is steep enough to settle inside the dwell.
        final double settle = ((t - 0.3) / 0.7).clamp(0.0, 1.0);
        final double tilt = still
            ? 0
            : Brand.laughTilt *
                  math.sin(settle * math.pi * 5) *
                  math.exp(-5 * settle);

        final double name = still
            ? 1
            : Curves.easeOutBack.transform(
                ((t - _nameAt) / (1 - _nameAt)).clamp(0.0, 1.0),
              );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BrandMark(size: 128, tilt: tilt, hop: hop),
            const SizedBox(height: AppSpacing.md),
            // Scaled rather than faded: the wordmark is chunky outlined type,
            // and a half-opacity outline reads as a rendering fault.
            Transform.scale(
              scale: 0.6 + 0.4 * name.clamp(0.0, 1.0),
              child: Opacity(
                opacity: name.clamp(0.0, 1.0),
                child: const BrandWordmark(height: 52),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Opacity(
              opacity: still ? 1 : ((t - 0.7) / 0.3).clamp(0.0, 1.0),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: captionColor),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // A quiet progress hint, so a slow session check does not look
            // like a frozen screen once the animation has finished.
            SizedBox(
              height: 2,
              width: 120,
              child: Opacity(
                opacity: still ? 0 : (t >= 1 ? 1 : 0),
                child: LinearProgressIndicator(
                  backgroundColor: colors.surfaceActive,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
