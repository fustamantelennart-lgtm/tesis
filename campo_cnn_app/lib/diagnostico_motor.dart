import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'domain.dart';

/// Diagnostic-only asynchronous runner. The measurement runner remains Motor.
class MotorDiagnostico {
  static Future<double> inferir(Cultivo cultivo, Uint8List tensor) async {
    if (tensor.length != tensorBytes) throw const FormatException('Tensor incompleto.');
    final motor = await Motor.abrir(cultivo); // SHA, shape, dtype and one CPU thread.
    IsolateInterpreter? worker;
    try {
      worker = await IsolateInterpreter.create(address: motor.interprete.address);
      final salida = <List<double>>[[0.0]];
      await worker.run(tensor, salida);
      final score = salida[0][0];
      if (!score.isFinite || score < 0 || score > 1) {
        throw StateError('La salida del modelo está fuera de [0, 1].');
      }
      return score;
    } finally {
      await worker?.close();
      motor.cerrar();
    }
  }
}
