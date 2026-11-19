import 'dart:convert';
import 'dart:io';

import 'package:campo_cnn/comparacion_referencias.dart';
import 'package:campo_cnn/cp04_ejecucion.dart';
import 'package:campo_cnn/diagnostico_motor.dart';
import 'package:campo_cnn/domain.dart';
import 'package:campo_cnn/preprocesamiento.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _criterioTensor = String.fromEnvironment('TENSOR_MAX_ABS');
const _codigoSha = String.fromEnvironment('CP04_CODE_SHA256');
const _criterioScore = 'abs(android-colab) <= 1e-5 + 1e-4*abs(colab)';
final _nombreBin = RegExp(r'^(original|tensor)_[a-f0-9]{64}\.bin$');

String _csv(Object? value) => '"${(value ?? '').toString().replaceAll('"', '""')}"';

Future<Uint8List> _leerBin(Directory carpeta, String nombre) async {
  if (!_nombreBin.hasMatch(nombre)) throw FormatException('Nombre de referencia invalido: $nombre');
  return File(p.join(carpeta.path, nombre)).readAsBytes();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CP04: originales externos, checkpoint y comparacion completa', (tester) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(_codigoSha)) {
      throw StateError('Falta CP04_CODE_SHA256 generado desde el codigo evaluado.');
    }
    final base = await getExternalStorageDirectory();
    if (base == null) throw StateError('Android no ofrecio directorio externo de la app.');
    final entradas = Directory(p.join(base.path, 'cp04', 'entrada'));
    final salidas = Directory(p.join(base.path, 'cp04', 'salidas'));
    await entradas.create(recursive: true);
    await salidas.create(recursive: true);
    final comprobacion = File(p.join(salidas.path, '.escritura_cp04.tmp'));
    await comprobacion.writeAsString('ok', flush: true);
    await comprobacion.delete();
    final manifestFile = File(p.join(entradas.path, 'manifest.json'));
    if (!await manifestFile.exists()) {
      throw StateError('Falta ${manifestFile.path}; transferir las 629 referencias antes de ejecutar.');
    }
    final manifestBytes = await manifestFile.readAsBytes();
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    if (manifest['estado'] != 'listo' || manifest['esquema'] != 2 ||
        manifest['preprocesamiento'] !=
          'exif_transpose_rgb_tf_resize_with_pad_224_bilinear_antialias_div255' ||
        manifest['tensor_dtype'] != 'float32_le' ||
        (manifest['tensor_shape'] as List).join(',') != '1,224,224,3') {
      throw StateError('Manifiesto CP04 incompleto o incompatible.');
    }
    final registros = (manifest['registros'] as List).cast<Map<String, dynamic>>();
    final conteos = (manifest['conteos_esperados'] as Map).cast<String, dynamic>();
    if (registros.length != 629 || manifest['procesadas'] != 629 ||
        manifest['seleccionadas'] != 629 ||
        registros.map((r) => r['ruta_relativa']).toSet().length != 629 ||
        conteos['arroz/val'] != 217 || conteos['cana/val'] != 412 ||
        conteos.values.fold<int>(0, (s, n) => s + (n as int)) != 629) {
      throw StateError('CP04 requiere las 629 referencias de validacion completas.');
    }
    if (manifest['tensorflow'] != manifest['tensorflow_esperado'] ||
        manifest['pillow'] != manifest['pillow_esperado']) {
      throw StateError('Versiones efectivas distintas de las declaradas.');
    }
    final modelos = (manifest['modelos_sha256'] as Map).cast<String, dynamic>();
    final modelosActuales = <String, String>{};
    for (final cultivo in Cultivo.values) {
      final bytes = await rootBundle.load(cultivo.asset);
      final actual = sha256.convert(bytes.buffer.asUint8List(
        bytes.offsetInBytes, bytes.lengthInBytes)).toString();
      if (actual != cultivo.sha || modelos[cultivo.clave] != actual) {
        throw StateError('Modelo distinto del esperado: ${cultivo.clave}');
      }
      modelosActuales[cultivo.clave] = actual;
    }
    final toleranciaTensor = _criterioTensor.isEmpty
      ? null : double.tryParse(_criterioTensor);
    if (_criterioTensor.isNotEmpty &&
        (toleranciaTensor == null || !toleranciaTensor.isFinite || toleranciaTensor < 0)) {
      throw const FormatException('TENSOR_MAX_ABS invalido.');
    }
    final info = await DeviceInfoPlugin().androidInfo;
    final entorno = <String, Object?>{
      'fabricante': info.manufacturer, 'modelo': info.model,
      'android': info.version.release, 'sdk': info.version.sdkInt,
      'fisico': info.isPhysicalDevice,
    };
    final identidad = <String, Object?>{
      'manifest_sha256': sha256.convert(manifestBytes).toString(),
      'modelos_sha256': modelosActuales,
      'codigo_sha256': _codigoSha,
      'preprocesamiento': preprocesamiento,
      'criterio_score': _criterioScore,
      'criterio_categoria': 'mismo_umbral_y_misma_clase',
      'criterio_tensor_diagnostico': toleranciaTensor,
      'entorno': entorno,
    };
    final run = await EjecucionCp04.abrir(salidas, identidad, 629);
    // ignore: avoid_print
    print('CP04 ejecucion ${run.id}; entrada ${entradas.path}; salida ${salidas.path}');
    final resultados = <Map<String, Object?>>[];
    final observados = <String, int>{};
    var verificadas = 0;
    var comparadas = 0;
    var reutilizadas = 0;
    for (var index = 0; index < registros.length; index++) {
      final row = registros[index];
      final ruta = row['ruta_relativa'] as String;
      final cultivo = switch (row['cultivo']) {
        'arroz' => Cultivo.arroz,
        'cana' => Cultivo.cana,
        _ => throw StateError('Cultivo de referencia invalido: $ruta'),
      };
      final particion = row['particion'] as String;
      if (particion != manifest['particion_objetivo']) {
        throw StateError('Particion ajena a validacion: $ruta');
      }
      final grupo = '${cultivo.clave}/$particion';
      observados[grupo] = (observados[grupo] ?? 0) + 1;
      final salida = <String, Object?>{
        'ruta_relativa': ruta, 'cultivo': cultivo.clave, 'particion': particion,
        'sha256_original': row['sha256_original'] as String,
      };
      try {
        final original = await _leerBin(entradas, row['original'] as String);
        final referencia = await _leerBin(entradas, row['tensor'] as String);
        final originalSha = sha256.convert(original).toString();
        final tensorSha = sha256.convert(referencia).toString();
        salida['sha256_original_verificado'] = originalSha;
        salida['sha256_tensor_verificado'] = tensorSha;
        if (originalSha != row['sha256_original'] || tensorSha != row['sha256_tensor']) {
          throw StateError('SHA-256 de entrada distinto: $ruta');
        }
        if ((row['umbral'] as num).toDouble() != cultivo.umbral) {
          throw StateError('Umbral de referencia distinto: $ruta');
        }
        verificadas++;
        final previo = await run.reutilizar(index, originalSha, tensorSha);
        if (previo != null && previo['ruta_relativa'] == ruta &&
            previo['score_actual'] is num) {
          resultados.add(previo);
          comparadas++;
          reutilizadas++;
          continue;
        }
        final tensorActual = await compute(PreparadorImagen.preparar, original);
        salida['sha256_tensor_referencia'] = tensorSha;
        salida['sha256_tensor_android'] = sha256.convert(tensorActual).toString();
        final scoreActual = await MotorDiagnostico.inferir(cultivo, tensorActual);
        salida.addAll(ComparadorReferencias.comparar(
          tensorReferencia: referencia, tensorActual: tensorActual,
          scoreReferencia: (row['score_referencia'] as num).toDouble(),
          scoreActual: scoreActual, umbral: cultivo.umbral,
          toleranciaTensorMaxAbs: toleranciaTensor,
        ));
        if (salida['categoria_referencia'] != row['categoria_referencia']) {
          throw StateError('Categoria de referencia inconsistente: $ruta');
        }
        comparadas++;
      } catch (error) {
        salida['error'] = '$error';
      }
      await run.guardar(index, salida);
      resultados.add(salida);
      // ignore: avoid_print
      print('CP04 ${index + 1}/629; ejecucion ${run.id}');
      await Future<void>.delayed(Duration.zero);
    }
    final conteosCorrectos = conteos.entries.every((e) => observados[e.key] == e.value);
    final completo = resultados.length == 629 && verificadas == 629 &&
      comparadas == 629 && conteosCorrectos;
    final fallosCriterios = resultados.where((r) =>
      !ComparadorReferencias.cumplePuntuacionYCategoria(r)).length;
    final comparacionPasa = completo && fallosCriterios == 0;
    final reporte = <String, Object?>{
      'id_ejecucion': run.id, 'huella_ejecucion': run.huella,
      'estado': !completo ? 'incompleta' :
        comparacionPasa ? 'comparacion_pasa' : 'comparacion_falla',
      'cp04_aprobado_automaticamente': false,
      'identidad': identidad, 'tensorflow': manifest['tensorflow'],
      'pillow': manifest['pillow'], 'conteos_esperados': conteos,
      'total_esperado': 629, 'entradas_verificadas': verificadas,
      'comparadas': comparadas, 'reutilizadas': reutilizadas,
      'fallos_puntuacion_categoria': fallosCriterios,
      'criterio_tensor_obligatorio': false,
      'resultados': resultados,
    };
    final csv = <String>[
      'ruta_relativa,cultivo,particion,sha256_original,tensor_max_abs,tensor_indice_max_abs,tensor_media_abs,tensor_rmse,tensor_valores_distintos,tensor_fuera_tolerancia,tensor_cumple,score_referencia,score_android,score_error_abs,score_limite,score_cumple,categoria_referencia,categoria_android,categoria_coincide,error',
      for (final r in resultados) [
        r['ruta_relativa'], r['cultivo'], r['particion'], r['sha256_original'],
        (r['tensor'] as Map?)?['max_abs'], (r['tensor'] as Map?)?['indice_max_abs'],
        (r['tensor'] as Map?)?['media_abs'], (r['tensor'] as Map?)?['rmse'],
        (r['tensor'] as Map?)?['valores_distintos'],
        (r['tensor'] as Map?)?['valores_fuera_tolerancia'],
        (r['tensor'] as Map?)?['cumple'], r['score_referencia'], r['score_actual'],
        r['score_error_abs'], r['score_limite'], r['score_cumple'],
        r['categoria_referencia'], r['categoria_actual'],
        r['categoria_coincide'], r['error'],
      ].map(_csv).join(','),
    ].join('\n');
    await run.reporte(reporte, '$csv\n', completo: completo);
    // ignore: avoid_print
    print('CP04 ${run.id}: ${reporte['estado']}; informes en ${salidas.path}');
    expect(comparacionPasa, isTrue,
      reason: 'Revisar informes de puntuacion y categoria; CP04 no se aprueba automaticamente.');
  }, timeout: const Timeout(Duration(hours: 3)));
}
