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

/// Opens the tray. Returns once it is dismissed.
Future<void> showToolTray(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => const _ToolTraySheet(),
  );
}

class _ToolTraySheet extends ConsumerWidget {
  const _ToolTraySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final DrawToolState state = ref.watch(drawToolProvider);
    final DrawToolNotifier notifier = ref.read(drawToolProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SketchCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
                        onTap: () {
                          notifier.selectTool(tool);
                          Navigator.of(context).pop();
                        },
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
                  '${context.l10n.gameBrushSize} · ${state.width.toInt()}',
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
              ],
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
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SketchCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    context.l10n.gameCustomColor,
                    style: text.titleMedium?.copyWith(color: colors.ink),
                  ),
                  const Spacer(),
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
