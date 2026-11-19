import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'domain.dart';

class Medidor {
  static Future<Resumen> ejecutar(PaquetePrueba paquete,
      void Function(int, int) progreso) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('La medición de tesis requiere un Android físico.');
    }
    final info = await DeviceInfoPlugin().androidInfo;
    if (!info.isPhysicalDevice) throw StateError('Usa un teléfono Android físico.');
    // El modo se comprueba desde la compilación. En debug no se admiten cifras.
    if (kDebugMode) throw StateError('Compila en modo profile o release.');
    final motor = await Motor.abrir(paquete.cultivo);
    final archivo = await paquete.archivo.open();
    final resultados = <Medida>[];
    var maxDiferencia = 0.0;
    try {
      // El primer tensor se lee y verifica antes de iniciar los calentamientos.
      await archivo.setPosition(paquete.offset);
      final primero = await archivo.read(tensorBytes);
      if (sha256.convert(primero).toString() != paquete.items.first.shaTensor) {
        throw FormatException('El primer tensor fue alterado.');
      }
      for (var i = 0; i < calentamientos; i++) { motor.inferir(primero); }
      for (var i = 0; i < paquete.items.length; i++) {
        final item = paquete.items[i];
        await archivo.setPosition(paquete.offset + i * tensorBytes);
        final tensor = await archivo.read(tensorBytes);
        if (tensor.length != tensorBytes || sha256.convert(tensor).toString() != item.shaTensor) {
          throw FormatException('Tensor modificado o incompleto: ${item.archivo}');
        }
        // No mover lectura, SHA ni actualización de pantalla al intervalo medido.
        final reloj = Stopwatch()..start();
        final score = motor.inferir(tensor);
        reloj.stop();
        final diferencia = (score - item.scoreReferencia).abs();
        maxDiferencia = max(maxDiferencia, diferencia);
        if (diferencia > 0.0001 ||
            (score >= paquete.cultivo.umbral) !=
                (item.scoreReferencia >= paquete.cultivo.umbral)) {
          throw StateError('No coincide con la referencia TFLite en ${item.archivo}. '
              'Diferencia: $diferencia. No se guarda esta medición.');
        }
        resultados.add(Medida(item.archivo, item.etiqueta, score,
          item.scoreReferencia, reloj.elapsedMicroseconds / 1000.0));
        progreso(i + 1, paquete.items.length);
        // Permitir actualizar la interfaz después de la inferencia.
        await Future<void>.delayed(Duration.zero);
      }
      return Resumen(paquete.cultivo, DateTime.now().toUtc(),
        '${info.manufacturer} ${info.model}', 'Android ${info.version.release}',
        kReleaseMode ? 'release' : 'profile', resultados, maxDiferencia);
    } finally {
      await archivo.close();
      motor.cerrar();
    }
  }
}

class ArchivoResultados {
  static Future<Directory> _carpeta() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/mediciones');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> guardar(Resumen resultado) async {
    final dir = await _carpeta();
    final nombre = '${resultado.cultivo.clave}_${resultado.fecha.toUtc().toIso8601String().replaceAll(':', '-')}.json';
    final f = File('${dir.path}/$nombre');
    return f.writeAsString(const JsonEncoder.withIndent('  ').convert(resultado.toJson()));
  }

  static Future<List<File>> listar() async {
    final dir = await _carpeta();
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  static Future<File> csv(File resultado) async {
    final j = jsonDecode(await resultado.readAsString()) as Map<String, dynamic>;
    final cabecera = 'archivo;etiqueta;score_android;score_colab;prediccion;ms\n';
    final filas = (j['medidas'] as List).map((r) {
      final m = r as Map<String, dynamic>;
      return [m['archivo'], m['etiqueta'], m['score_android'],
        m['score_colab'], m['prediccion'], m['ms']].join(';');
    }).join('\n');
    final destino = File('${resultado.path.substring(0, resultado.path.length - 5)}.csv');
    return destino.writeAsString('\uFEFF$cabecera$filas\n');
  }
}
