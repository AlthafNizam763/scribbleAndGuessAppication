// Renders every piece of STUPID GAMES branding from the geometry in
// `lib/theme/brand.dart`.
//
//   flutter test tool/generate_brand_assets.dart
//
// This is a build tool wearing a test's clothes. It is written as a test
// because `flutter test` is the one place a Flutter project can get at a real
// Skia canvas and `dart:io` at the same time, which is exactly what turning a
// CustomPainter into launcher bitmaps needs. It is deliberately NOT named
// `*_test.dart`, so a plain `flutter test` run never fires it and no ordinary
// build rewrites checked-in art.
//
// Everything below composes the same [BrandMarkPainter] the app draws with, so
// the launcher icon on a phone and the logo on the splash are the same artwork,
// not a bitmap someone exported once and forgot to update.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble_guess/core/widgets/brand_logo.dart';
import 'package:scribble_guess/theme/theme.dart';

/// Draws one square icon of edge [size] into [canvas].
typedef Composition = void Function(Canvas canvas, double size);

/// Corner radius of a plated icon, as a fraction of its edge.
///
/// Apple's superellipse is close to 22.37% of the width; matching it means the
/// macOS and web plates sit comfortably beside native icons.
const double _plateRadius = 0.2237;

/// Android's adaptive icon canvas is 108dp; the launcher shows 48dp of it.
const double _adaptiveDp = 108;
const double _launcherDp = 48;
const double _splashDp = 96;

/// The five Android density buckets, and what one dp is worth in each.
const Map<String, double> _densities = <String, double>{
  'mdpi': 1,
  'hdpi': 1.5,
  'xhdpi': 2,
  'xxhdpi': 3,
  'xxxhdpi': 4,
};

int _written = 0;

// ---------------------------------------------------------------- rendering

Future<Uint8List> _render(int size, Composition draw) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  draw(canvas, size.toDouble());
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(size, size);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _write(String path, int size, Composition draw) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(await _render(size, draw));
  _written++;
}

// ------------------------------------------------------- opaque PNG encoder

/// Renders [draw] and encodes it as a PNG with no alpha channel at all.
///
/// App Store validation rejects an app icon that carries an alpha channel,
/// even one that is opaque everywhere, and Flutter's own `toByteData` only
/// ever emits RGBA. So the iOS set is re-encoded here as PNG colour type 2
/// (truecolour, three bytes per pixel) from the raw pixels.
Future<Uint8List> _renderOpaque(int size, Composition draw) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  draw(canvas, size.toDouble());
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(size, size);
  final ByteData? raw = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  image.dispose();
  picture.dispose();

  final Uint8List rgba = raw!.buffer.asUint8List();

  // Scanlines, each prefixed with filter type 0 (none), alpha dropped.
  final Uint8List rows = Uint8List(size * (1 + size * 3));
  int out = 0;
  for (int y = 0; y < size; y++) {
    rows[out++] = 0;
    int input = y * size * 4;
    for (int x = 0; x < size; x++) {
      rows[out++] = rgba[input];
      rows[out++] = rgba[input + 1];
      rows[out++] = rgba[input + 2];
      input += 4;
    }
  }

  final BytesBuilder png = BytesBuilder()
    ..add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ByteData header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type 2: truecolour, no alpha
    ..setUint8(10, 0) // deflate
    ..setUint8(11, 0) // adaptive filtering
    ..setUint8(12, 0); // no interlacing
  png.add(_chunk('IHDR', header.buffer.asUint8List()));
  png.add(
    _chunk(
      'IDAT',
      Uint8List.fromList(ZLibCodec(level: 9).encode(rows)),
    ),
  );
  png.add(_chunk('IEND', Uint8List(0)));

  return png.takeBytes();
}

/// One PNG chunk: length, type, payload, CRC over type and payload.
Uint8List _chunk(String type, Uint8List data) {
  final Uint8List tag = Uint8List.fromList(type.codeUnits);
  final BytesBuilder body = BytesBuilder()
    ..add(tag)
    ..add(data);
  final Uint8List payload = body.takeBytes();

  final BytesBuilder out = BytesBuilder();
  final ByteData length = ByteData(4)..setUint32(0, data.length);
  out.add(length.buffer.asUint8List());
  out.add(payload);
  final ByteData crc = ByteData(4)..setUint32(0, _crc32(payload));
  out.add(crc.buffer.asUint8List());
  return out.takeBytes();
}

final List<int> _crcTable = List<int>.generate(256, (int n) {
  int c = n;
  for (int k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  int c = 0xFFFFFFFF;
  for (final int byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Future<void> _writeOpaque(String path, int size, Composition draw) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(await _renderOpaque(size, draw));
  _written++;
}

// ------------------------------------------------------------- compositions

/// Lays the mark into the centre of a [size] box at [scale] of its edge.
void _mark(
  Canvas canvas,
  double size, {
  required double scale,
  BrandInk ink = BrandInk.full,
}) {
  final double edge = size * scale;
  final double inset = (size - edge) / 2;
  canvas.save();
  canvas.translate(inset, inset);
  BrandMarkPainter(ink: ink).paint(canvas, Size(edge, edge));
  canvas.restore();
}

/// Plate to the edges. For iOS and Android maskable art, which must be opaque
/// because the platform crops them to a shape of its own choosing.
void _square(Canvas canvas, double size, {double scale = Brand.iconScale}) {
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size, size),
    Paint()..color = Brand.iconPlate,
  );
  _mark(canvas, size, scale: scale);
}

/// A rounded plate on transparency. For the places that draw an icon exactly
/// as given — legacy Android launchers, macOS, the web, Windows.
void _rounded(Canvas canvas, double size) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size, size),
      Radius.circular(size * _plateRadius),
    ),
    Paint()
      ..color = Brand.iconPlate
      ..isAntiAlias = true,
  );
  _mark(canvas, size, scale: Brand.iconScale);
}

/// The same plate, circular, for launchers that ask for a round icon.
void _circle(Canvas canvas, double size) {
  canvas.drawCircle(
    Offset(size / 2, size / 2),
    size / 2,
    Paint()
      ..color = Brand.iconPlate
      ..isAntiAlias = true,
  );
  _mark(canvas, size, scale: Brand.iconScale * 0.92);
}

/// A plate inset from the edges, the way macOS icons leave room for their
/// shadow rather than filling the tile.
void _macPlate(Canvas canvas, double size) {
  const double margin = 0.08;
  final double edge = size * (1 - margin * 2);
  canvas.save();
  canvas.translate(size * margin, size * margin);
  _rounded(canvas, edge);
  canvas.restore();
}

/// The adaptive icon's foreground layer: mark only, on transparency, small
/// enough to survive any mask the launcher applies.
void _adaptiveForeground(Canvas canvas, double size) =>
    _mark(canvas, size, scale: Brand.maskableScale);

/// The Android 13 themed-icon layer.
///
/// Only alpha is read — the system supplies the colour — so every part of the
/// cat goes down in one flat black. That flattens the coat and the face into
/// a single blob, which is exactly what the platform wants: a stencil.
void _monochrome(Canvas canvas, double size) => _mark(
  canvas,
  size,
  scale: Brand.maskableScale,
  ink: BrandInk.flat(const Color(0xFF000000)),
);

/// Splash art: the bare mark, no plate, inked for one brightness.
Composition _splashMark(BrandInk ink) =>
    (Canvas canvas, double size) => _mark(canvas, size, scale: 1, ink: ink);

/// The mark as it is drawn on the dark theme's desk.
///
/// The coat keeps its orange — that is the brand — but the outline switches to
/// chalk, because a near-black line on a near-black ground draws the cat as a
/// hole rather than as a cat.
const BrandInk _night = BrandInk(
  fur: Brand.fur,
  outline: AppColors.darkText,
  light: AppColors.darkSurfaceActive,
  accent: Brand.accent,
);

// ------------------------------------------------------------------ the ICO

/// Packs [sizes] into a Windows .ico.
///
/// Each entry is stored as a PNG rather than a DIB, which every Windows since
/// Vista reads and which keeps the 256px entry from dominating the file.
Future<void> _writeIco(String path, List<int> sizes) async {
  final List<Uint8List> images = <Uint8List>[
    for (final int size in sizes) await _render(size, _rounded),
  ];

  const int headerBytes = 6;
  const int entryBytes = 16;
  int offset = headerBytes + entryBytes * images.length;

  final BytesBuilder out = BytesBuilder();
  final ByteData header = ByteData(headerBytes)
    ..setUint16(0, 0, Endian.little) // reserved
    ..setUint16(2, 1, Endian.little) // 1 = icon
    ..setUint16(4, images.length, Endian.little);
  out.add(header.buffer.asUint8List());

  for (int i = 0; i < images.length; i++) {
    // 256 is stored as 0: the field is a single byte.
    final int dimension = sizes[i] >= 256 ? 0 : sizes[i];
    final ByteData entry = ByteData(entryBytes)
      ..setUint8(0, dimension)
      ..setUint8(1, dimension)
      ..setUint8(2, 0) // palette size: none
      ..setUint8(3, 0) // reserved
      ..setUint16(4, 1, Endian.little) // colour planes
      ..setUint16(6, 32, Endian.little) // bits per pixel
      ..setUint32(8, images[i].length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    out.add(entry.buffer.asUint8List());
    offset += images[i].length;
  }

  for (final Uint8List image in images) {
    out.add(image);
  }

  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(out.takeBytes());
  _written++;
}

// -------------------------------------------------------------------- main

void main() {
  test(
    'generate brand assets',
    () async {
      const String android = 'android/app/src/main/res';
      const String ios =
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-';
      const String macos = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

      // ---- Android launcher, per density -------------------------------
      for (final MapEntry<String, double> bucket in _densities.entries) {
        final String dir = '$android/mipmap-${bucket.key}';
        final int launcher = (_launcherDp * bucket.value).round();
        final int adaptive = (_adaptiveDp * bucket.value).round();
        final int splash = (_splashDp * bucket.value).round();

        await _write('$dir/ic_launcher.png', launcher, _rounded);
        await _write('$dir/ic_launcher_round.png', launcher, _circle);
        await _write(
          '$dir/ic_launcher_foreground.png',
          adaptive,
          _adaptiveForeground,
        );
        await _write('$dir/ic_launcher_monochrome.png', adaptive, _monochrome);

        // Splash art, light and dark, resolved by the -night qualifier.
        await _write(
          '$android/drawable-${bucket.key}/splash_logo.png',
          splash,
          _splashMark(BrandInk.full),
        );
        await _write(
          '$android/drawable-night-${bucket.key}/splash_logo.png',
          splash,
          _splashMark(_night),
        );
      }

      // ---- iOS ----------------------------------------------------------
      // Opaque and square: iOS rejects alpha in an app icon and rounds the
      // corners itself.
      const Map<String, int> iosIcons = <String, int>{
        '20x20@1x': 20,
        '20x20@2x': 40,
        '20x20@3x': 60,
        '29x29@1x': 29,
        '29x29@2x': 58,
        '29x29@3x': 87,
        '40x40@1x': 40,
        '40x40@2x': 80,
        '40x40@3x': 120,
        '60x60@2x': 120,
        '60x60@3x': 180,
        '76x76@1x': 76,
        '76x76@2x': 152,
        '83.5x83.5@2x': 167,
        '1024x1024@1x': 1024,
      };
      for (final MapEntry<String, int> icon in iosIcons.entries) {
        await _writeOpaque('$ios${icon.key}.png', icon.value, _square);
      }

      // ---- iOS launch screen --------------------------------------------
      // The storyboard centres this at its natural point size, so 1x is the
      // size in points. Light and dark are separate files, picked by the
      // appearance tags in the image set.
      const String launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
      const Map<String, int> launchScales = <String, int>{
        '': 120,
        '@2x': 240,
        '@3x': 360,
      };
      for (final MapEntry<String, int> scale in launchScales.entries) {
        await _write(
          '$launch/LaunchImage${scale.key}.png',
          scale.value,
          _splashMark(BrandInk.full),
        );
        await _write(
          '$launch/LaunchImage-dark${scale.key}.png',
          scale.value,
          _splashMark(_night),
        );
      }

      // ---- macOS --------------------------------------------------------
      for (final int size in <int>[16, 32, 64, 128, 256, 512, 1024]) {
        await _write('$macos/app_icon_$size.png', size, _macPlate);
      }

      // ---- Web ----------------------------------------------------------
      await _write('web/favicon.png', 32, _rounded);
      await _write('web/icons/Icon-192.png', 192, _rounded);
      await _write('web/icons/Icon-512.png', 512, _rounded);
      // Maskable art is cropped by the installer, so it must bleed to the
      // edge and keep the mark well inside the safe zone.
      await _write(
        'web/icons/Icon-maskable-192.png',
        192,
        (Canvas c, double s) => _square(c, s, scale: Brand.maskableScale),
      );
      await _write(
        'web/icons/Icon-maskable-512.png',
        512,
        (Canvas c, double s) => _square(c, s, scale: Brand.maskableScale),
      );

      // ---- Windows ------------------------------------------------------
      await _writeIco('windows/runner/resources/app_icon.ico', <int>[
        16,
        24,
        32,
        48,
        64,
        128,
        256,
      ]);

      // ---- Masters, for store listings and press ------------------------
      await _write('brand/app_icon_1024.png', 1024, _square);
      await _write('brand/icon_rounded_1024.png', 1024, _rounded);
      await _write(
        'brand/mark_full_1024.png',
        1024,
        _splashMark(BrandInk.full),
      );
      await _write(
        'brand/mark_chalk_1024.png',
        1024,
        _splashMark(_night),
      );
      await _write('brand/mark_monochrome_1024.png', 1024, _monochrome);

      stdout.writeln('brand: wrote $_written files');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
