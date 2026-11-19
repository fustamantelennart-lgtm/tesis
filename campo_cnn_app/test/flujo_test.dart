import 'package:campo_cnn/domain.dart';
import 'package:campo_cnn/flujo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contexto de caso, revisión y cultivo permanece inseparable', () {
    final flujo = ControlFlujo();
    expect(flujo.seleccionarRevision(const ContextoRevision('caso-a', 'rev-a',
      Cultivo.arroz)), isTrue);
    expect(flujo.cambiarCultivo(Cultivo.cana), isFalse);
    expect(flujo.iniciar(), isTrue);
    expect(flujo.iniciar(), isFalse);
    expect(flujo.seleccionarRevision(const ContextoRevision('caso-b', 'rev-b',
      Cultivo.cana)), isFalse);
    expect(flujo.abrirDestino('caso:caso-b'), isNull);
    expect(flujo.revision!.casoId, 'caso-a');
    expect(flujo.revision!.revisionId, 'rev-a');
    expect(flujo.revision!.cultivo, Cultivo.arroz);
    flujo.confirmar();
    flujo.finalizar();
    expect(flujo.revision, isNull);
    expect(flujo.consumirDestino(), 'caso:caso-b');
    expect(flujo.cambiarCultivo(Cultivo.cana), isTrue);
  });

  test('cancelar limpia revisión y libera destino diferido', () {
    final flujo = ControlFlujo();
    flujo.seleccionarRevision(const ContextoRevision('caso-a', 'rev-a', Cultivo.cana));
    expect(flujo.abrirDestino('pendientes'), isNull);
    expect(flujo.cancelarRevision(), isTrue);
    expect(flujo.revision, isNull);
    expect(flujo.consumirDestino(), 'pendientes');
  });

  test('un aviso no sale de la revisión tras cancelar selector o fallar inferencia', () {
    final flujo = ControlFlujo();
    flujo.seleccionarRevision(const ContextoRevision('caso-a', 'rev-a', Cultivo.arroz));
    expect(flujo.iniciar(), isTrue);
    expect(flujo.abrirDestino('caso:caso-b'), isNull);
    flujo.finalizar();
    expect(flujo.consumirDestino(), isNull);
    expect(flujo.destinoPendiente, 'caso:caso-b');
    expect(flujo.abrirDestino('pendientes'), isNull);
    expect(flujo.cancelarRevision(), isTrue);
    expect(flujo.consumirDestino(), 'pendientes');
  });
}
