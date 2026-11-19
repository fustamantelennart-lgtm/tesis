import 'dart:math' as math;
import 'dart:typed_data';

/// Compara valores Float32 de tensores y el criterio de score por separado.
class ComparadorReferencias {
  static bool cumplePuntuacionYCategoria(Map<String, Object?> resultado) =>
      resultado['score_cumple'] == true &&
      resultado['categoria_coincide'] == true;

  static Map<String, Object?> comparar({
    required Uint8List tensorReferencia,
    required Uint8List tensorActual,
    required double scoreReferencia,
    required double scoreActual,
    required double umbral,
    double? toleranciaTensorMaxAbs,
  }) {
    if (tensorReferencia.length != tensorActual.length ||
        tensorReferencia.length % 4 != 0 || tensorReferencia.isEmpty) {
      throw const FormatException('Tensores Float32 incompatibles.');
    }
    if (!scoreReferencia.isFinite || !scoreActual.isFinite ||
        !umbral.isFinite || scoreReferencia < 0 || scoreReferencia > 1 ||
        scoreActual < 0 || scoreActual > 1 || umbral < 0 || umbral > 1) {
      throw const FormatException('Score o umbral inválido.');
    }
    if (toleranciaTensorMaxAbs != null &&
        (!toleranciaTensorMaxAbs.isFinite || toleranciaTensorMaxAbs < 0)) {
      throw const FormatException('Tolerancia de tensor inválida.');
    }
    final ref = ByteData.sublistView(tensorReferencia);
    final actual = ByteData.sublistView(tensorActual);
    final cantidad = tensorReferencia.length ~/ 4;
    var maxAbs = 0.0, sumaAbs = 0.0, sumaCuadrados = 0.0;
    var indiceMax = 0;
    var diferentes = 0, fueraTolerancia = 0;
    for (var i = 0; i < cantidad; i++) {
      final a = ref.getFloat32(i * 4, Endian.little);
      final b = actual.getFloat32(i * 4, Endian.little);
      if (!a.isFinite || !b.isFinite) {
        throw const FormatException('Tensor con valores no finitos.');
      }
      final diferencia = (a - b).abs();
      if (diferencia > maxAbs) { maxAbs = diferencia; indiceMax = i; }
      sumaAbs += diferencia;
      sumaCuadrados += diferencia * diferencia;
      if (diferencia != 0) { diferentes++; }
      if (toleranciaTensorMaxAbs != null &&
          diferencia > toleranciaTensorMaxAbs) { fueraTolerancia++; }
    }
    final errorScore = (scoreActual - scoreReferencia).abs();
    final limiteScore = 1e-5 + 1e-4 * scoreReferencia.abs();
    final categoriaReferencia = scoreReferencia >= umbral ? 1 : 0;
    final categoriaActual = scoreActual >= umbral ? 1 : 0;
    return {
      'tensor': {
        'valores': cantidad,
        'max_abs': maxAbs,
        'indice_max_abs': indiceMax,
        'media_abs': sumaAbs / cantidad,
        'rmse': math.sqrt(sumaCuadrados / cantidad),
        'valores_distintos': diferentes,
        'tolerancia_max_abs': toleranciaTensorMaxAbs,
        'valores_fuera_tolerancia': toleranciaTensorMaxAbs == null
            ? null : fueraTolerancia,
        'cumple': toleranciaTensorMaxAbs == null
            ? null : fueraTolerancia == 0,
      },
      'score_referencia': scoreReferencia,
      'score_actual': scoreActual,
      'score_error_abs': errorScore,
      'score_limite': limiteScore,
      'score_cumple': errorScore <= limiteScore,
      'categoria_referencia': categoriaReferencia,
      'categoria_actual': categoriaActual,
      'categoria_coincide': categoriaReferencia == categoriaActual,
    };
  }
}
