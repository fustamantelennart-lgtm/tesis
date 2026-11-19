import 'dart:convert';
import 'dart:io';

import 'package:campo_cnn/preprocesamiento.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('imagen no decodificable no crea tensor', () {
    expect(() => PreparadorImagen.preparar(Uint8List.fromList([1, 2, 3])),
      throwsFormatException);
  });
  test('RGB constante y relleno negro', () {
    final image = img.Image(width: 2, height: 1);
    image.setPixelRgb(0, 0, 255, 0, 0);
    image.setPixelRgb(1, 0, 255, 0, 0);
    final tensor = PreparadorImagen.preparar(Uint8List.fromList(img.encodePng(image)));
    expect(tensor.length, 224 * 224 * 3 * 4);
    final floats = ByteData.sublistView(tensor);
    expect(floats.getFloat32(0, Endian.little), 0);
    final center = ((112 * 224 + 112) * 3) * 4;
    expect(floats.getFloat32(center, Endian.little), closeTo(1, 1e-6));
    expect(floats.getFloat32(center + 4, Endian.little), 0);
  });
  test('remuestreo no constante usa centros de píxel y relleno asimétrico', () {
    final image = img.Image(width: 2, height: 2);
    for (var y = 0; y < 2; y++) {
      image.setPixelRgb(0, y, 0, 0, 0);
      image.setPixelRgb(1, y, 255, 0, 0);
    }
    final tensor = PreparadorImagen.preparar(Uint8List.fromList(img.encodePng(image)));
    final floats = ByteData.sublistView(tensor);
    double red(int x, int y) => floats.getFloat32((y * 224 + x) * 12, Endian.little);
    expect(red(111, 112), closeTo(0.5, 1e-5));
    expect(red(112, 112), greaterThan(0.5));
    expect(red(0, 112), 0);
    expect(red(223, 112), 0);

    final wide = img.Image(width: 3, height: 1);
    for (var x = 0; x < 3; x++) { wide.setPixelRgb(x, 0, 255, 0, 0); }
    final padded = ByteData.sublistView(PreparadorImagen.preparar(
      Uint8List.fromList(img.encodePng(wide))));
    double at(int y) => padded.getFloat32((y * 224 + 112) * 12, Endian.little);
    expect(at(73), 0);
    expect(at(74), closeTo(1, 1e-6));
    expect(at(147), closeTo(1, 1e-6));
    expect(at(148), 0);
  });

  final referencias = (jsonDecode(File('test/fixtures_exif/referencias_pillow.json')
    .readAsStringSync()) as Map<String, dynamic>)['casos'] as List<dynamic>;
  for (final caso in referencias.cast<Map<String, dynamic>>()) {
    final orientacion = caso['orientacion'] as int;
    test('EXIF $orientacion coincide con Pillow 11.3.0', () {
      final original = File('test/fixtures_exif/${caso['original']}').readAsBytesSync();
      expect(sha256.convert(original).toString(), caso['sha256_original']);
      expect(img.decodeJpgExif(original)?.imageIfd.orientation, orientacion);
      final decoded = img.decodeImage(original)!;
      expect(decoded.width, caso['ancho_pillow']);
      expect(decoded.height, caso['alto_pillow']);
      expect(decoded.exif.imageIfd.orientation, isNull);
      final tensor = ByteData.sublistView(PreparadorImagen.preparar(original));
      for (final punto in (caso['puntos'] as List).cast<Map<String, dynamic>>()) {
        final rgb = (punto['rgb'] as List).cast<int>();
        final pixel = decoded.getPixel(
          punto['x_orientado'] as int, punto['y_orientado'] as int);
        final canales = [pixel.r, pixel.g, pixel.b];
        final offset = ((punto['y_tensor'] as int) * 224 +
          (punto['x_tensor'] as int)) * 12;
        for (var c = 0; c < 3; c++) {
          expect(canales[c], closeTo(rgb[c], 5),
            reason: 'Pillow, EXIF $orientacion, ${punto['nombre']}, canal $c');
          expect(tensor.getFloat32(offset + c * 4, Endian.little),
            closeTo(rgb[c] / 255.0, 0.03),
            reason: 'Tensor, EXIF $orientacion, ${punto['nombre']}, canal $c');
        }
      }
    });
  }
  test('reinsertar EXIF 6 después de decodificar rota por segunda vez', () {
    final original = File('test/fixtures_exif/exif_6.jpg').readAsBytesSync();
    final decoded = img.decodeImage(original)!;
    expect([decoded.width, decoded.height], [112, 224]);
    expect(decoded.exif.imageIfd.orientation, isNull);
    decoded.exif = img.decodeJpgExif(original)!;
    final doble = img.bakeOrientation(decoded);
    expect([doble.width, doble.height], [224, 112]);
  });
  test('preparación en isolate produce el mismo tensor para imagen grande', () async {
    final image = img.Image(width: 640, height: 480);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    final direct = PreparadorImagen.preparar(bytes);
    final background = await compute(PreparadorImagen.preparar, bytes);
    expect(listEquals(direct, background), isTrue);
  });
}
