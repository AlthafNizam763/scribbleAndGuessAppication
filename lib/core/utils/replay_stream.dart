import 'dart:async';

/// Wraps a broadcast [source] so every new listener is handed the latest value
/// before the live ones.
///
/// ## The problem this solves
///
/// A plain `StreamController.broadcast()` delivers to whoever is listening at
/// the moment of the `add`, and to nobody else. That is the wrong shape for
/// state a screen needs when it opens, because the push that *causes* a screen
/// to open necessarily arrives before that screen exists: the round result is
/// sent with the phase change the results screen is pushed by, and the word
/// choices are sent as a turn opens, while the drawer may still be looking at
/// the previous scoreboard. Both are delivered into an empty room and lost.
///
/// ## Why not `async*`
///
/// The obvious fix —
///
/// ```dart
/// Stream<T> get values async* {
///   yield _latest;
///   yield* _controller.stream;
/// }
/// ```
///
/// — reintroduces the same bug in miniature. An `async*` body does not run
/// until the returned stream is listened to, and it suspends at the first
/// `yield`, so the subscription to `_controller` is only attached one or more
/// microtasks later. Anything added in that window is dropped.
///
/// [replaying] attaches in `onListen`, synchronously, so there is no window.
///
/// [latest] is read at subscription time and may return `null` to mean "there
/// is nothing to replay yet"; a value is passed through untouched otherwise.
/// The returned stream is single-subscription, which is what callers want —
/// each listener gets its own replay — and every listener is independent of
/// the others.
Stream<T> replaying<T>(
  StreamController<T> source,
  T? Function() latest,
) {
  // `Stream.multi` runs this body once per listener, synchronously, at the
  // moment that listener subscribes. That is the property the whole helper
  // rests on: the replay and the subscription to [source] happen in the same
  // turn of the event loop, so nothing can slip between them.
  return Stream<T>.multi((MultiStreamController<T> controller) {
    final T? value = latest();
    if (value != null) {
      controller.add(value);
    }

    if (source.isClosed) {
      // Nothing more will ever arrive, but the cached value above was still
      // worth handing over: a repository disposed between build and listen
      // should not leave a screen with no state at all.
      controller.close();
      return;
    }

    final StreamSubscription<T> subscription = source.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );

    controller.onCancel = subscription.cancel;
    controller.onPause = subscription.pause;
    controller.onResume = subscription.resume;
  });
}
