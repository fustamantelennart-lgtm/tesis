import 'package:campo_cnn/consultas.dart';
import 'package:campo_cnn/registro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RegistroVencido extends Registro {
  _RegistroVencido() : super(reloj: () => DateTime.utc(2026, 1, 5));
  final revision = <String, Object?>{
    'id': 'revision-a', 'caso_id': 'caso-a', 'estado': 'pendiente',
    'vence_utc': DateTime.utc(2026, 1, 4).toIso8601String(),
    'creado_utc': DateTime.utc(2026, 1, 1).toIso8601String(),
    'atendida_utc': null,
  };
  @override
  Future<List<Map<String, Object?>>> consultas() async => [];
  @override
  Future<List<Map<String, Object?>>> casos() async => [
    {'id': 'caso-a', 'cultivo': 'arroz', 'estado': 'activo',
      'creado_utc': DateTime.utc(2026, 1, 1).toIso8601String()}
  ];
  @override
  Future<List<Map<String, Object?>>> pendientes() async => [revision];
  @override
  Future<List<Map<String, Object?>>> revisiones(String casoId) async => [revision];
  @override
  Future<List<Map<String, Object?>>> consultasCaso(String casoId) async => [];
  @override
  Future<List<Map<String, Object?>>> avisos() async => [];
  @override
  Future<void> cerrar() async {}
}

void main() {
  testWidgets('revisión vencida sigue pendiente visible y se puede abrir', (tester) async {
    final registro = _RegistroVencido();
    String? abierto;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Consultas(
      registro: registro, onCaso: (id) => abierto = id))));
    await tester.pumpAndSettle();
    expect(find.text('Revisión pendiente vencida'), findsOneWidget);
    await tester.tap(find.text('Revisión pendiente vencida'));
    expect(abierto, 'caso-a');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('detalle conserva revisión vencida y permite atenderla', (tester) async {
    final registro = _RegistroVencido();
    String? revisionAtendida;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CasoDetalle(
      registro: registro, casoId: 'caso-a',
      onAtender: (revision, caso, cultivo) {
        revisionAtendida = revision;
        expect(caso, 'caso-a');
      }))));
    await tester.pumpAndSettle();
    expect(find.text('Revisión pendiente vencida'), findsOneWidget);
    expect(find.textContaining('Creada:'), findsOneWidget);
    await tester.tap(find.text('Atender'));
    expect(revisionAtendida, 'revision-a');
    await tester.pumpWidget(const SizedBox());
  });
}
