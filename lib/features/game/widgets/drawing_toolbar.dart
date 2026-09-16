import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/features/game/widgets/tool_tray_sheet.dart';
import 'package:scribble_guess/models/drawing_board.dart';
import 'package:scribble_guess/models/enums.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/theme/theme.dart';

/// The drawer's tools: colours, nib sizes, the tool tray, undo/redo and clear.
///
/// Only ever mounted for the player holding the pen, so it does not need to
/// reason about permission itself — the server decides that, and refuses
/// strokes from anybody else regardless of what any UI allows.
///
/// ## Why the extra tools live behind a tray
///
/// There are nine of them now, and a row of nine icons on a phone leaves no
/// room for the canvas that is the point of the screen. The two used most —
/// the current drawing tool and the eraser — stay on the bar; the rest are one
/// tap away in a sheet. The bar also shows which tool is active, so the tray
/// never has to be opened just to find out.
class DrawingToolbar extends ConsumerWidget {
  const DrawingToolbar({required this.onClear, super.key});

  final VoidCallback onClear;

  /// The icon each tool is drawn with, shared with the tray.
  static IconData iconFor(DrawTool tool) => switch (tool) {
        DrawTool.pen => Icons.edit_outlined,
        DrawTool.pencil => Icons.create_outlined,
        DrawTool.marker => Icons.brush_outlined,
        DrawTool.brush => Icons.gesture,
        DrawTool.eraser => Icons.auto_fix_normal,
        DrawTool.fill => Icons.format_color_fill,
        DrawTool.line => Icons.horizontal_rule,
        DrawTool.rectangle => Icons.crop_square,
        DrawTool.circle => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SketchColors colors = context.sketch;
    final DrawToolState tool = ref.watch(drawToolProvider);
    final DrawToolNotifier notifier = ref.read(drawToolProvider.notifier);
    final DrawingBoard board = ref.watch(boardProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: DrawToolState.penPalette.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (BuildContext context, int index) {
              // The last slot is the custom picker rather than a swatch.
              if (index == DrawToolState.penPalette.length) {
                return _CustomColorButton(
                  current: tool.colorValue,
                  onPicked: notifier.selectColor,
                );
              }

              final int value = DrawToolState.penPalette[index];
              final bool active = tool.colorApplies && tool.colorValue == value;

              return Semantics(
                button: true,
                selected: active,
                label: 'Colour ${index + 1}',
                child: GestureDetector(
                  onTap: () => notifier.selectColor(value),
                  child: Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.ink,
                        width: active
                            ? AppSpacing.border + 2
                            : AppSpacing.border,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            // Sizes are meaningless for a fill, which covers the canvas
            // whatever the nib is set to. Hidden rather than disabled: a row of
            // greyed-out dots invites a tap that will do nothing.
            if (tool.tool.usesWidth)
              for (final double width in DrawToolState.widths)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _NibButton(
                    width: width,
                    selected: tool.width == width,
                    onTap: () => notifier.selectWidth(width),
                  ),
                ),
            const Spacer(),
            _ToolButton(
              icon: iconFor(tool.tool),
              tooltip: context.l10n.gameTools,
              selected: !tool.isErasing,
              onPressed: () => showToolTray(context),
            ),
            _ToolButton(
              icon: iconFor(DrawTool.eraser),
              tooltip: context.l10n.gameEraser,
              selected: tool.isErasing,
              onPressed: () => notifier.selectTool(DrawTool.eraser),
            ),
            _ToolButton(
              icon: Icons.undo,
              tooltip: context.l10n.gameUndo,
              onPressed: board.canUndo
                  ? () => ref.read(drawingRepositoryProvider).undo()
                  : null,
            ),
            _ToolButton(
              icon: Icons.redo,
              tooltip: context.l10n.gameRedo,
              onPressed: board.canRedo
                  ? () => ref.read(drawingRepositoryProvider).redo()
                  : null,
            ),
            _ToolButton(
              icon: Icons.delete_outline,
              tooltip: context.l10n.gameClear,
              danger: true,
              onPressed: board.canUndo ? onClear : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// The swatch that opens the custom colour picker.
///
/// Drawn as a ring of hues so it reads as "more colours" rather than as one
/// more swatch, which is what a single gradient chip would look like.
class _CustomColorButton extends StatelessWidget {
  const _CustomColorButton({required this.current, required this.onPicked});

  final int current;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Semantics(
      button: true,
      label: context.l10n.gameCustomColor,
      child: GestureDetector(
        onTap: () async {
          final int? picked = await showCustomColorPicker(context, current);
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
    );
  }
}

/// A nib size, drawn as a dot at its actual relative weight.
class _NibButton extends StatelessWidget {
  const _NibButton({
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Brush size ${width.toInt()}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          width: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? colors.ink : colors.inkFaint,
              width: selected ? AppSpacing.border : 1,
            ),
          ),
          child: Container(
            height: width.clamp(2.0, 20.0),
            width: width.clamp(2.0, 20.0),
            decoration: BoxDecoration(
              color: colors.ink,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final bool enabled = onPressed != null;

    final Color tint = !enabled
        ? colors.inkFaint
        : danger
            ? colors.danger
            : colors.ink;

    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      color: tint,
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: colors.ink.withValues(alpha: 0.12),
            )
          : null,
    );
  }
}

