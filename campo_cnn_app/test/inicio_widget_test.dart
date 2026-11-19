import 'dart:async';
import 'dart:io';

import 'package:campo_cnn/avisos.dart';
import 'package:campo_cnn/domain.dart';
import 'package:campo_cnn/flujo.dart';
import 'package:campo_cnn/main.dart';
import 'package:campo_cnn/registro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RegistroInicial extends Registro {
  SeleccionPendiente? pendiente;
  final cerradas = <String>[];
  final actividades = <String>[];
  @override
  Future<void> actividad(String tipo) async { actividades.add(tipo); }
  @override
  Future<void> recuperarHuerfanos() async {}
  @override
  Future<SeleccionPendiente?> seleccionPendiente() async => pendiente;
  @override
  Future<void> cerrarSeleccion(String id) async {
    cerradas.add(id);
    pendiente = null;
  }
  @override
  Future<List<Map<String, Object?>>> pendientes() async => [];
  @override
  Future<List<Map<String, Object?>>> consultas() async => [];
  @override
  Future<List<Map<String, Object?>>> casos() async => [];
  @override
  Future<List<Map<String, Object?>>> revisiones(String casoId) async => [];
  @override
  Future<DateTime?> ultimaActividad() async => null;
  @override
  Future<List<Map<String, Object?>>> avisos() async => [];
  @override
  Future<void> cerrar() async {}
}

class _RegistroCiclo extends Registro {
  _RegistroCiclo({required super.reloj, required super.dbPath,
    required super.documentsDirectory});
  @override
  Future<void> recuperarHuerfanos() async {}
  @override
  Future<SeleccionPendiente?> seleccionPendiente() async => null;
}

class _AvisosCiclo extends Avisos {
  _AvisosCiclo(super.registro, super.abrirDestino, this.payload);
  final String payload;
  @override
  Future<void> iniciar() async { abrirDestino(payload); }
  @override
  Future<void> refrescarPermiso() async {}
  @override
  Future<ResumenAvisos> reconciliar() async => const ResumenAvisos();
}

class _Programador implements ProgramadorAvisos {
  bool fallarPrimera = false;
  int inicios = 0;
  int programaciones = 0;
  String? lanzamientoPayload;
  @override
  Future<void> iniciar(void Function(String) onTap) async {
    inicios++;
    if (fallarPrimera && inicios == 1) throw StateError('avisos no disponibles');
  }
  @override
  Future<String?> lanzamiento() async => lanzamientoPayload;
  @override
  Future<bool?> solicitarPermiso() async => true;
  @override
  Future<bool?> permisoActual() async => true;
  @override
  Future<List<AvisoPendienteAndroid>> pendientes() async => [];
  @override
  Future<void> programar(int id, DateTime vence, String texto, String payload) async {
    programaciones++;
  }
  @override
  Future<void> cancelar(int id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('inicio lento no permite seleccionar foto antes de recuperar estado', (tester) async {
    final registro = _RegistroInicial();
    final continuar = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: Inicio(registroInicial: registro,
      antesIniciar: () => continuar.future,
      recuperarPerdida: () async => LostDataResponse.empty(),
      avisosFactory: (r, abrir) => Avisos(r, abrir, programador: _Programador()))));
    expect(find.text('Iniciando Campo CNN…'), findsOneWidget);
    expect(find.text('Cámara'), findsNothing);
    continuar.complete();
    await tester.pumpAndSettle();
    expect(find.text('Iniciando Campo CNN…'), findsNothing);
    expect(find.text('Diagnóstico'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('abrir desde aviso y reanudar registran actividad sin atender', (tester) async {
    final registro = _RegistroInicial();
    final programador = _Programador()..lanzamientoPayload = 'pendientes';
    await tester.pumpWidget(MaterialApp(home: Inicio(registroInicial: registro,
      recuperarPerdida: () async => LostDataResponse.empty(),
      avisosFactory: (r, abrir) => Avisos(r, abrir, programador: programador))));
    await tester.pumpAndSettle();
    expect(registro.actividades, ['apertura']);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(registro.actividades, ['apertura', 'reanudacion']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('apertura y reanudacion conservan caso, revision y consultas SQLite', (tester) async {
    final dir = await tester.runAsync(() =>
      Directory.systemTemp.createTemp('campo_ciclo_sqlite_'));
    if (dir == null) {
      throw StateError('No se pudo crear SQLite de prueba.');
    }
    final foto = File('${dir.path}/foto.jpg')..writeAsBytesSync([1, 2, 3]);
    var now = DateTime.utc(2026, 1, 1, 10);
    final registro = _RegistroCiclo(reloj: () => now,
      dbPath: '${dir.path}/datos.sqlite', documentsDirectory: dir);
    Future<Map<String, Object?>> capturar() async => {
      'revision': Map<String, Object?>.from((await registro.pendientes()).single),
      'caso': Map<String, Object?>.from((await registro.casos()).single),
      'consultas': (await registro.consultas()).length,
      'actividades': await (await registro.db).query('actividad', orderBy: 'id'),
      'ultima': await registro.ultimaActividad(),
    };
    final antes = await tester.runAsync(() async {
      await registro.guardar(cultivo: Cultivo.arroz, origen: foto, score: 0.9);
      return capturar();
    });
    expect((antes!['actividades'] as List).length, 1);
    now = DateTime.utc(2026, 1, 1, 11);
    final payload = 'caso:${(antes['caso'] as Map)['id']}';
    await tester.pumpWidget(MaterialApp(home: Inicio(registroInicial: registro,
      recuperarPerdida: () async => LostDataResponse.empty(),
      avisosFactory: (r, abrir) => _AvisosCiclo(r, abrir, payload))));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if ((await (await registro.db).query('actividad')).length >= 2) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final abierto = (await tester.runAsync(capturar))!;
    expect(abierto['ultima'], now);
    expect((abierto['actividades'] as List).length, 2);
    expect(abierto['revision'], antes['revision']);
    expect(abierto['caso'], antes['caso']);
    expect(abierto['consultas'], antes['consultas']);
    now = DateTime.utc(2026, 1, 1, 12);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if ((await (await registro.db).query('actividad')).length >= 3) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final reanudado = (await tester.runAsync(capturar))!;
    expect(reanudado['ultima'], now);
    final actividades = reanudado['actividades'] as List<Map<String, Object?>>;
    expect(actividades.length, 3);
    expect(actividades.last['tipo'], 'reanudacion');
    expect(reanudado['revision'], antes['revision']);
    expect(reanudado['caso'], antes['caso']);
    expect(reanudado['consultas'], antes['consultas']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fallo indispensable muestra reintento y permite completar inicio', (tester) async {
    final registro = _RegistroInicial();
    var intentos = 0;
    await tester.pumpWidget(MaterialApp(home: Inicio(registroInicial: registro,
      antesIniciar: () async {
        intentos++;
        if (intentos == 1) throw StateError('fallo controlado');
      },
      recuperarPerdida: () async => LostDataResponse.empty(),
      avisosFactory: (r, abrir) => Avisos(r, abrir, programador: _Programador()))));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Cámara'), findsNothing);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(intentos, 2);
    expect(find.text('Reintentar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selección antigua se resuelve antes de permitir una nueva', (tester) async {
    final registro = _RegistroInicial()
      ..pendiente = const SeleccionPendiente('intento-viejo', Cultivo.arroz, null, null);
    final continuar = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: Inicio(registroInicial: registro,
      antesIniciar: () => continuar.future,
      recuperarPerdida: () async => LostDataResponse.empty(),
      avisosFactory: (r, abrir) => Avisos(r, abrir, programador: _Programador()))));
    expect(find.text('Cámara'), findsNothing);
    expect(registro.cerradas, isEmpty);
    continuar.complete();
    await tester.pumpAndSettle();
    expect(registro.cerradas, ['intento-viejo']);
    expect(find.text('Iniciando Campo CNN…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reintento conserva respuesta recuperada tras fallo de avisos', (tester) async {
    final registro = _RegistroInicial();
    final programador = _Programador()..fallarPrimera = true;
    var recuperaciones = 0;
    await tester.pumpWidget(MaterialApp(home: Inicio(registroInicial: registro,
      recuperarPerdida: () async {
        recuperaciones++;
        return LostDataResponse.empty();
      },
      avisosFactory: (r, abrir) => Avisos(r, abrir, programador: programador))));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(recuperaciones, 1);
    expect(programador.inicios, 2);
    expect(find.text('Reintentar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('otra revisión del mismo cultivo no hereda score ni consulta', (tester) async {
    final registro = _RegistroInicial();
    final avisos = Avisos(registro, (_) {}, programador: _Programador());
    Widget vista(ContextoRevision? contexto) => MaterialApp(home: Diagnostico(
      key: const ValueKey('mismo-cultivo'), cultivo: Cultivo.arroz,
      registro: registro, avisos: avisos, contexto: contexto,
      onIniciar: () => true, onFinalizar: () {}, onConfirmado: () {},
      onCancelar: () {}, onRecuperada: () {}, onGuardado: () {}));
    await tester.pumpWidget(vista(const ContextoRevision('caso-A', 'rev-A', Cultivo.arroz)));
    final dynamic estado = tester.state(find.byType(Diagnostico));
    estado.score = 0.9;
    estado.consultaId = 'consulta-A';
    await tester.pumpWidget(vista(const ContextoRevision('caso-B', 'rev-B', Cultivo.arroz)));
    expect(find.textContaining('caso-B'), findsOneWidget);
    expect(find.textContaining('consulta-A'), findsNothing);
    expect(find.textContaining('Puntuación del modelo'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resultado guardado permanece al cerrar contexto y se limpia en nueva revisión', (tester) async {
    final registro = _RegistroInicial();
    final avisos = Avisos(registro, (_) {}, programador: _Programador());
    Widget vista(ContextoRevision? contexto) => MaterialApp(home: Diagnostico(
      key: const ValueKey('flujo'), cultivo: Cultivo.cana,
      registro: registro, avisos: avisos, contexto: contexto,
      onIniciar: () => true, onFinalizar: () {}, onConfirmado: () {},
      onCancelar: () {}, onRecuperada: () {}, onGuardado: () {}));
    await tester.pumpWidget(vista(const ContextoRevision('caso-A', 'rev-A', Cultivo.cana)));
    final dynamic estado = tester.state(find.byType(Diagnostico));
    estado.score = 0.8;
    estado.consultaId = 'consulta-A';
    await tester.pumpWidget(vista(null));
    expect(find.textContaining('consulta-A'), findsOneWidget);
    await tester.pumpWidget(vista(const ContextoRevision('caso-B', 'rev-B', Cultivo.cana)));
    expect(find.textContaining('consulta-A'), findsNothing);
    expect(find.textContaining('caso-B'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
