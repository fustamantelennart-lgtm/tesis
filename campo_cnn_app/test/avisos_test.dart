import 'dart:io';

import 'package:campo_cnn/avisos.dart';
import 'package:campo_cnn/domain.dart';
import 'package:campo_cnn/registro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ProgramadorFalso implements ProgramadorAvisos {
  bool autorizado = true;
  bool fallar = false;
  int cancelaciones = 0;
  int programaciones = 0;
  final solicitudes = <int, (DateTime, String, String)>{};
  @override
  Future<void> iniciar(void Function(String) onTap) async {}
  @override
  Future<String?> lanzamiento() async => null;
  @override
  Future<bool?> solicitarPermiso() async => autorizado;
  @override
  Future<bool?> permisoActual() async => autorizado;
  @override
  Future<List<AvisoPendienteAndroid>> pendientes() async => solicitudes.entries
    .map((e) => AvisoPendienteAndroid(e.key, e.value.$2, e.value.$3)).toList();
  @override
  Future<void> programar(int id, DateTime vence, String texto, String payload) async {
    if (fallar) throw StateError('fallo simulado');
    programaciones++;
    solicitudes[id] = (vence, texto, payload);
  }
  @override
  Future<void> cancelar(int id) async { cancelaciones++; solicitudes.remove(id); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('inactividad se mueve al abrir y se cancela al atender todo', () async {
    final dir = await Directory.systemTemp.createTemp('campo_avisos_');
    final photo = File('${dir.path}/foto')..writeAsBytesSync([1]);
    var now = DateTime.utc(2026, 1, 1);
    final db = Registro(reloj: () => now, dbPath: '${dir.path}/db.sqlite',
      documentsDirectory: dir);
    await db.guardar(cultivo: Cultivo.arroz, origen: photo, score: 0.9);
    final r = (await db.pendientes()).single;
    final fake = ProgramadorFalso();
    final avisos = Avisos(db, (_) {}, programador: fake);
    await avisos.iniciar();
    await avisos.reconciliar();
    expect(fake.solicitudes.length, 2);
    final inactivityId = await db.numeroAviso('inactividad');
    expect(fake.solicitudes[inactivityId]!.$1, DateTime.utc(2026, 1, 8));
    now = DateTime.utc(2026, 1, 2);
    await avisos.reconciliar(); // mantenimiento: no es actividad del usuario
    expect(await db.ultimaActividad(), DateTime.utc(2026, 1, 1));
    expect(fake.solicitudes[inactivityId]!.$1, DateTime.utc(2026, 1, 8));
    await db.actividad('apertura');
    await avisos.reconciliar();
    expect(fake.solicitudes[inactivityId]!.$1, DateTime.utc(2026, 1, 9));
    expect(fake.cancelaciones, greaterThan(0));
    await db.guardar(cultivo: Cultivo.arroz, origen: photo, score: 0.1,
      casoId: r['caso_id'] as String, revisionId: r['id'] as String);
    await avisos.reconciliar();
    expect(fake.solicitudes, isEmpty);
    expect((await db.aviso('inactividad'))?['estado'], 'cancelado');
    expect((await db.eventosAvisos()).length, greaterThan(3));
    await db.cerrar();
  });

  test('permiso denegado, cambio en Ajustes y fallo de programación', () async {
    final dir = await Directory.systemTemp.createTemp('campo_permisos_');
    final photo = File('${dir.path}/foto')..writeAsBytesSync([2]);
    final db = Registro(reloj: () => DateTime.utc(2026, 2, 1),
      dbPath: '${dir.path}/db.sqlite', documentsDirectory: dir);
    await db.guardar(cultivo: Cultivo.arroz, origen: photo, score: 0.9);
    final fake = ProgramadorFalso()..autorizado = false;
    final avisos = Avisos(db, (_) {}, programador: fake);
    await avisos.iniciar();
    expect((await avisos.reconciliar()).denegados, 2);
    expect(fake.solicitudes, isEmpty);
    fake.autorizado = true;
    fake.fallar = true;
    await avisos.refrescarPermiso();
    expect((await avisos.reconciliar()).fallidos, 2);
    fake.fallar = false;
    expect((await avisos.reconciliar()).programados, 2);
    expect(fake.solicitudes.length, 2);
    await db.cerrar();
  });

  test('coincidencias de una y varias revisiones se agrupan', () async {
    final dir = await Directory.systemTemp.createTemp('campo_grupos_');
    final photo = File('${dir.path}/foto')..writeAsBytesSync([3]);
    final db = Registro(reloj: () => DateTime.utc(2026, 3, 1),
      dbPath: '${dir.path}/db.sqlite', documentsDirectory: dir);
    final fake = ProgramadorFalso();
    final avisos = Avisos(db, (_) {}, programador: fake);
    await avisos.iniciar();
    await db.guardar(cultivo: Cultivo.cana, origen: photo, score: 0.9);
    await avisos.reconciliar();
    expect(fake.solicitudes.length, 1);
    expect(fake.solicitudes.values.single.$3, startsWith('caso:'));
    final avisoId = (await db.avisos()).single['id'] as String;
    final primerasRelaciones = await db.relacionesAviso(avisoId);
    expect(primerasRelaciones.map((r) => r['motivo']).toSet(),
      {'revision', 'inactividad'});
    expect(primerasRelaciones.map((r) => r['revision_id']).toSet().length, 1);
    await db.guardar(cultivo: Cultivo.cana, origen: photo, score: 0.9);
    await avisos.reconciliar();
    expect(fake.solicitudes.length, 1);
    expect(fake.solicitudes.values.single.$2, contains('2 revisiones'));
    expect(fake.solicitudes.values.single.$3, 'pendientes');
    expect((await db.relacionesAviso(avisoId)).length, 4);
    await db.cerrar();
  });

  test('coincidencia de inactividad con un caso considera todos los pendientes', () async {
    final dir = await Directory.systemTemp.createTemp('campo_grupo_motivos_');
    final photo = File('${dir.path}/foto')..writeAsBytesSync([7]);
    final db = Registro(reloj: () => DateTime.utc(2026, 3, 1),
      dbPath: '${dir.path}/db.sqlite', documentsDirectory: dir);
    await db.guardar(cultivo: Cultivo.arroz, origen: photo, score: 0.9);
    await db.guardar(cultivo: Cultivo.cana, origen: photo, score: 0.9);
    final fake = ProgramadorFalso();
    final avisos = Avisos(db, (_) {}, programador: fake);
    await avisos.iniciar();
    await avisos.reconciliar();
    expect(fake.solicitudes.length, 2);
    final grupo = (await db.avisos()).singleWhere((a) => a['tipo'] == 'grupo');
    expect(grupo['payload'], 'pendientes');
    expect(grupo['revision_id'], isNull);
    final motivos = await db.relacionesAviso(grupo['id'] as String);
    expect(motivos.length, 3);
    expect(motivos.where((m) => m['motivo'] == 'inactividad').length, 2);
    expect(motivos.where((m) => m['motivo'] == 'revision').length, 1);
    await db.cerrar();
  });

  test('programación Android aceptada y escritura SQLite fallida se reparan', () async {
    final dir = await Directory.systemTemp.createTemp('campo_parcial_');
    final photo = File('${dir.path}/foto')..writeAsBytesSync([4]);
    var falla = true;
    final db = Registro(reloj: () => DateTime.utc(2026, 4, 1),
      dbPath: '${dir.path}/db.sqlite', documentsDirectory: dir,
      antesEstadoAviso: (estado) async {
        if (estado == 'programado' && falla) { falla = false; throw StateError('disco'); }
      });
    await db.guardar(cultivo: Cultivo.arroz, origen: photo, score: 0.9);
    final fake = ProgramadorFalso();
    final avisos = Avisos(db, (_) {}, programador: fake);
    await avisos.iniciar();
    await expectLater(avisos.reconciliar(), throwsStateError);
    expect(fake.solicitudes.length, 1);
    expect((await db.avisos()).single['estado'], 'solicitado');
    await avisos.reconciliar();
    expect(fake.solicitudes.length, 2);
    expect(fake.cancelaciones, greaterThan(0));
    expect((await db.aviso('revision:${(await db.pendientes()).single['id']}'))?['estado'],
      'programado');
    await db.cerrar();
  });

  test('alarma inexacta pendiente sigue activa después del plazo', () async {
    final dir = await Directory.systemTemp.createTemp('campo_alarma_tardia_');
    final photo = File('${dir.path}/foto')..writeAsBytesSync([5]);
    var now = DateTime.utc(2026, 6, 1);
    final db = Registro(reloj: () => now, dbPath: '${dir.path}/db.sqlite',
      documentsDirectory: dir);
    await db.guardar(cultivo: Cultivo.arroz, origen: photo, score: 0.9);
    final fake = ProgramadorFalso();
    final avisos = Avisos(db, (_) {}, programador: fake);
    await avisos.iniciar();
    await avisos.reconciliar();
    final id = fake.solicitudes.keys.first;
    now = DateTime.utc(2026, 6, 4, 1);
    final resumen = await avisos.reconciliar();
    expect(resumen.vencidos, greaterThan(0));
    expect(fake.solicitudes.containsKey(id), isTrue);
    expect(fake.cancelaciones, 0);
    await db.cerrar();
  });

  test('permiso recuperado tras vencimiento muestra pendiente sin duplicar alarma', () async {
    final dir = await Directory.systemTemp.createTemp('campo_permiso_tardio_');
    final photo = File('${dir.path}/foto')..writeAsBytesSync([6]);
    var now = DateTime.utc(2026, 6, 1);
    final db = Registro(reloj: () => now, dbPath: '${dir.path}/db.sqlite',
      documentsDirectory: dir);
    await db.guardar(cultivo: Cultivo.arroz, origen: photo, score: 0.9);
    final fake = ProgramadorFalso()..autorizado = false;
    final avisos = Avisos(db, (_) {}, programador: fake);
    await avisos.iniciar();
    await avisos.reconciliar();
    now = DateTime.utc(2026, 6, 5);
    fake.autorizado = true;
    await avisos.refrescarPermiso();
    final resumen = await avisos.reconciliar();
    expect(resumen.vencidos, greaterThan(0));
    expect(fake.solicitudes.values.every((s) => s.$1.isAfter(now)), isTrue);
    expect((await db.pendientes()).length, 1);
    expect((await db.eventosAvisos()).any((e) => e['estado'] == 'entregado'), isFalse);
    await db.cerrar();
  });

  test('reinicio reprograma; vencido no se marca como entregado', () async {
    final dir = await Directory.systemTemp.createTemp('campo_reinicio_');
    final photo = File('${dir.path}/foto')..writeAsBytesSync([5]);
    var now = DateTime.utc(2026, 6, 1);
    final db = Registro(reloj: () => now, dbPath: '${dir.path}/db.sqlite',
      documentsDirectory: dir);
    await db.guardar(cultivo: Cultivo.arroz, origen: photo, score: 0.9);
    final fake = ProgramadorFalso();
    final avisos = Avisos(db, (_) {}, programador: fake);
    await avisos.iniciar();
    await avisos.reconciliar();
    final before = fake.programaciones;
    fake.solicitudes.clear(); // Android perdió las alarmas tras reinicio.
    await avisos.reconciliar();
    expect(fake.programaciones, before + 2);
    now = DateTime.utc(2026, 6, 5);
    await db.actividad('apertura');
    final resumen = await avisos.reconciliar();
    expect(resumen.vencidos, 1);
    final review = (await db.pendientes()).single;
    final state = await db.aviso('revision:${review['id']}');
    expect(state?['estado'], 'vencido_pendiente_android');
    expect((await db.eventosAvisos()).any((e) => e['estado'] == 'entregado'), isFalse);
    await db.cerrar();
  });
}
