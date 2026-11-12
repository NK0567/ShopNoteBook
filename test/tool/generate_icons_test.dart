// Génère toutes les icônes de l'application à partir de BrandLogoPainter.
// flutter test test/tool/generate_icons_test.dart --dart-define=GENERATE_ICONS=true
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopnotbook/ui/brand_logo.dart';

const _enabled = bool.fromEnvironment('GENERATE_ICONS');

Future<Uint8List> _render(int size, {bool maskable = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();
  if (maskable) {
    // Icône « maskable » : fond plein (le système découpe), dessin dans la zone sûre.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s, s),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandLogoPainter.blueLight, BrandLogoPainter.blueDark],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );
    const BrandLogoPainter(background: false, contentScale: 0.78).paint(canvas, Size.square(s));
  } else {
    const BrandLogoPainter().paint(canvas, Size.square(s));
  }
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Fichier .ico Windows contenant des images PNG (accepté depuis Windows Vista).
Uint8List _ico(List<(int, Uint8List)> images) {
  final header = BytesBuilder();
  final body = BytesBuilder();
  var offset = 6 + 16 * images.length;
  final h = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  header.add(h.buffer.asUint8List());
  for (final (size, png) in images) {
    final e = ByteData(16)
      ..setUint8(0, size >= 256 ? 0 : size)
      ..setUint8(1, size >= 256 ? 0 : size)
      ..setUint8(2, 0)
      ..setUint8(3, 0)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, png.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    header.add(e.buffer.asUint8List());
    body.add(png);
    offset += png.length;
  }
  return (header..add(body.toBytes())).toBytes();
}

void main() {
  testWidgets('génère les icônes', (tester) async {
    await tester.runAsync(() async {
      Future<void> write(String path, Uint8List bytes) async {
        final f = File(path);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes);
      }

      // Android (icône classique, toutes densités).
      const android = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final e in android.entries) {
        await write('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png', await _render(e.value));
      }

      // Web / PWA.
      await write('web/favicon.png', await _render(32));
      await write('web/icons/Icon-192.png', await _render(192));
      await write('web/icons/Icon-512.png', await _render(512));
      await write('web/icons/Icon-maskable-192.png', await _render(192, maskable: true));
      await write('web/icons/Icon-maskable-512.png', await _render(512, maskable: true));

      // Windows.
      final sizes = [16, 24, 32, 48, 64, 128, 256];
      await write('windows/runner/resources/app_icon.ico', _ico([for (final s in sizes) (s, await _render(s))]));

      // Logo haute définition (documents, publicité, installateur).
      await write('assets/branding/logo-1024.png', await _render(1024));
    });
  }, skip: !_enabled);
}
