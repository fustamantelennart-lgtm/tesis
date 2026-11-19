import 'dart:io';
import 'dart:typed_data';

import 'package:campo_cnn/diagnostico_motor.dart';
import 'package:campo_cnn/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ejecutor de diagnóstico rechaza tensor incompleto antes de abrir modelo', () async {
    await expectLater(MotorDiagnostico.inferir(Cultivo.arroz, Uint8List(3)),
      throwsFormatException);
  });

  test('ambos modelos reales dan el mismo score en ejecución directa y asíncrona', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tensor = Uint8List(tensorBytes);
    final bytes = ByteData.sublistView(tensor);
    for (var i = 0; i < tensorBytes; i += 4) {
      bytes.setFloat32(i, (i ~/ 4 % 251) / 255, Endian.little);
    }
    for (final cultivo in Cultivo.values) {
      final motor = await Motor.abrir(cultivo);
      late final double directo;
      try { directo = motor.inferir(tensor); }
      finally { motor.cerrar(); }
      for (var n = 0; n < 2; n++) {
        final asincrono = await MotorDiagnostico.inferir(cultivo, tensor);
        expect(asincrono, closeTo(directo, 1e-6));
        expect(asincrono >= cultivo.umbral, directo >= cultivo.umbral);
      }
    }
  }, skip: _tfliteDisponible()
      ? false
      : 'Biblioteca TFLite de escritorio ausente (blobs/libtensorflowlite_c-*); '
        'ejecutar en Android.');
}

/// Misma ruta que usa tflite_flutter 0.12.1 para cargar la biblioteca en escritorio.
bool _tfliteDisponible() {
  if (Platform.isAndroid) return true;
  final carpeta = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isLinux) {
    return File('$carpeta/blobs/libtensorflowlite_c-linux.so').existsSync();
  }
  if (Platform.isWindows) {
    return File('$carpeta/blobs/libtensorflowlite_c-win.dll').existsSync();
  }
  return false;
}
