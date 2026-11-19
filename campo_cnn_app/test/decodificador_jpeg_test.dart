import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campo_cnn/decodificador_jpeg.dart';
import 'package:campo_cnn/preprocesamiento.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Bytes RGB distintos y primer indice distinto entre dos imagenes.
String? _diferencia(Uint8List esperado, Uint8List actual) {
  if (esperado.length != actual.length) {
    return 'longitud ${actual.length} != ${esperado.length}';
  }
  var distintos = 0, primero = -1;
  for (var i = 0; i < esperado.length; i++) {
    if (esperado[i] != actual[i]) {
      distintos++;
      if (primero < 0) primero = i;
    }
  }
  return distintos == 0 ? null
    : '$distintos bytes distintos; primero en $primero '
      '(${actual[primero]} != ${esperado[primero]})';
}

Uint8List _rgbPng(String ruta) => img.decodePng(File(ruta).readAsBytesSync())!
  .convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);

void main() {
  const carpeta = 'test/fixtures_jpeg';
  final referencias = (jsonDecode(File('$carpeta/referencias_pillow_jpeg.json')
    .readAsStringSync()) as Map<String, dynamic>)['casos'] as List<dynamic>;

  for (final caso in referencias.cast<Map<String, dynamic>>()) {
    test('JPEG ${caso['nombre']} identico a Pillow 11.3.0', () {
      final jpeg = File('$carpeta/${caso['jpeg']}').readAsBytesSync();
      expect(sha256.convert(jpeg).toString(), caso['sha256_jpeg']);
      final esperado = _rgbPng('$carpeta/${caso['png']}');
      expect(sha256.convert(esperado).toString(), caso['sha256_rgb']);
      final rgb = DecodificadorJpeg.decodificar(jpeg);
      expect([rgb.ancho, rgb.alto], [caso['ancho'], caso['alto']]);
      expect(_diferencia(esperado, rgb.rgb), isNull);
    });
  }

  test('control: el decodificador de package:image no coincide con Pillow', () {
    // Demuestra que la comparacion exacta detecta la causa de CP04 en arroz.
    final jpeg = File('$carpeta/base_420.jpg').readAsBytesSync();
    final anterior = img.decodeJpg(jpeg)!.convert(numChannels: 3)
      .getBytes(order: img.ChannelOrder.rgb);
    expect(_diferencia(_rgbPng('$carpeta/base_420_pillow.png'), anterior), isNotNull);
  });

  test('orientaciones EXIF 1 a 8 identicas a ImageOps.exif_transpose', () {
    final exif = (jsonDecode(File('test/fixtures_exif/referencias_pillow.json')
      .readAsStringSync()) as Map<String, dynamic>)['casos'] as List<dynamic>;
    for (final caso in exif.cast<Map<String, dynamic>>()) {
      final o = caso['orientacion'] as int;
      final jpeg = File('test/fixtures_exif/${caso['original']}').readAsBytesSync();
      final esperado = _rgbPng('test/fixtures_exif/pillow_orientada_$o.png');
      final rgb = PreparadorImagen.rgbOrientado(jpeg);
      expect([rgb.width, rgb.height], [caso['ancho_pillow'], caso['alto_pillow']],
        reason: 'EXIF $o');
      expect(_diferencia(esperado, rgb.getBytes(order: img.ChannelOrder.rgb)),
        isNull, reason: 'EXIF $o');
    }
  });

  test('datos que no son JPEG valido no producen imagen', () {
    expect(() => DecodificadorJpeg.decodificar(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9])),
      throwsFormatException);
    expect(() => PreparadorImagen.rgbOrientado(
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xC0, 0, 2])), throwsFormatException);
  });
}
