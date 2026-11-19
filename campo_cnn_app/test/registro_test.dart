import 'dart:io';
import 'dart:async';

import 'package:campo_cnn/domain.dart';
import 'package:campo_cnn/registro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('consulta, revisión, cierre, duplicados y reapertura SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('campo_cnn_registro_');
    final source = File('${dir.path}/foto.jpg')..writeAsBytesSync([1, 2, 3]);
    var now = DateTime.utc(2026, 1, 1, 10);
    Registro abrir() => Registro(reloj: () => now,
      dbPath: '${dir.path}/datos.sqlite', documentsDirectory: dir);
    final registro = abrir();

    await registro.guardar(cultivo: Cultivo.arroz, origen: source, score: 0.8);
    var cases = await registro.casos();
    expect(cases.length, 1);
    final caseId = cases.first['id'] as String;
    var reviews = await registro.revisiones(caseId);
    expect(reviews.length, 1);
    expect(reviews.first['vence_utc'], DateTime.utc(2026, 1, 4, 10).toIso8601String());
    final reviewId = reviews.first['id'] as String;
    await registro.cerrar();

    final reopened = abrir();
    expect((await reopened.consultas()).length, 1);
    expect((await reopened.pendientes()).length, 1);
    await expectLater(reopened.guardar(cultivo: Cultivo.cana, origen: source,
      score: 0.9, casoId: caseId, revisionId: reviewId), throwsStateError);
    expect((await reopened.consultas()).length, 1);

    now = DateTime.utc(2026, 1, 4, 11);
    await reopened.guardar(cultivo: Cultivo.arroz, origen: source, score: 0.2,
      casoId: caseId, revisionId: reviewId);
    cases = await reopened.casos();
    reviews = await reopened.revisiones(caseId);
    expect(cases.single['estado'], 'cerrado');
    expect(reviews.single['estado'], 'atendida');
    expect(await reopened.pendientes(), isEmpty);
    await expectLater(reopened.guardar(cultivo: Cultivo.arroz, origen: source,
      score: 0.8, casoId: caseId, revisionId: reviewId), throwsStateError);
    expect((await reopened.consultas()).length, 2);
    await reopened.guardar(cultivo: Cultivo.arroz, origen: source, score: 0.9);
    final posteriores = await reopened.casos();
    expect(posteriores.length, 2);
    expect(posteriores.singleWhere((c) => c['id'] == caseId)['estado'], 'cerrado');
    expect((await reopened.revisiones(caseId)).single['estado'], 'atendida');
    for (final consulta in await reopened.consultasCaso(caseId)) {
      expect(await File(consulta['imagen'] as String).exists(), isTrue);
    }
    await reopened.cerrar();
  });

  test('sano inicial no crea caso; caña positiva encadena revisión', () async {
    final dir = await Directory.systemTemp.createTemp('campo_cnn_cana_');
    final source = File('${dir.path}/foto.jpg')..writeAsBytesSync([4, 5, 6]);
    var now = DateTime.utc(2026, 2, 1);
    final registro = Registro(reloj: () => now,
      dbPath: '${dir.path}/datos.sqlite', documentsDirectory: dir);
    await registro.guardar(cultivo: Cultivo.cana, origen: source, score: 0.2);
    expect(await registro.casos(), isEmpty);
    expect(await registro.pendientes(), isEmpty);
    await registro.guardar(cultivo: Cultivo.cana, origen: source, score: 0.8);
    final c = (await registro.casos()).single;
    final caseId = c['id'] as String;
    final initial = (await registro.pendientes()).single;
    expect(initial['vence_utc'], DateTime.utc(2026, 2, 8).toIso8601String());
    now = DateTime.utc(2026, 2, 2, 1); // atención anticipada
    await registro.guardar(cultivo: Cultivo.cana, origen: source, score: 0.9,
      casoId: caseId, revisionId: initial['id'] as String);
    final reviews = await registro.revisiones(caseId);
    expect(reviews.length, 2);
    expect((await registro.pendientes()).length, 1);
    expect((await registro.pendientes()).single['vence_utc'],
      DateTime.utc(2026, 2, 9, 1).toIso8601String());
    expect((await registro.casos()).single['estado'], 'activo');
    await registro.cerrar();
  });

  test('rechaza puntuaciones inválidas y deja la copia fallida limpia', () async {
    final dir = await Directory.systemTemp.createTemp('campo_invariantes_');
    final source = File('${dir.path}/foto')..writeAsBytesSync([1]);
    final registro = Registro(dbPath: '${dir.path}/db.sqlite', documentsDirectory: dir,
      copiarImagen: (origen, destino) async {
        await File(destino).writeAsBytes([7]);
        throw const FileSystemException('copia interrumpida');
      });
    for (final score in [double.nan, double.infinity, -0.1, 1.1]) {
      await expectLater(registro.guardar(cultivo: Cultivo.arroz,
        origen: source, score: score), throwsFormatException);
    }
    await expectLater(registro.guardar(cultivo: Cultivo.arroz,
      origen: source, score: 0.8), throwsA(isA<FileSystemException>()));
    expect(await registro.consultas(), isEmpty);
    final folder = Directory('${dir.path}/consultas');
    expect((await folder.list().toList()).whereType<File>(), isEmpty);
    final orphan = File('${folder.path}/orphan.img')..writeAsBytesSync([8]);
    await registro.recuperarHuerfanos();
    expect(await orphan.exists(), isFalse);
    expect(await File('${dir.path}/consultas_recuperadas/orphan.img').exists(), isTrue);
    await registro.cerrar();
  });

  test('apertura fallida permite reintento y cierre coordinado', () async {
    final dir = await Directory.systemTemp.createTemp('campo_apertura_');
    final invalid = Directory('${dir.path}/datos.sqlite')..createSync();
    final registro = Registro(dbPath: invalid.path, documentsDirectory: dir);
    await expectLater(registro.db, throwsA(isA<Exception>()));
    await invalid.delete();
    expect(await registro.consultas(), isEmpty);
    await registro.cerrar();
  });

  test('migración de versión 2 conserva casos y agrega restricciones', () async {
    final dir = await Directory.systemTemp.createTemp('campo_migracion_');
    final path = '${dir.path}/datos.sqlite';
    final old = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(version: 2, onCreate: (d, _) async {
        await d.execute('CREATE TABLE casos (id TEXT PRIMARY KEY, cultivo TEXT, estado TEXT, creado_utc TEXT, cerrado_utc TEXT)');
        await d.execute('CREATE TABLE revisiones (id TEXT PRIMARY KEY, caso_id TEXT, consulta_id TEXT, vence_utc TEXT, estado TEXT, atendida_utc TEXT)');
        await d.execute('CREATE TABLE consultas (id TEXT PRIMARY KEY, fecha_utc TEXT, cultivo TEXT, imagen TEXT, clase INTEGER, score REAL, umbral REAL, modelo_sha256 TEXT, caso_id TEXT, revision_id TEXT)');
        await d.execute('CREATE TABLE actividad (id INTEGER PRIMARY KEY, fecha_utc TEXT, tipo TEXT)');
        await d.execute('CREATE TABLE avisos (id TEXT PRIMARY KEY, revision_id TEXT, tipo TEXT, vence_utc TEXT, estado TEXT, actualizado_utc TEXT, error TEXT)');
        await d.insert('casos', {'id': 'previo', 'cultivo': 'arroz',
          'estado': 'activo', 'creado_utc': '2026-01-01T00:00:00Z'});
        await d.insert('avisos', {'id': 'anterior', 'tipo': 'inactividad',
          'vence_utc': '2026-01-08T00:00:00Z', 'estado': 'programado',
          'actualizado_utc': '2026-01-01T00:00:00Z'});
      }));
    await old.close();
    final registro = Registro(dbPath: path, documentsDirectory: dir);
    expect((await registro.casos()).single['id'], 'previo');
    expect(await registro.numeroAviso('revision:abc'), greaterThan(0));
    expect((await registro.eventosAvisos()).single['estado'], 'programado');
    await registro.cerrar();
  });

  test('selección recuperada mantiene contexto y no duplica consulta', () async {
    final dir = await Directory.systemTemp.createTemp('campo_recuperacion_');
    final source = File('${dir.path}/foto')..writeAsBytesSync([9]);
    var now = DateTime.utc(2026, 5, 1);
    Registro abrir() => Registro(reloj: () => now,
      dbPath: '${dir.path}/db.sqlite', documentsDirectory: dir);
    var registro = abrir();
    await registro.guardar(cultivo: Cultivo.arroz, origen: source, score: 0.9);
    final revision = (await registro.pendientes()).single;
    final selection = await registro.prepararSeleccion(Cultivo.arroz,
      casoId: revision['caso_id'] as String,
      revisionId: revision['id'] as String);
    await registro.cerrar();
    registro = abrir();
    final recovered = await registro.seleccionPendiente();
    expect(recovered!.id, selection.id);
    expect(recovered.casoId, selection.casoId);
    expect(recovered.revisionId, selection.revisionId);
    now = DateTime.utc(2026, 5, 4);
    final first = await registro.guardar(cultivo: recovered.cultivo,
      origen: source, score: 0.8, casoId: recovered.casoId,
      revisionId: recovered.revisionId, intentoId: recovered.id);
    final second = await registro.guardar(cultivo: recovered.cultivo,
      origen: source, score: 0.8, casoId: recovered.casoId,
      revisionId: recovered.revisionId, intentoId: recovered.id);
    expect(first, second);
    expect((await registro.consultas()).length, 2);
    expect((await registro.revisiones(recovered.casoId!)).length, 2);
    expect(await registro.seleccionPendiente(), isNull);
    await registro.cerrar();
  });

  test('identificadores Android únicos y restricciones de consulta SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('campo_ids_');
    final path = '${dir.path}/db.sqlite';
    var registro = Registro(dbPath: path, documentsDirectory: dir);
    final a = await registro.numeroAviso('revision:a');
    final b = await registro.numeroAviso('revision:b');
    expect(a, isNot(b));
    await expectLater((await registro.db).insert('consultas', {
      'id': 'incoherente', 'fecha_utc': DateTime.utc(2026).toIso8601String(),
      'cultivo': 'arroz', 'imagen': 'x', 'clase': 1, 'score': 0.2,
      'umbral': Cultivo.arroz.umbral, 'modelo_sha256': Cultivo.arroz.sha,
    }), throwsA(isA<Exception>()));
    await registro.cerrar();
    registro = Registro(dbPath: path, documentsDirectory: dir);
    expect(await registro.numeroAviso('revision:a'), a);
    expect(await registro.numeroAviso('revision:b'), b);
    await registro.cerrar();
  });

  test('barrido espera a la copia en curso y conserva la foto de la consulta', () async {
    final dir = await Directory.systemTemp.createTemp('campo_copia_barrido_');
    final source = File('${dir.path}/origen')..writeAsBytesSync([1, 2, 3]);
    final copiada = Completer<void>();
    final continuar = Completer<void>();
    final registro = Registro(dbPath: '${dir.path}/db.sqlite', documentsDirectory: dir,
      copiarImagen: (origen, destino) async {
        final file = await origen.copy(destino);
        copiada.complete();
        await continuar.future;
        return file;
      });
    final guardar = registro.guardar(cultivo: Cultivo.arroz, origen: source, score: 0.9);
    await copiada.future;
    final barrido = registro.recuperarHuerfanos();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    continuar.complete();
    await guardar;
    await barrido;
    final consulta = (await registro.consultas()).single;
    expect(await File(consulta['imagen'] as String).exists(), isTrue);
    expect((await Directory('${dir.path}/consultas_recuperadas').exists()), isFalse);
    await registro.cerrar();
  });

  test('revisión guarda creación y atención anticipada reinicia plazo desde consulta', () async {
    final dir = await Directory.systemTemp.createTemp('campo_agente_anticipada_');
    final source = File('${dir.path}/foto')..writeAsBytesSync([1, 2, 3]);
    var now = DateTime.utc(2026, 1, 1, 10);
    final registro = Registro(reloj: () => now,
      dbPath: '${dir.path}/db.sqlite', documentsDirectory: dir);
    await registro.guardar(cultivo: Cultivo.arroz, origen: source, score: 0.9);
    final caso = (await registro.casos()).single['id'] as String;
    final primera = (await registro.pendientes()).single;
    expect(primera['creado_utc'], now.toIso8601String());
    expect(primera['creado_fuente'], 'registrado');
    expect(primera['vence_utc'], DateTime.utc(2026, 1, 4, 10).toIso8601String());
    now = DateTime.utc(2026, 1, 2, 9);
    await registro.guardar(cultivo: Cultivo.arroz, origen: source, score: 0.9,
      casoId: caso, revisionId: primera['id'] as String);
    final segunda = (await registro.pendientes()).single;
    expect(segunda['caso_id'], caso);
    expect(segunda['creado_utc'], now.toIso8601String());
    expect(segunda['creado_fuente'], 'registrado');
    expect(segunda['vence_utc'], DateTime.utc(2026, 1, 5, 9).toIso8601String());
    expect((await registro.revisiones(caso)).where((r) => r['estado'] == 'atendida').length, 1);
    await registro.cerrar();
  });

  test('migración 3 a 5 conserva revisiones y reconstruye creación sin borrar avisos', () async {
    final dir = await Directory.systemTemp.createTemp('campo_agente_migracion_');
    final path = '${dir.path}/datos.sqlite';
    final old = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(version: 3, onCreate: (d, _) async {
        await d.execute('CREATE TABLE casos (id TEXT PRIMARY KEY, cultivo TEXT, estado TEXT, creado_utc TEXT, cerrado_utc TEXT)');
        await d.execute('CREATE TABLE revisiones (id TEXT PRIMARY KEY, caso_id TEXT, consulta_id TEXT, vence_utc TEXT, estado TEXT, atendida_utc TEXT)');
        await d.execute('CREATE TABLE consultas (id TEXT PRIMARY KEY, fecha_utc TEXT, cultivo TEXT, clase INTEGER, caso_id TEXT)');
        await d.execute('CREATE TABLE avisos (id TEXT PRIMARY KEY, revision_id TEXT, tipo TEXT, vence_utc TEXT, estado TEXT, actualizado_utc TEXT, error TEXT, android_id INTEGER, payload TEXT, texto TEXT)');
        await d.insert('casos', {'id': 'caso-viejo', 'cultivo': 'arroz',
          'estado': 'activo', 'creado_utc': DateTime.utc(2026, 1, 1).toIso8601String()});
        await d.insert('revisiones', {'id': 'revision-1', 'caso_id': 'caso-viejo',
          'vence_utc': DateTime.utc(2026, 1, 4).toIso8601String(),
          'estado': 'atendida', 'atendida_utc': DateTime.utc(2026, 1, 2).toIso8601String()});
        await d.insert('revisiones', {'id': 'revision-2', 'caso_id': 'caso-viejo',
          'vence_utc': DateTime.utc(2026, 1, 5).toIso8601String(),
          'estado': 'pendiente'});
        await d.insert('avisos', {'id': 'revision:revision-2', 'revision_id': 'revision-2',
          'tipo': 'revision', 'vence_utc': DateTime.utc(2026, 1, 5).toIso8601String(),
          'estado': 'programado', 'actualizado_utc': DateTime.utc(2026, 1, 2).toIso8601String(),
          'android_id': 77, 'payload': 'caso:caso-viejo', 'texto': 'Pendiente'});
      }));
    await old.close();
    final registro = Registro(dbPath: path, documentsDirectory: dir);
    final reviews = await registro.revisiones('caso-viejo');
    final first = reviews.singleWhere((r) => r['id'] == 'revision-1');
    final second = reviews.singleWhere((r) => r['id'] == 'revision-2');
    expect(first['creado_utc'], DateTime.utc(2026, 1, 1).toIso8601String());
    expect(second['creado_utc'], DateTime.utc(2026, 1, 2).toIso8601String());
    expect(first['creado_fuente'], 'reconstruido');
    expect(second['creado_fuente'], 'reconstruido');
    expect(first['creado_evidencia'], 'caso:caso-viejo');
    expect(second['creado_evidencia'], 'vencimiento_menos_plazo');
    expect((await registro.aviso('revision:revision-2'))?['android_id'], 77);
    await registro.estadoAviso('revision:revision-2', 'revision-2', 'revision',
      DateTime.utc(2026, 1, 5), 'programado', androidId: 77,
      payload: 'caso:caso-viejo', texto: 'Pendiente',
      relaciones: [('revision-2', 'revision')]);
    expect((await registro.relacionesAviso('revision:revision-2')).single['revision_id'],
      'revision-2');
    await registro.cerrar();
  });

  test('migracion 4 a 5 reconstruye fechas con reloj retrocedido', () async {
    final dir = await Directory.systemTemp.createTemp('campo_reloj_atras_');
    final path = '${dir.path}/datos.sqlite';
    final old = await databaseFactoryFfi.openDatabase(path,
      options: OpenDatabaseOptions(version: 4, onCreate: (d, _) async {
        await d.execute('CREATE TABLE casos (id TEXT PRIMARY KEY, cultivo TEXT, estado TEXT, creado_utc TEXT)');
        await d.execute('CREATE TABLE revisiones (id TEXT PRIMARY KEY, caso_id TEXT, consulta_id TEXT, creado_utc TEXT, vence_utc TEXT, estado TEXT, atendida_utc TEXT)');
        await d.execute('CREATE TABLE consultas (id TEXT PRIMARY KEY, fecha_utc TEXT, cultivo TEXT, clase INTEGER, caso_id TEXT, revision_id TEXT)');
        await d.insert('casos', {'id': 'c', 'cultivo': 'arroz', 'estado': 'activo',
          'creado_utc': DateTime.utc(2026, 1, 10).toIso8601String()});
        await d.insert('revisiones', {'id': 'r1', 'caso_id': 'c',
          'creado_utc': DateTime.utc(2026, 1, 10).toIso8601String(),
          'vence_utc': DateTime.utc(2026, 1, 13).toIso8601String(),
          'estado': 'atendida', 'atendida_utc': DateTime.utc(2026, 1, 9).toIso8601String()});
        await d.insert('revisiones', {'id': 'r2', 'caso_id': 'c',
          'creado_utc': DateTime.utc(2026, 1, 10).toIso8601String(),
          'vence_utc': DateTime.utc(2026, 1, 12).toIso8601String(),
          'estado': 'pendiente'});
        await d.insert('consultas', {'id': 'q1',
          'fecha_utc': DateTime.utc(2026, 1, 10).toIso8601String(),
          'cultivo': 'arroz', 'clase': 1, 'caso_id': 'c'});
        await d.insert('consultas', {'id': 'q2',
          'fecha_utc': DateTime.utc(2026, 1, 9).toIso8601String(),
          'cultivo': 'arroz', 'clase': 1, 'caso_id': 'c', 'revision_id': 'r1'});
      }));
    await old.close();
    final registro = Registro(dbPath: path, documentsDirectory: dir);
    final reviews = await registro.revisiones('c');
    final r1 = reviews.singleWhere((r) => r['id'] == 'r1');
    final r2 = reviews.singleWhere((r) => r['id'] == 'r2');
    expect(r1['creado_utc'], DateTime.utc(2026, 1, 10).toIso8601String());
    expect(r2['creado_utc'], DateTime.utc(2026, 1, 9).toIso8601String());
    expect(r2['creado_utc_legado'], DateTime.utc(2026, 1, 10).toIso8601String());
    expect(r2['creado_fuente'], 'reconstruido');
    expect(r2['creado_evidencia'], 'consulta:q2');
    expect(r2['estado'], 'pendiente');
    expect((await registro.casos()).single['estado'], 'activo');
    await registro.cerrar();
  });
}

