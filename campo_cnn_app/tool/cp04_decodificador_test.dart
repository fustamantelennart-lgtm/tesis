import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:campo_cnn/comparacion_referencias.dart';
import 'package:campo_cnn/preprocesamiento.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Verificacion local (sin TFLite) del preprocesamiento desde los originales:
// RGB orientado identico a Pillow 11.3.0 y tensor frente al de Colab.
// Indices opcionales: variable de entorno CP04_INDICES=0,5,9
// Carpeta de referencias Pillow e informe: CP04_INVESTIGACION (Docker: /salida/cp04).
final _investigacion = Platform.environment['CP04_INVESTIGACION'] ??
  '../evidencia/cp04_3_decodificador';

Map<String, Object?> _evaluar(Map<String, Object?> tarea) {
  final original = File(tarea['original'] as String).readAsBytesSync();
  final referencia = File(tarea['tensor'] as String).readAsBytesSync();
  final rgb = PreparadorImagen.rgbOrientado(original);
  final bytes = rgb.getBytes(order: img.ChannelOrder.rgb);
  final tensor = PreparadorImagen.preparar(original);
  final diferencia = ComparadorReferencias.comparar(
    tensorReferencia: referencia, tensorActual: tensor,
    scoreReferencia: 0.5, scoreActual: 0.5, umbral: 0.5,
  )['tensor'] as Map<String, Object?>;
  return {
    'indice': tarea['indice'],
    'ancho': rgb.width,
    'alto': rgb.height,
    'sha256_rgb': sha256.convert(bytes).toString(),
    'sha256_tensor': sha256.convert(tensor).toString(),
    'tensor': diferencia,
  };
}

void main() {
  test('CP04 decodificador: RGB Pillow exacto y tensor Colab, 629 originales',
      () async {
    final manifest = jsonDecode(File('integration_test/fixtures/manifest.json')
      .readAsStringSync()) as Map<String, dynamic>;
    final pillow = jsonDecode(File('$_investigacion/rgb_pillow_629.json')
      .readAsStringSync()) as Map<String, dynamic>;
    final registros = (manifest['registros'] as List).cast<Map<String, dynamic>>();
    final casos = (pillow['casos'] as List).cast<Map<String, dynamic>>();
    expect(registros.length, 629);
    expect(casos.length, 629);
    final filtro = Platform.environment['CP04_INDICES'];
    final indices = filtro == null || filtro.isEmpty
      ? List<int>.generate(629, (i) => i)
      : filtro.split(',').map(int.parse).toList();
    final tareas = [
      for (final i in indices) <String, Object?>{
        'indice': i,
        'original': File('integration_test/fixtures/${registros[i]['original']}').absolute.path,
        'tensor': File('integration_test/fixtures/${registros[i]['tensor']}').absolute.path,
      },
    ];
    final trabajadores = math.max(1, math.min(Platform.numberOfProcessors - 1, 12));
    final resultados = <Map<String, Object?>>[];
    var siguiente = 0;
    Future<void> trabajador() async {
      while (siguiente < tareas.length) {
        final tarea = tareas[siguiente++];
        resultados.add(await Isolate.run(() => _evaluar(tarea)));
      }
    }
    await Future.wait([for (var i = 0; i < trabajadores; i++) trabajador()]);
    resultados.sort((a, b) => (a['indice'] as int).compareTo(b['indice'] as int));

    final filas = <Map<String, Object?>>[];
    final porCultivo = <String, Map<String, num>>{};
    for (final r in resultados) {
      final i = r['indice'] as int;
      final ref = casos[i];
      expect(ref['indice'], i);
      final tensor = r['tensor'] as Map<String, Object?>;
      final rgbIgual = r['sha256_rgb'] == ref['sha256_rgb'] &&
        r['ancho'] == ref['ancho'] && r['alto'] == ref['alto'];
      final tensorIgual = r['sha256_tensor'] == registros[i]['sha256_tensor'];
      final cultivo = registros[i]['cultivo'] as String;
      final g = porCultivo.putIfAbsent(cultivo, () => {
        'fotografias': 0, 'rgb_identico': 0, 'tensor_bit_identico': 0,
        'tensor_max_abs_max': 0.0});
      g['fotografias'] = g['fotografias']! + 1;
      if (rgbIgual) g['rgb_identico'] = g['rgb_identico']! + 1;
      if (tensorIgual) g['tensor_bit_identico'] = g['tensor_bit_identico']! + 1;
      g['tensor_max_abs_max'] = math.max(g['tensor_max_abs_max']!.toDouble(),
        (tensor['max_abs'] as num).toDouble());
      filas.add({
        'indice': i, 'ruta_relativa': registros[i]['ruta_relativa'],
        'cultivo': cultivo, 'orientacion_exif': ref['orientacion_exif'],
        'rgb_identico_pillow': rgbIgual, 'tensor_bit_identico_colab': tensorIgual,
        'tensor_max_abs': tensor['max_abs'], 'tensor_rmse': tensor['rmse'],
        'tensor_valores_distintos': tensor['valores_distintos'],
      });
    }
    final informe = {
      'pillow': pillow['pillow'], 'libjpeg_turbo': pillow['libjpeg_turbo'],
      'manifest_sha256': sha256.convert(
        File('integration_test/fixtures/manifest.json').readAsBytesSync()).toString(),
      'preprocesamiento_sha256': sha256.convert(
        File('lib/preprocesamiento.dart').readAsBytesSync()).toString(),
      'decodificador_sha256': sha256.convert(
        File('lib/decodificador_jpeg.dart').readAsBytesSync()).toString(),
      'evaluadas': filas.length,
      'por_cultivo': porCultivo,
      'nota': 'Sin TFLite: no evalua scores. El criterio CP04 se mide en Android.',
      'resultados': filas,
    };
    final sufijo = filtro == null || filtro.isEmpty ? '629' : 'muestra';
    File('$_investigacion/verificacion_decodificador_$sufijo.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(informe));
    // ignore: avoid_print
    print(const JsonEncoder.withIndent(' ').convert(porCultivo));
    final distintos = filas.where((f) => f['rgb_identico_pillow'] != true)
      .map((f) => f['indice']).toList();
    expect(distintos, isEmpty, reason: 'RGB distinto de Pillow en estos indices');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
