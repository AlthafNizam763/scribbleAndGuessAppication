// Renders the ten cats to one sheet, for looking at.
//
//   flutter test tool/preview_avatars.dart
//
// A build tool wearing a test's clothes, for the same reason
// `generate_brand_assets.dart` is: `flutter test` is the one place this project
// can get at a real Skia canvas and `dart:io` at once. Deliberately not named
// `*_test.dart`, so an ordinary `flutter test` run never fires it.
//
// Writes `brand/avatars_preview.png` and nothing else. The app ships no avatar
// images; this exists only so a person can see all ten at once.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/avatar_art.dart';
import 'package:scribble_guess/widgets/avatar_painter.dart';

void main() {
  test('render the avatar sheet', () async {
    const double tile = 150;
    const int columns = 5;
    final int rows = (AvatarCatalog.faces.length / columns).ceil();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    const double width = tile * columns;
    final double height = tile * rows;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = AppColors.surface,
    );

    for (int i = 0; i < AvatarCatalog.faces.length; i++) {
      final AvatarFace face = AvatarCatalog.faces[i];
      final double x = (i % columns) * tile;
      final double y = (i ~/ columns) * tile;

      // The disc the app draws behind a character, so the sheet shows what a
      // player actually sees rather than a floating head.
      canvas.drawCircle(
        Offset(x + tile / 2, y + tile / 2 - 6),
        tile * 0.42,
        Paint()..color = AppColors.avatarPalette[i % AppColors.avatarPalette.length]
            .withValues(alpha: 0.28),
      );

      canvas.save();
      canvas.translate(x + tile * 0.14, y + tile * 0.08);
      AvatarArtPainter(face: face).paint(canvas, const Size(tile * 0.72, tile * 0.72));
      canvas.restore();

      final TextPainter label = TextPainter(
        text: TextSpan(
          text: '${face.id}  ${face.name}',
          style: const TextStyle(color: AppColors.text, fontSize: 13, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + (tile - label.width) / 2, y + tile - 18));
    }

    final ui.Image image = await recorder.endRecording().toImage(
      width.round(),
      height.round(),
    );
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final File out = File('brand/avatars_preview.png');
    await out.parent.create(recursive: true);
    await out.writeAsBytes(png!.buffer.asUint8List());
    stdout.writeln('avatars: wrote ${out.path}');
  });
}
