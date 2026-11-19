import 'dart:typed_data';

import 'package:campo_cnn/comparacion_referencias.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List tensor(List<double> valores) {
  final bytes = Uint8List(valores.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < valores.length; i++) {
    data.setFloat32(i * 4, valores[i], Endian.little);
  }
  return bytes;
}

void main() {
  test('métricas de tensor no se confunden con tolerancia de score', () {
    final resultado = ComparadorReferencias.comparar(
      tensorReferencia: tensor([0, 0.5, 1]),
      tensorActual: tensor([0, 0.51, 1]),
      scoreReferencia: 0.6, scoreActual: 0.60001, umbral: 0.65,
      toleranciaTensorMaxAbs: 0.001,
    );
    final medidas = resultado['tensor'] as Map<String, Object?>;
    expect(medidas['max_abs'] as double, closeTo(0.01, 1e-6));
    expect(medidas['valores_distintos'], 1);
    expect(medidas['valores_fuera_tolerancia'], 1);
    expect(medidas['cumple'], false);
    expect(resultado['score_cumple'], true);
    expect(resultado['categoria_coincide'], true);
    expect(ComparadorReferencias.cumplePuntuacionYCategoria(resultado), true);
  });

  test('score puede fallar con tensor idéntico; positivo es inclusivo', () {
    final resultado = ComparadorReferencias.comparar(
      tensorReferencia: tensor([0.2]),
      tensorActual: tensor([0.2]),
      scoreReferencia: 0.65, scoreActual: 0.649, umbral: 0.65,
    );
    final medidas = resultado['tensor'] as Map<String, Object?>;
    expect(medidas['max_abs'], 0);
    expect(medidas['cumple'], null);
    expect(resultado['score_cumple'], false);
    expect(resultado['categoria_referencia'], 1);
    expect(resultado['categoria_actual'], 0);
    expect(resultado['categoria_coincide'], false);
    expect(ComparadorReferencias.cumplePuntuacionYCategoria(resultado), false);
  });

  test('rechaza tensores incompatibles y tolerancia inválida', () {
    expect(() => ComparadorReferencias.comparar(
      tensorReferencia: tensor([0]), tensorActual: Uint8List(3),
      scoreReferencia: 0.5, scoreActual: 0.5, umbral: 0.6,
    ), throwsFormatException);
    expect(() => ComparadorReferencias.comparar(
      tensorReferencia: tensor([0]), tensorActual: tensor([0]),
      scoreReferencia: 0.5, scoreActual: 0.5, umbral: 0.6,
      toleranciaTensorMaxAbs: -1,
    ), throwsFormatException);
  });
}
