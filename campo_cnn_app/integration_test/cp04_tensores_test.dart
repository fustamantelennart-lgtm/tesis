import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:campo_cnn/comparacion_referencias.dart';
import 'package:campo_cnn/diagnostico_motor.dart';
import 'package:campo_cnn/domain.dart';
import 'package:campo_cnn/preprocesamiento.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _codigoSha = String.fromEnvironment('CP04_CODE_SHA256');
const _indicesCsv = String.fromEnvironment('CP04_INDICES');
const _entorno = String.fromEnvironment('CP04_ENTORNO');

Map<String, Object?> _score(double referencia, double actual, double umbral) {
  final error = (actual - referencia).abs();
  final limite = 1e-5 + 1e-4 * referencia.abs();
  return {
    'referencia': referencia,
    'android': actual,
    'error_abs': error,
    'limite': limite,
    'score_cumple': error <= limite,
    'categoria_referencia': referencia >= umbral ? 1 : 0,
    'categoria_android': actual >= umbral ? 1 : 0,
    'categoria_coincide': (referencia >= umbral) == (actual >= umbral),
  };
}

String _csv(Object? value) => '"${(value ?? '').toString().replaceAll('"', '""')}"';

Future<void> _escribir(File destino, String contenido) async {
  final temporal = File('${destino.path}.tmp');
  await temporal.writeAsString(contenido, flush: true);
  await temporal.rename(destino.path);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CP04 A: tensores Colab en Motor y MotorDiagnostico', (tester) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(_codigoSha) || _entorno.isEmpty) {
      throw StateError('Faltan CP04_CODE_SHA256 o CP04_ENTORNO.');
    }
    final base = await getExternalStorageDirectory();
    if (base == null) throw StateError('No hay carpeta externa de la app.');
    final entradas = Directory(p.join(base.path, 'cp04', 'entrada'));
    final salidas = Directory(p.join(base.path, 'cp04', 'salidas'));
    await salidas.create(recursive: true);
    final manifestBytes = await File(p.join(entradas.path, 'manifest.json')).readAsBytes();
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final registros = (manifest['registros'] as List).cast<Map<String, dynamic>>();
    if (manifest['estado'] != 'listo' || registros.length != 629 ||
        manifest['procesadas'] != 629 || manifest['seleccionadas'] != 629) {
      throw StateError('Manifiesto CP04 incompleto.');
    }
    final indices = _indicesCsv.isEmpty
      ? List<int>.generate(629, (index) => index)
      : _indicesCsv.split(',').map(int.parse).toList();
    if (indices.isEmpty || indices.toSet().length != indices.length ||
        indices.any((index) => index < 0 || index >= 629)) {
      throw StateError('Indices CP04 invalidos.');
    }
    final muestra = _indicesCsv.isNotEmpty;
    final modelos = (manifest['modelos_sha256'] as Map).cast<String, dynamic>();
    for (final cultivo in Cultivo.values) {
      final bytes = await rootBundle.load(cultivo.asset);
      final hash = sha256.convert(bytes.buffer.asUint8List(
        bytes.offsetInBytes, bytes.lengthInBytes)).toString();
      if (hash != cultivo.sha || modelos[cultivo.clave] != hash) {
        throw StateError('Modelo distinto del manifiesto: ${cultivo.clave}');
      }
    }
    final id = '${DateTime.now().toUtc().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final motores = <Cultivo, Motor>{};
    final resultados = <Map<String, Object?>>[];
    try {
      for (final cultivo in Cultivo.values) {
        motores[cultivo] = await Motor.abrir(cultivo);
      }
      for (final index in indices) {
        final row = registros[index];
        final cultivo = switch (row['cultivo']) {
          'arroz' => Cultivo.arroz,
          'cana' => Cultivo.cana,
          _ => throw StateError('Cultivo invalido en fila $index'),
        };
        final ruta = row['ruta_relativa'] as String;
        final resultado = <String, Object?>{
          'indice': index, 'ruta_relativa': ruta, 'cultivo': cultivo.clave,
          'particion': row['particion'],
          'sha256_tensor_referencia': row['sha256_tensor'],
        };
        try {
          if (row['particion'] != 'val' ||
              (row['umbral'] as num).toDouble() != cultivo.umbral) {
            throw StateError('Particion o umbral inconsistente: $ruta');
          }
          final tensor = await File(p.join(entradas.path, row['tensor'] as String))
            .readAsBytes();
          final hash = sha256.convert(tensor).toString();
          if (hash != row['sha256_tensor'] || tensor.length != tensorBytes) {
            throw StateError('Tensor de referencia alterado: $ruta');
          }
          resultado['sha256_tensor_verificado'] = hash;
          final referencia = (row['score_referencia'] as num).toDouble();
          final directo = motores[cultivo]!.inferir(tensor);
          final asincrono = await MotorDiagnostico.inferir(cultivo, tensor);
          resultado['motor'] = _score(referencia, directo, cultivo.umbral);
          resultado['motor_diagnostico'] =
            _score(referencia, asincrono, cultivo.umbral);
          resultado['diferencia_ejecutores'] = (directo - asincrono).abs();
          if (resultado['motor'] is Map &&
              (resultado['motor'] as Map)['categoria_referencia'] !=
                row['categoria_referencia']) {
            throw StateError('Categoria Colab inconsistente: $ruta');
          }
          if (muestra) {
            final original = await File(p.join(entradas.path, row['original'] as String))
              .readAsBytes();
            if (sha256.convert(original).toString() != row['sha256_original']) {
              throw StateError('Original alterado: $ruta');
            }
            final preparado = await compute(PreparadorImagen.preparar, original);
            final scoreOriginal = await MotorDiagnostico.inferir(cultivo, preparado);
            resultado['desde_original'] = ComparadorReferencias.comparar(
              tensorReferencia: tensor, tensorActual: preparado,
              scoreReferencia: referencia, scoreActual: scoreOriginal,
              umbral: cultivo.umbral,
            );
          }
        } catch (error) {
          resultado['error'] = '$error';
        }
        resultados.add(resultado);
        await _escribir(File(p.join(salidas.path,
          'diagnostico_tensor_${id}_${index.toString().padLeft(4, '0')}.json')),
          jsonEncode(resultado));
        // ignore: avoid_print
        print('CP04 A ${resultados.length}/${indices.length}; indice $index; ejecucion $id');
      }
    } finally {
      for (final motor in motores.values) { motor.cerrar(); }
    }
    final errores = resultados.where((row) => row['error'] != null).length;
    final fallosMotor = resultados.where((row) {
      final motor = row['motor'] as Map?;
      return motor == null || motor['score_cumple'] != true ||
        motor['categoria_coincide'] != true;
    }).length;
    final fallosAsincrono = resultados.where((row) {
      final motor = row['motor_diagnostico'] as Map?;
      return motor == null || motor['score_cumple'] != true ||
        motor['categoria_coincide'] != true;
    }).length;
    final informe = <String, Object?>{
      'id_ejecucion': id, 'modo': muestra ? 'muestra' : 'completa',
      'entorno_declarado': _entorno, 'codigo_sha256': _codigoSha,
      'manifest_sha256': sha256.convert(manifestBytes).toString(),
      'modelos_sha256': modelos,
      'criterio_score': 'abs(android-colab) <= 1e-5 + 1e-4*abs(colab)',
      'criterio_categoria': 'mismo_umbral_y_misma_clase',
      'total_manifest': 629, 'seleccionadas': indices.length,
      'errores_ejecucion': errores, 'fallos_motor': fallosMotor,
      'fallos_motor_diagnostico': fallosAsincrono,
      'estado': errores == 0 && fallosMotor == 0 && fallosAsincrono == 0
        ? 'referencia_pasa' : 'referencia_falla',
      'cp04_aprobado_automaticamente': false,
      'resultados': resultados,
    };
    final prefijo = muestra ? 'muestra_tensores' : 'completa_tensores';
    await _escribir(File(p.join(salidas.path, '${prefijo}_$id.json')),
      const JsonEncoder.withIndent('  ').convert(informe));
    final csv = <String>[
      'indice,ruta_relativa,cultivo,error,score_referencia,score_motor,score_motor_cumple,categoria_motor_coincide,score_motor_diagnostico,score_motor_diagnostico_cumple,categoria_motor_diagnostico_coincide,diferencia_ejecutores,tensor_original_max_abs,score_original,score_original_cumple,categoria_original_coincide',
      for (final row in resultados) [
        row['indice'], row['ruta_relativa'], row['cultivo'], row['error'],
        (row['motor'] as Map?)?['referencia'],
        (row['motor'] as Map?)?['android'],
        (row['motor'] as Map?)?['score_cumple'],
        (row['motor'] as Map?)?['categoria_coincide'],
        (row['motor_diagnostico'] as Map?)?['android'],
        (row['motor_diagnostico'] as Map?)?['score_cumple'],
        (row['motor_diagnostico'] as Map?)?['categoria_coincide'],
        row['diferencia_ejecutores'],
        ((row['desde_original'] as Map?)?['tensor'] as Map?)?['max_abs'],
        (row['desde_original'] as Map?)?['score_actual'],
        (row['desde_original'] as Map?)?['score_cumple'],
        (row['desde_original'] as Map?)?['categoria_coincide'],
      ].map(_csv).join(','),
    ].join('\n');
    await _escribir(File(p.join(salidas.path, '${prefijo}_$id.csv')), '$csv\n');
    // ignore: avoid_print
    print('CP04 A $id: ${informe['estado']}; motor=$fallosMotor; '
      'asincrono=$fallosAsincrono; errores=$errores');
    expect(errores + fallosMotor + fallosAsincrono, 0,
      reason: 'Revisar informes CP04 A. La comparacion desde originales es independiente.');
  }, timeout: const Timeout(Duration(hours: 3)));
}
