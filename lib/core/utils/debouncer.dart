import 'dart:async';

/// Runs the most recent action once the caller has been quiet for [duration].
///
/// Trailing-edge only: every [run] restarts the wait, so a burst of calls
/// results in exactly one invocation. Always [dispose] it with its owner.
class Debouncer {
  /// Creates a debouncer with the given quiet period.
  Debouncer({this.duration = const Duration(milliseconds: 300)});

  /// How long the caller must be quiet before the action fires.
  final Duration duration;

  Timer? _timer;
  void Function()? _pending;

  /// Whether an action is waiting to fire.
  bool get isPending => _timer?.isActive ?? false;

  /// Schedules [action], replacing any action still waiting.
  void run(void Function() action) {
    _timer?.cancel();
    _pending = action;
    _timer = Timer(duration, _fire);
  }

  /// Runs the pending action immediately, if there is one.
  void flush() {
    if (_timer?.isActive ?? false) {
      _timer?.cancel();
      _fire();
    }
  }

  /// Drops the pending action without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  /// Cancels everything. Safe to call more than once.
  void dispose() => cancel();

  void _fire() {
    _timer = null;
    final void Function()? action = _pending;
    _pending = null;
    action?.call();
  }
}

/// Runs an action at most once per [duration], on the leading edge, and
/// replays the last suppressed action when the window closes.
///
/// Used for high-frequency streams such as outgoing stroke batches, where the
/// first sample should go out immediately and the final one must not be lost.
class Throttler {
  /// Creates a throttler with the given minimum gap between invocations.
  Throttler({this.duration = const Duration(milliseconds: 60)});

  /// Minimum time between two invocations.
  final Duration duration;

  Timer? _timer;
  void Function()? _pending;
  DateTime? _lastRun;

  /// Whether a suppressed action is waiting for the window to close.
  bool get isPending => _pending != null;

  /// Runs [action] now if the window is open, otherwise queues it as the
  /// trailing invocation, replacing anything queued before.
  void run(void Function() action) {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastRun;
    if (last == null || now.difference(last) >= duration) {
      _lastRun = now;
      action();
      return;
    }
    _pending = action;
    _timer ??= Timer(duration - now.difference(last), _fire);
  }

  /// Runs the queued trailing action immediately, if there is one.
  void flush() {
    _timer?.cancel();
    _fire();
  }

  /// Drops the queued action and reopens the window.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _lastRun = null;
  }

  /// Cancels everything. Safe to call more than once.
  void dispose() => cancel();

  void _fire() {
    _timer = null;
    final void Function()? action = _pending;
    _pending = null;
    if (action != null) {
      _lastRun = DateTime.now();
      action();
    }
  }
}
