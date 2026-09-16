import 'package:flutter/widgets.dart';

/// Carries the app's press feedback down to the widgets that need it.
///
/// ## Why this exists rather than a `ref.read` in the button
///
/// `core/` is the app's base layer and imports nothing from `providers/`;
/// that is what lets the sketch UI kit be dropped into a test, or a widget
/// catalogue, with no Riverpod scope around it. But a button is exactly where a
/// click and a bump belong, and the thing that plays them is a service that
/// lives in a provider.
///
/// So the kit declares the hole and the app fills it. `core/` knows only that
/// *something* may want to be told about a press; `ScribbleGuessApp` is what
/// connects that to `SoundService`. Nothing is installed in a test, and
/// [press] then quietly does nothing — which is the right default for feedback
/// that is decoration in the first place.
class TapFeedback extends InheritedWidget {
  /// Installs [onPress] for everything under [child].
  const TapFeedback({
    required this.onPress,
    required super.child,
    super.key,
  });

  /// Called once per press. Expected to return immediately.
  final VoidCallback onPress;

  /// Fires the feedback installed above [context], if any.
  ///
  /// Reads without subscribing: this is called from inside a tap handler, where
  /// establishing a dependency would rebuild the button every time the callback
  /// identity changed and buy nothing — the handler looks the value up afresh
  /// on the next press regardless.
  static void press(BuildContext context) {
    context.getInheritedWidgetOfExactType<TapFeedback>()?.onPress();
  }

  @override
  bool updateShouldNotify(TapFeedback oldWidget) =>
      onPress != oldWidget.onPress;
}
