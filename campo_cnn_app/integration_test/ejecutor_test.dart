import 'dart:typed_data';

import 'package:campo_cnn/diagnostico_motor.dart';
import 'package:campo_cnn/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('modelos reales: ejecutor directo y asíncrono, varias consultas', (tester) async {
    final tensor = Uint8List(tensorBytes);
    final data = ByteData.sublistView(tensor);
    for (var index = 0; index < tensorBytes; index += 4) {
      data.setFloat32(index, (index ~/ 4 % 251) / 255, Endian.little);
    }
    for (final cultivo in Cultivo.values) {
      final motor = await Motor.abrir(cultivo);
      late final double directo;
      try { directo = motor.inferir(tensor); }
      finally { motor.cerrar(); }
      for (var i = 0; i < 3; i++) {
        final asincrono = await MotorDiagnostico.inferir(cultivo, tensor);
        expect(asincrono, closeTo(directo, 1e-6));
        expect(asincrono >= cultivo.umbral, directo >= cultivo.umbral);
      }
      await expectLater(MotorDiagnostico.inferir(cultivo, Uint8List(3)),
        throwsFormatException);
    }
  });
}
