import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Diario durable de una comparacion CP04. Cada indice se escribe de modo
/// atomico; una ejecucion incompleta se puede reanudar sin mezclar contextos.
class EjecucionCp04 {
  EjecucionCp04._(this.carpeta, this.id, this.identidad, this.huella,
      this.total, this._meta);

  final Directory carpeta;
  final String id;
  final Map<String, Object?> identidad;
  final String huella;
  final int total;
  Map<String, Object?> _meta;

  static String firma(Map<String, Object?> identidad) =>
    sha256.convert(utf8.encode(jsonEncode(identidad))).toString();

  static Future<EjecucionCp04> abrir(Directory carpeta,
      Map<String, Object?> identidad, int total) async {
    await carpeta.create(recursive: true);
    final huella = firma(identidad);
    final candidatos = await carpeta.list().where((e) => e is File &&
      RegExp(r'ejecucion_[0-9a-z_-]+\.json$').hasMatch(e.path.split(Platform.pathSeparator).last))
      .cast<File>().toList();
    candidatos.sort((a, b) => b.path.compareTo(a.path));
    for (final file in candidatos) {
      try {
        final meta = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
        if ((meta['estado'] == 'en_curso' || meta['estado'] == 'incompleta') &&
            meta['huella'] == huella &&
            meta['total'] == total && meta['identidad'] is Map) {
          final id = meta['id'] as String;
          return EjecucionCp04._(carpeta, id, identidad, huella, total, meta);
        }
      } catch (_) {
        // Un metadato incompleto se conserva; se inicia otra ejecucion.
      }
    }
    final id = '${DateTime.now().toUtc().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final meta = <String, Object?>{
      'id': id, 'estado': 'en_curso', 'inicio_utc': DateTime.now().toUtc().toIso8601String(),
      'huella': huella, 'identidad': identidad, 'total': total,
    };
    final run = EjecucionCp04._(carpeta, id, identidad, huella, total, meta);
    await run._guardarMeta();
    return run;
  }

  File _fila(int index) => File('${carpeta.path}/fila_${id}_${index.toString().padLeft(4, '0')}.json');
  File get _archivoMeta => File('${carpeta.path}/ejecucion_$id.json');

  Future<Map<String, Object?>?> reutilizar(int index,
      String originalSha, String tensorSha) async {
    final file = _fila(index);
    if (!await file.exists()) return null;
    try {
      final data = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
      if (data['huella'] != huella || data['indice'] != index ||
          data['sha256_original_verificado'] != originalSha ||
          data['sha256_tensor_verificado'] != tensorSha ||
          data['error'] != null) {
        return null;
      }
      return data;
    } catch (_) { return null; }
  }

  Future<void> guardar(int index, Map<String, Object?> resultado) async {
    final data = <String, Object?>{'huella': huella, 'indice': index, ...resultado};
    await _atomico(_fila(index), jsonEncode(data));
  }

  Future<void> reporte(Map<String, Object?> json, String csv,
      {required bool completo}) async {
    final sufijo = '${DateTime.now().toUtc().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final jsonFile = File('${carpeta.path}/comparacion_${id}_$sufijo.json');
    final csvFile = File('${carpeta.path}/comparacion_${id}_$sufijo.csv');
    await _atomico(jsonFile, const JsonEncoder.withIndent('  ').convert(json));
    await _atomico(csvFile, csv);
    _meta = {..._meta, 'estado': completo ? 'terminada' : 'incompleta',
      'fin_utc': DateTime.now().toUtc().toIso8601String(),
      'informe_json': jsonFile.path, 'informe_csv': csvFile.path};
    await _guardarMeta();
  }

  Future<void> _guardarMeta() =>
    _atomico(_archivoMeta, const JsonEncoder.withIndent('  ').convert(_meta));

  static Future<void> _atomico(File destino, String contenido) async {
    final parcial = File('${destino.path}.tmp');
    await parcial.writeAsString(contenido, flush: true);
    try {
      await parcial.rename(destino.path);
    } on FileSystemException {
      // Windows no permite sustituir el destino con rename. En Android el
      // reemplazo POSIX es atomico y conserva el metadato ante interrupciones.
      if (!Platform.isWindows || !await destino.exists()) {
        rethrow;
      }
      await destino.delete();
      await parcial.rename(destino.path);
    }
  }
}
