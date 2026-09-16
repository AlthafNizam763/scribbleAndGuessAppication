import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/widgets/sketch_card.dart';
import 'package:scribble_guess/features/game/widgets/drawing_toolbar.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The full tool tray, and the custom colour picker.
///
/// Both are sheets rather than bar controls because the toolbar has to leave
/// room for the canvas on a phone — see the note on [DrawingToolbar].
///
/// Neither of these decides anything the server cares about: the tool, the
/// colour and the width are local preferences that shape the strokes this
/// device produces. Whether those strokes are accepted is settled by
/// `drawingService.assertCanDraw`, which this UI cannot influence.
///
/// ## Why both sheets scroll
///
/// A modal bottom sheet opened *without* `isScrollControlled` is laid out
/// against a hard ceiling of nine sixteenths of the screen, and a `Column`
/// inside it is simply clipped at that line with no way to reach what is
/// below. That is what hid the brush size on a 6.5" phone: the three tool
/// groups wrap to five rows of chips on a narrow screen and eat the budget
/// before the slider is reached, and at a large system font scale they eat it
/// sooner still.
///
/// So the tray is scroll-controlled and its body is a [SingleChildScrollView]
/// whose bottom padding carries both the keyboard inset and the gesture bar.
/// Content shorter than the screen still sizes the sheet to itself — the
/// column is `MainAxisSize.min` — and content taller than it scrolls rather
/// than disappearing.

/// The tools the tray offers, grouped as a drawer would reach for them.
const List<(String, List<DrawTool>)> _toolGroups = <(String, List<DrawTool>)>[
  ('Draw', <DrawTool>[
    DrawTool.pen,
    DrawTool.pencil,
    DrawTool.marker,
    DrawTool.brush,
  ]),
  ('Shapes', <DrawTool>[
    DrawTool.line,
    DrawTool.rectangle,
    DrawTool.circle,
  ]),
  ('Other', <DrawTool>[
    DrawTool.eraser,
    DrawTool.fill,
  ]),
];

/// How much of the screen the tray may cover at most.
///
/// Short of the whole height on purpose: the strip of canvas left visible above
/// it is what tells a drawer the sheet is a sheet and can be dismissed. There
/// is deliberately no matching *minimum* — a minimum would pad a short tray
/// with transparent dead space that swallows taps meant for the barrier.
const double _maxSheetHeightFraction = 0.92;

/// The board actions the tray offers alongside the tools.
///
/// Passed in rather than read from a provider because the two screens that
/// open the tray undo different things: the game screen's undo goes through
/// `drawingRepository` and out to the server, practice's rewrites a local
/// board that no one else can see. The tray shows the same three buttons for
/// both and owns neither implementation.
@immutable
class DrawingToolActions {
  /// Creates the action set.
  const DrawingToolActions({
    this.onUndo,
    this.onRedo,
    this.onClear,
  });

  /// Undoes the last stroke, or null when there is nothing to undo.
  final VoidCallback? onUndo;

  /// Redoes the last undone stroke, or null when there is none.
  final VoidCallback? onRedo;

  /// Clears the canvas, or null when it is already empty.
  final VoidCallback? onClear;

  /// Whether any of the three is worth drawing a row for.
  bool get isEmpty => onUndo == null && onRedo == null && onClear == null;
}

/// Opens the tray. Returns once it is dismissed.
///
/// [actions] adds the undo/redo/clear row; omitting it hides that section
/// rather than drawing three dead buttons.
Future<void> showToolTray(
  BuildContext context, {
  DrawingToolActions actions = const DrawingToolActions(),
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // The fix. Without this the sheet is capped at 9/16 of the screen and the
    // bottom of the tray is clipped away with nothing to scroll.
    isScrollControlled: true,
    // Keeps the sheet clear of the status bar and of a landscape display
    // cutout. Bottom is deliberately left to the padding below, so the sheet
    // itself can sit flush with the bottom edge of the screen.
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * _maxSheetHeightFraction,
    ),
    builder: (BuildContext context) => _ToolTraySheet(actions: actions),
  );
}

class _ToolTraySheet extends ConsumerWidget {
  const _ToolTraySheet({required this.actions});

  final DrawingToolActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final DrawToolState state = ref.watch(drawToolProvider);
    final DrawToolNotifier notifier = ref.read(drawToolProvider.notifier);
    final MediaQueryData media = MediaQuery.of(context);

    return SafeArea(
      // The route already keeps the sheet off the status bar; this is here for
      // the sides, and bottom is excluded so the scroll padding below owns it.
      // Adding `padding.bottom` twice would leave a visible gap under the
      // last button on a phone with a gesture bar.
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          // The keyboard, then the navigation bar, then a thumb's worth of
          // room. `padding.bottom` collapses to zero while the keyboard is up
          // — the gesture bar is behind it — so the two never double up.
          bottom: media.viewInsets.bottom + media.padding.bottom + AppSpacing.lg,
        ),
        child: SketchCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _DragHandle(),

              Text(
                context.l10n.gameToolsTitle,
                style: text.titleMedium?.copyWith(color: colors.ink),
              ),
              const SizedBox(height: AppSpacing.md),

              for (final (String title, List<DrawTool> tools) in _toolGroups) ...<Widget>[
                Text(
                  title.toUpperCase(),
                  style: text.labelSmall?.copyWith(color: colors.inkSoft),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final DrawTool tool in tools)
                      _ToolChip(
                        tool: tool,
                        selected: state.tool == tool,
                        // Stays open. Picking a nib and then a size is one
                        // errand, and closing after the first half of it is
                        // what made the size controls hard to reach at all.
                        onTap: () => notifier.selectTool(tool),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // The fill is the one tool whose name promises more than it
              // does, so the tray says plainly what it will do rather than
              // letting a drawer discover it by tapping.
              if (state.tool == DrawTool.fill) ...<Widget>[
                Text(
                  context.l10n.gameFillHint,
                  style: text.bodySmall?.copyWith(color: colors.inkSoft),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              if (state.tool.usesWidth) ...<Widget>[
                Text(
                  '${context.l10n.gameBrushSize.toUpperCase()} · '
                  '${state.width.toInt()}',
                  style: text.labelSmall?.copyWith(color: colors.inkSoft),
                ),
                Slider(
                  value: state.width.clamp(
                    DrawToolState.minWidth,
                    DrawToolState.maxWidth,
                  ),
                  min: DrawToolState.minWidth,
                  max: DrawToolState.maxWidth,
                  onChanged: notifier.selectWidth,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // The palette. On the game screen it repeats the swatch strip on
              // the toolbar; in practice it is the *only* way to change ink,
              // because that screen has no colour row of its own.
              if (state.tool.usesColor) ...<Widget>[
                Text(
                  context.l10n.gameColors.toUpperCase(),
                  style: text.labelSmall?.copyWith(color: colors.inkSoft),
                ),
                const SizedBox(height: AppSpacing.sm),
                _PaletteWrap(
                  selected: state.colorValue,
                  onPicked: notifier.selectColor,
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              if (!actions.isEmpty) ...<Widget>[
                _ActionRow(actions: actions),
                const SizedBox(height: AppSpacing.sm),
              ],

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.done),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The grab bar at the top of a sheet.
///
/// Drawn rather than taken from `showDragHandle`, which paints a Material
/// handle in the theme's outline colour above the sheet's own background — on
/// a transparent sheet that lands on the canvas rather than on the card.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Container(
          height: 4,
          width: 44,
          decoration: BoxDecoration(
            color: colors.inkFaint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// The ink swatches, plus the way into the custom picker.
class _PaletteWrap extends StatelessWidget {
  const _PaletteWrap({required this.selected, required this.onPicked});

  final int selected;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (int index = 0; index < DrawToolState.penPalette.length; index += 1)
          Semantics(
            button: true,
            selected: DrawToolState.penPalette[index] == selected,
            label: '${context.l10n.a11yColorPicker} ${index + 1}',
            child: GestureDetector(
              onTap: () => onPicked(DrawToolState.penPalette[index]),
              child: Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: Color(DrawToolState.penPalette[index]),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.ink,
                    width: DrawToolState.penPalette[index] == selected
                        ? AppSpacing.border + 2
                        : AppSpacing.border,
                  ),
                ),
              ),
            ),
          ),
        Semantics(
          button: true,
          label: context.l10n.gameCustomColor,
          child: GestureDetector(
            onTap: () async {
              final int? picked = await showCustomColorPicker(context, selected);
              if (picked != null) onPicked(picked);
            },
            child: Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.ink, width: AppSpacing.border),
                gradient: const SweepGradient(
                  colors: <Color>[
                    Color(0xFFD64545),
                    Color(0xFFE3B92F),
                    Color(0xFF3F9A50),
                    Color(0xFF3B7DD8),
                    Color(0xFF7C5BD9),
                    Color(0xFFD64545),
                  ],
                ),
              ),
              child: Icon(Icons.add, size: 18, color: colors.canvasWhite),
            ),
          ),
        ),
      ],
    );
  }
}

/// Undo, redo and clear, forwarded to whichever screen opened the tray.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.actions});

  final DrawingToolActions actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        _ActionChip(
          icon: Icons.undo,
          label: context.l10n.gameUndo,
          onTap: actions.onUndo,
        ),
        _ActionChip(
          icon: Icons.redo,
          label: context.l10n.gameRedo,
          onTap: actions.onRedo,
        ),
        _ActionChip(
          icon: Icons.delete_outline,
          label: context.l10n.gameClear,
          danger: true,
          onTap: actions.onClear,
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final bool enabled = onTap != null;

    final Color tint = !enabled
        ? colors.inkFaint
        : danger
            ? colors.danger
            : colors.ink;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.paper,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: colors.inkFaint, width: AppSpacing.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: text.labelSmall?.copyWith(color: tint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tool in the tray.
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final DrawTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: tool.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          // A floor rather than a fixed width: at a 1.4x system font scale
          // "Rectangle" no longer fits in 84 logical pixels, and a chip that
          // grows to hold its label is better than one that clips it.
          constraints: const BoxConstraints(minWidth: 84),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.paperShade : colors.paper,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: selected ? colors.ink : colors.inkFaint,
              width: selected ? AppSpacing.border + 1 : AppSpacing.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(DrawingToolbar.iconFor(tool), size: 22, color: colors.ink),
              const SizedBox(height: AppSpacing.xs),
              Text(
                tool.label,
                textAlign: TextAlign.center,
                style: text.labelSmall?.copyWith(
                  color: colors.ink,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the custom colour picker, returning the ARGB value chosen or null.
///
/// ## Why this is hand-rolled rather than a package
///
/// The app has no colour-picker dependency and this needs three sliders. A
/// package would bring a Material-styled dialog that would be the only surface
/// in the app not drawn in the sketchbook language, for a screen a drawer
/// opens for two seconds.
Future<int?> showCustomColorPicker(BuildContext context, int initial) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * _maxSheetHeightFraction,
    ),
    builder: (BuildContext context) => _CustomColorSheet(initial: initial),
  );
}

class _CustomColorSheet extends StatefulWidget {
  const _CustomColorSheet({required this.initial});

  final int initial;

  @override
  State<_CustomColorSheet> createState() => _CustomColorSheetState();
}

class _CustomColorSheetState extends State<_CustomColorSheet> {
  late double _hue;
  late double _saturation;
  late double _lightness;

  @override
  void initState() {
    super.initState();
    final HSLColor hsl = HSLColor.fromColor(Color(widget.initial));
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  /// HSL rather than RGB because the three sliders then mean something a
  /// person can aim with: "same colour but lighter" is one slider here and
  /// three co-ordinated ones in RGB.
  Color get _color =>
      HSLColor.fromAHSL(1, _hue, _saturation, _lightness).toColor();

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final MediaQueryData media = MediaQuery.of(context);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: media.viewInsets.bottom + media.padding.bottom + AppSpacing.lg,
        ),
        child: SketchCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _DragHandle(),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.l10n.gameCustomColor,
                      style: text.titleMedium?.copyWith(color: colors.ink),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    height: 32,
                    width: 32,
                    decoration: BoxDecoration(
                      color: _color,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: colors.ink, width: AppSpacing.border),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _LabelledSlider(
                label: 'Hue',
                value: _hue,
                max: 360,
                onChanged: (double value) => setState(() => _hue = value),
              ),
              _LabelledSlider(
                label: 'Saturation',
                value: _saturation,
                max: 1,
                onChanged: (double value) =>
                    setState(() => _saturation = value),
              ),
              _LabelledSlider(
                label: 'Lightness',
                value: _lightness,
                max: 1,
                onChanged: (double value) => setState(() => _lightness = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_color.toARGB32()),
                    child: Text(context.l10n.done),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabelledSlider extends StatelessWidget {
  const _LabelledSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: text.labelSmall?.copyWith(color: colors.inkSoft),
          ),
        ),
        Expanded(
          child: Slider(value: value, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}
