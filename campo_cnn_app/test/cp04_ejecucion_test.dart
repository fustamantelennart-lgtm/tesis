import 'dart:io';

import 'package:campo_cnn/cp04_ejecucion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checkpoint reutiliza solo entradas y contexto identicos', () async {
    final dir = await Directory.systemTemp.createTemp('campo_cp04_reanudar_');
    final identidad = <String, Object?>{
      'manifest_sha256': 'manifiesto-a', 'modelos_sha256': {'arroz': 'modelo-a'},
      'codigo_sha256': 'codigo-a', 'criterio_score': 'criterio-a',
      'criterio_categoria': 'categoria-a', 'entorno': {'modelo': 'SOV44'},
    };
    final primera = await EjecucionCp04.abrir(dir, identidad, 629);
    await primera.guardar(0, {
      'ruta_relativa': 'arroz/val/a.jpg',
      'sha256_original_verificado': 'original-a',
      'sha256_tensor_verificado': 'tensor-a', 'score_actual': 0.8,
    });
    final reanudada = await EjecucionCp04.abrir(dir, identidad, 629);
    expect(reanudada.id, primera.id);
    expect((await reanudada.reutilizar(0, 'original-a', 'tensor-a'))?['score_actual'], 0.8);
    expect(await reanudada.reutilizar(0, 'original-b', 'tensor-a'), isNull);
    expect(await reanudada.reutilizar(0, 'original-a', 'tensor-b'), isNull);
    await reanudada.guardar(1, {
      'sha256_original_verificado': 'original-a',
      'sha256_tensor_verificado': 'tensor-a', 'error': 'lectura interrumpida',
    });
    expect(await reanudada.reutilizar(1, 'original-a', 'tensor-a'), isNull);
    final otroCodigo = await EjecucionCp04.abrir(dir,
      {...identidad, 'codigo_sha256': 'codigo-b'}, 629);
    expect(otroCodigo.id, isNot(primera.id));
    expect(await otroCodigo.reutilizar(0, 'original-a', 'tensor-a'), isNull);
    final otroCriterio = await EjecucionCp04.abrir(dir,
      {...identidad, 'criterio_score': 'criterio-b'}, 629);
    expect(otroCriterio.id, isNot(primera.id));
    final otroModelo = await EjecucionCp04.abrir(dir,
      {...identidad, 'modelos_sha256': {'arroz': 'modelo-b'}}, 629);
    expect(otroModelo.id, isNot(primera.id));
    final otroManifiesto = await EjecucionCp04.abrir(dir,
      {...identidad, 'manifest_sha256': 'manifiesto-b'}, 629);
    expect(otroManifiesto.id, isNot(primera.id));
  });

  test('informe previo persiste y una ejecucion terminada crea otra', () async {
    final dir = await Directory.systemTemp.createTemp('campo_cp04_informes_');
    final identidad = <String, Object?>{'codigo_sha256': 'codigo-a'};
    final primera = await EjecucionCp04.abrir(dir, identidad, 629);
    await primera.reporte({'estado': 'incompleta'}, 'fila\n', completo: false);
    final incompleta = await EjecucionCp04.abrir(dir, identidad, 629);
    expect(incompleta.id, primera.id);
    await incompleta.reporte({'estado': 'comparacion_falla'}, 'fila\n', completo: true);
    final informes = await dir.list().where((e) => e.path.endsWith('.csv')).toList();
    expect(informes.length, 2);
    final nueva = await EjecucionCp04.abrir(dir, identidad, 629);
    expect(nueva.id, isNot(primera.id));
    expect(await informes.first.exists(), isTrue);
  });
}
