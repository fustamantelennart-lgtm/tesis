import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:campo_cnn/comparacion_referencias.dart';
import 'package:campo_cnn/preprocesamiento.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _analisis = '../evidencia/cp04_2_investigacion_exif/pillow_etapas';

Map<String, int> _caja(Uint8List tensor) {
  final view = ByteData.sublistView(tensor);
  var minX = 224, minY = 224, maxX = -1, maxY = -1;
  for (var y = 0; y < 224; y++) {
    for (var x = 0; x < 224; x++) {
      final offset = (y * 224 + x) * 12;
      if (view.getFloat32(offset, Endian.little) != 0 ||
          view.getFloat32(offset + 4, Endian.little) != 0 ||
          view.getFloat32(offset + 8, Endian.little) != 0) {
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }
  }
  return {'min_x': minX, 'min_y': minY, 'max_x': maxX, 'max_y': maxY};
}

Map<String, Object?> _diferencia(Uint8List a, Uint8List b) =>
  ComparadorReferencias.comparar(
    tensorReferencia: a, tensorActual: b,
    scoreReferencia: 0.5, scoreActual: 0.5, umbral: 0.5,
  )['tensor'] as Map<String, Object?>;

void main() {
  test('CP04 etapas: Pillow RGB, decodificacion, geometria y tensor', () {
    final manifest = jsonDecode(File('integration_test/fixtures/manifest.json')
      .readAsStringSync()) as Map<String, dynamic>;
    final stages = jsonDecode(File('$_analisis/etapas_pillow.json')
      .readAsStringSync()) as Map<String, dynamic>;
    final records = (manifest['registros'] as List).cast<Map<String, dynamic>>();
    final resultados = <Map<String, Object?>>[];
    for (final stage in (stages['casos'] as List).cast<Map<String, dynamic>>()) {
      final index = stage['indice'] as int;
      final record = records[index];
      final original = File('integration_test/fixtures/${record['original']}')
        .readAsBytesSync();
      final pillowPng = File('$_analisis/${stage['png']}').readAsBytesSync();
      final decoded = img.decodeImage(original)!;
      final pillow = img.decodePng(pillowPng)!;
      final dims = (stage['dimensiones_pillow_rgb'] as List).cast<int>();
      expect([decoded.width, decoded.height], dims);
      expect([pillow.width, pillow.height], dims);
      final rgbDart = decoded.getBytes(order: img.ChannelOrder.rgb);
      final rgbPillow = pillow.getBytes(order: img.ChannelOrder.rgb);
      expect(sha256.convert(rgbPillow).toString(), stage['sha256_rgb_pillow']);
      expect(rgbDart.length, rgbPillow.length);
      var maxRgb = 0, differentRgb = 0;
      var sumRgb = 0;
      for (var i = 0; i < rgbDart.length; i++) {
        final diff = (rgbDart[i] - rgbPillow[i]).abs();
        maxRgb = math.max(maxRgb, diff);
        sumRgb += diff;
        if (diff != 0) differentRgb++;
      }
      final tensorRef = File('integration_test/fixtures/${record['tensor']}')
        .readAsBytesSync();
      final tensorOriginal = PreparadorImagen.preparar(original);
      final tensorPillowRgb = PreparadorImagen.preparar(pillowPng);
      resultados.add({
        'indice': index, 'ruta_relativa': record['ruta_relativa'],
        'orientacion_exif': stage['orientacion_exif'],
        'dimensiones_pillow_rgb': dims,
        'dimensiones_dart_rgb': [decoded.width, decoded.height],
        'rgb_max_abs_0_a_255': maxRgb,
        'rgb_media_abs_0_a_255': sumRgb / rgbDart.length,
        'rgb_bytes_distintos': differentRgb,
        'rgb_bytes_total': rgbDart.length,
        'caja_referencia': _caja(tensorRef),
        'caja_desde_original': _caja(tensorOriginal),
        'caja_desde_pillow_rgb': _caja(tensorPillowRgb),
        'tensor_original_vs_colab': _diferencia(tensorRef, tensorOriginal),
        'tensor_pillow_rgb_vs_colab': _diferencia(tensorRef, tensorPillowRgb),
        'tensor_original_vs_pillow_rgb':
          _diferencia(tensorPillowRgb, tensorOriginal),
      });
    }
    final output = File('../evidencia/cp04_2_investigacion_exif/etapas_dart_pillow.json');
    output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(resultados));
    for (final row in resultados) {
      // ignore: avoid_print
      print('${row['indice']} RGB max=${row['rgb_max_abs_0_a_255']} '
        'tensor original/Colab=${(row['tensor_original_vs_colab'] as Map)['max_abs']} '
        'PillowRGB/Colab=${(row['tensor_pillow_rgb_vs_colab'] as Map)['max_abs']}');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
