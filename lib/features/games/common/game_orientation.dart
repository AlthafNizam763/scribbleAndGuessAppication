import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Holds a game in landscape for as long as any part of it is on screen.
///
/// ## The bug this exists to stop
///
/// [SystemChrome.setPreferredOrientations] is global and has no memory. The
/// obvious implementation — lock in `initState`, unlock in `dispose` — is
/// correct for one screen and wrong the moment two of them overlap, which is
/// exactly what Space Mystery does: the lobby locks landscape, pushes the
/// match, and the match locks landscape too. When the match is popped its
/// `dispose` unlocks *the whole application*, and the lobby underneath — still
/// mounted, still very much a landscape screen — is free to rotate into a
/// portrait layout it was never drawn for.
///
/// The same thing happens on the way to the result screen, and again on a
/// rematch, because "how many screens want landscape" is a count and a boolean
/// cannot hold it.
///
/// So this is a **counter**. Every [OrientationLock] widget takes a claim on
/// mount and releases it on unmount, and the orientation is restored only when
/// the last claim goes — which is the only moment at which no part of the game
/// is on screen any more.
///
/// ## Why it restores to unrestricted rather than to portrait
///
/// The application never locked portrait in the first place. Pinning it on the
/// way out would leave a tablet unable to rotate after its first match, which
/// is a worse bug than the one being fixed.
abstract final class GameOrientation {
  /// How many screens currently want landscape.
  static int _claims = 0;

  /// Swapped in tests, which have no platform channel to talk to.
  @visibleForTesting
  static Future<void> Function(List<DeviceOrientation>) applied =
      SystemChrome.setPreferredOrientations;

  /// Whether anything currently holds the lock. For tests and for asserts.
  @visibleForTesting
  static bool get locked => _claims > 0;

  /// Drops every claim. Tests only — a leaked claim in one test would
  /// otherwise make the next one lie.
  @visibleForTesting
  static void resetForTest() => _claims = 0;

  static const List<DeviceOrientation> _landscape = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  /// Takes a claim, locking landscape if this is the first one.
  static void claim() {
    _claims += 1;
    if (_claims == 1) _apply(_landscape);
  }

  /// Releases a claim, unlocking only when it was the last.
  static void release() {
    if (_claims == 0) return;
    _claims -= 1;
    if (_claims == 0) _apply(DeviceOrientation.values);
  }

  /// Applies a preference without awaiting it.
  ///
  /// The future completes when the platform has acknowledged the change, which
  /// is of no interest to either caller — and awaiting it inside `dispose` is
  /// not allowed anyway.
  static void _apply(List<DeviceOrientation> orientations) {
    // A platform that refuses the request — a desktop embedding, a test
    // binding with no window — must not take a screen down with it.
    applied(orientations).catchError((Object _) {});
  }
}

/// Claims landscape for as long as this widget is in the tree.
///
/// Wrap it round anything that is part of a landscape game: the lobby, the
/// match, the result. Nesting is not only allowed but expected — see the
/// counter in [GameOrientation].
class OrientationLock extends StatefulWidget {
  const OrientationLock({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// Whether to actually hold the lock. False makes this a plain pass-through,
  /// which is what lets one shared screen serve both a landscape game and a
  /// portrait one without a conditional in the widget tree above it.
  final bool enabled;

  @override
  State<OrientationLock> createState() => _OrientationLockState();
}

class _OrientationLockState extends State<OrientationLock> {
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(OrientationLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A screen that changes its mind — the shared lobby moving between games —
    // must hand the claim back rather than hold it for the rest of the session.
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (widget.enabled == _held) return;
    _held = widget.enabled;
    if (_held) {
      GameOrientation.claim();
    } else {
      GameOrientation.release();
    }
  }

  @override
  void dispose() {
    if (_held) GameOrientation.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
