import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'domain.dart';
import 'reglas.dart';

class SeleccionPendiente {
  const SeleccionPendiente(this.id, this.cultivo, this.casoId, this.revisionId);
  final String id;
  final Cultivo cultivo;
  final String? casoId;
  final String? revisionId;
}

class Registro {
  Registro({DateTime Function()? reloj, this.dbPath, this.documentsDirectory,
    this.antesEstadoAviso, this.copiarImagen})
    : ahora = reloj ?? DateTime.now;
  final DateTime Function() ahora;
  final String? dbPath;
  final Directory? documentsDirectory;
  final Future<void> Function(String estado)? antesEstadoAviso;
  final Future<File> Function(File origen, String destino)? copiarImagen;
  Future<Database>? _opening;
  Future<void> _archivos = Future<void>.value();

  Future<T> _conArchivos<T>(Future<T> Function() action) async {
    final anterior = _archivos;
    final fin = Completer<void>();
    _archivos = fin.future;
    await anterior;
    try { return await action(); }
    finally { fin.complete(); }
  }

  Future<Database> get db => _opening ??= _abrirConReintento();

  Future<Database> _abrirConReintento() async {
    try { return await _abrir(); }
    catch (_) { _opening = null; rethrow; }
  }

  Future<Database> _abrir() async {
    final d = await openDatabase(
    dbPath ?? '${await getDatabasesPath()}/campo_cnn.sqlite', version: 5,
    onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
    onCreate: (d, _) async {
      await d.execute('CREATE TABLE casos (id TEXT PRIMARY KEY, cultivo TEXT NOT NULL, estado TEXT NOT NULL CHECK(estado IN (\'activo\',\'cerrado\')), creado_utc TEXT NOT NULL, cerrado_utc TEXT)');
      await d.execute('CREATE TABLE revisiones (id TEXT PRIMARY KEY, caso_id TEXT NOT NULL REFERENCES casos(id), consulta_id TEXT REFERENCES consultas(id), creado_utc TEXT NOT NULL, creado_fuente TEXT NOT NULL DEFAULT \'registrado\' CHECK(creado_fuente IN (\'registrado\',\'reconstruido\')), creado_evidencia TEXT, creado_utc_legado TEXT, vence_utc TEXT NOT NULL, estado TEXT NOT NULL CHECK(estado IN (\'pendiente\',\'atendida\')), atendida_utc TEXT, UNIQUE(caso_id, vence_utc))');
      await d.execute('CREATE TABLE consultas (id TEXT PRIMARY KEY, fecha_utc TEXT NOT NULL, cultivo TEXT NOT NULL, imagen TEXT NOT NULL, clase INTEGER NOT NULL CHECK(clase IN (0,1)), score REAL NOT NULL CHECK(score >= 0 AND score <= 1), umbral REAL NOT NULL, modelo_sha256 TEXT NOT NULL, caso_id TEXT REFERENCES casos(id), revision_id TEXT REFERENCES revisiones(id), intento_id TEXT UNIQUE)');
      await d.execute('CREATE TABLE actividad (id INTEGER PRIMARY KEY, fecha_utc TEXT NOT NULL, tipo TEXT NOT NULL)');
      await d.execute('CREATE TABLE avisos (id TEXT PRIMARY KEY, revision_id TEXT REFERENCES revisiones(id), tipo TEXT NOT NULL, vence_utc TEXT NOT NULL, estado TEXT NOT NULL, actualizado_utc TEXT NOT NULL, error TEXT, android_id INTEGER UNIQUE, payload TEXT, texto TEXT)');
      await d.execute('CREATE TABLE avisos_relaciones (aviso_id TEXT NOT NULL REFERENCES avisos(id), revision_id TEXT NOT NULL REFERENCES revisiones(id), motivo TEXT NOT NULL CHECK(motivo IN (\'revision\',\'inactividad\')), PRIMARY KEY(aviso_id, revision_id, motivo))');
      await d.execute('CREATE TABLE avisos_ids (numero INTEGER PRIMARY KEY AUTOINCREMENT, clave TEXT NOT NULL UNIQUE)');
      await d.execute('CREATE TABLE avisos_eventos (id INTEGER PRIMARY KEY AUTOINCREMENT, aviso_id TEXT NOT NULL, fecha_utc TEXT NOT NULL, estado TEXT NOT NULL, vence_utc TEXT NOT NULL, detalle TEXT)');
      await d.execute('CREATE TABLE selecciones (id TEXT PRIMARY KEY, cultivo TEXT NOT NULL, caso_id TEXT, revision_id TEXT, estado TEXT NOT NULL, creado_utc TEXT NOT NULL)');
      await d.execute('CREATE INDEX idx_revisiones_pendientes ON revisiones(estado, vence_utc)');
      await d.execute('CREATE INDEX idx_consultas_caso ON consultas(caso_id, fecha_utc)');
      await d.execute('CREATE UNIQUE INDEX idx_un_pendiente_por_caso ON revisiones(caso_id) WHERE estado = \'pendiente\'');
      await _crearTriggers(d);
      await _crearTriggerRevision(d);
    },
    onUpgrade: (d, old, next) async {
      if (old < 2) {
        await d.execute('CREATE INDEX IF NOT EXISTS idx_consultas_caso ON consultas(caso_id, fecha_utc)');
      }
      if (old < 3) {
        await d.execute('ALTER TABLE consultas ADD COLUMN intento_id TEXT');
        await d.execute('CREATE UNIQUE INDEX idx_consultas_intento ON consultas(intento_id)');
        await d.execute('ALTER TABLE avisos ADD COLUMN android_id INTEGER');
        await d.execute('ALTER TABLE avisos ADD COLUMN payload TEXT');
        await d.execute('ALTER TABLE avisos ADD COLUMN texto TEXT');
        await d.execute('CREATE TABLE avisos_ids (numero INTEGER PRIMARY KEY AUTOINCREMENT, clave TEXT NOT NULL UNIQUE)');
        await d.execute('CREATE TABLE avisos_eventos (id INTEGER PRIMARY KEY AUTOINCREMENT, aviso_id TEXT NOT NULL, fecha_utc TEXT NOT NULL, estado TEXT NOT NULL, vence_utc TEXT NOT NULL, detalle TEXT)');
        await d.execute("INSERT INTO avisos_eventos(aviso_id, fecha_utc, estado, vence_utc, detalle) SELECT id, actualizado_utc, estado, vence_utc, 'estado conservado al migrar' FROM avisos");
        await d.execute('CREATE TABLE selecciones (id TEXT PRIMARY KEY, cultivo TEXT NOT NULL, caso_id TEXT, revision_id TEXT, estado TEXT NOT NULL, creado_utc TEXT NOT NULL)');
        await d.execute('CREATE UNIQUE INDEX idx_un_pendiente_por_caso ON revisiones(caso_id) WHERE estado = \'pendiente\'');
        await _crearTriggers(d);
      }
      if (old < 4) {
        await d.execute('ALTER TABLE revisiones ADD COLUMN creado_utc TEXT');
        await d.execute('CREATE TABLE avisos_relaciones (aviso_id TEXT NOT NULL REFERENCES avisos(id), revision_id TEXT NOT NULL REFERENCES revisiones(id), motivo TEXT NOT NULL CHECK(motivo IN (\'revision\',\'inactividad\')), PRIMARY KEY(aviso_id, revision_id, motivo))');
      }
      if (old < 5) {
        await d.execute("ALTER TABLE revisiones ADD COLUMN creado_fuente TEXT NOT NULL DEFAULT 'reconstruido'");
        await d.execute('ALTER TABLE revisiones ADD COLUMN creado_evidencia TEXT');
        await d.execute('ALTER TABLE revisiones ADD COLUMN creado_utc_legado TEXT');
        await _reconstruirCreacionRevisiones(d);
        await _crearTriggerRevision(d);
      }
    },
    );
    return d;
  }

  static Future<void> _crearTriggers(DatabaseExecutor d) async {
    await d.execute('''CREATE TRIGGER validar_consulta BEFORE INSERT ON consultas BEGIN
      SELECT CASE WHEN NEW.cultivo NOT IN ('arroz', 'cana')
        OR NEW.umbral != CASE NEW.cultivo
          WHEN 'arroz' THEN ${Cultivo.arroz.umbral}
          ELSE ${Cultivo.cana.umbral} END
        OR NEW.modelo_sha256 != CASE NEW.cultivo
          WHEN 'arroz' THEN '${Cultivo.arroz.sha}'
          ELSE '${Cultivo.cana.sha}' END
        OR NEW.clase != (NEW.score >= NEW.umbral)
        OR (NEW.caso_id IS NOT NULL AND
          (SELECT cultivo FROM casos WHERE id = NEW.caso_id) != NEW.cultivo)
        OR (NEW.revision_id IS NOT NULL AND
          (SELECT caso_id FROM revisiones WHERE id = NEW.revision_id) != NEW.caso_id)
        THEN RAISE(ABORT, 'consulta_incoherente') END;
    END''');
  }

  static Future<void> _crearTriggerRevision(DatabaseExecutor d) async {
    await d.execute('''CREATE TRIGGER validar_revision_creacion_insert
      BEFORE INSERT ON revisiones WHEN NEW.creado_utc IS NULL
      BEGIN SELECT RAISE(ABORT, 'revision_sin_creacion'); END''');
    await d.execute('''CREATE TRIGGER validar_revision_creacion_update
      BEFORE UPDATE OF creado_utc ON revisiones WHEN NEW.creado_utc IS NULL
      BEGIN SELECT RAISE(ABORT, 'revision_sin_creacion'); END''');
    await d.execute('''CREATE TRIGGER validar_revision_fuente_insert
      BEFORE INSERT ON revisiones
      WHEN NEW.creado_fuente IS NULL OR NEW.creado_fuente NOT IN ('registrado', 'reconstruido')
      BEGIN SELECT RAISE(ABORT, 'revision_fuente_invalida'); END''');
  }

  static Future<void> _reconstruirCreacionRevisiones(DatabaseExecutor d) async {
    final casos = {for (final c in await d.query('casos')) c['id'] as String: c};
    final consultas = await d.query('consultas');
    final revisiones = await d.query('revisiones');
    for (final r in revisiones) {
      final id = r['id'] as String;
      final caso = casos[r['caso_id'] as String];
      if (caso == null) throw StateError('Revision historica sin caso: $id');
      final cultivo = switch (caso['cultivo']) {
        'arroz' => Cultivo.arroz,
        'cana' => Cultivo.cana,
        _ => throw StateError('Cultivo historico invalido: $id'),
      };
      final vence = DateTime.parse(r['vence_utc'] as String).toUtc();
      // Invertir vence = consulta + plazo evita ordenar revisiones por fecha:
      // el reloj pudo retroceder entre dos consultas validas.
      final creado = vence.subtract(ReglasSeguimiento.plazo(cultivo));
      final candidatas = consultas.where((q) => q['caso_id'] == r['caso_id'] &&
        q['cultivo'] == cultivo.clave && q['clase'] == 1 &&
        DateTime.parse(q['fecha_utc'] as String).toUtc() == creado).toList();
      final evidencia = candidatas.length == 1
        ? 'consulta:${candidatas.single['id']}'
        : DateTime.tryParse(caso['creado_utc'] as String? ?? '')?.toUtc() == creado
          ? 'caso:${caso['id']}' : 'vencimiento_menos_plazo';
      await d.update('revisiones', {
        'creado_utc_legado': r['creado_utc'],
        'creado_utc': creado.toIso8601String(),
        'creado_fuente': 'reconstruido',
        'creado_evidencia': evidencia,
      }, where: 'id = ?', whereArgs: [id]);
    }
  }

  String _id() => '${ahora().toUtc().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
  String _utc(DateTime d) => d.toUtc().toIso8601String();

  Future<void> actividad(String tipo) async {
    await (await db).insert('actividad', {'fecha_utc': _utc(ahora()), 'tipo': tipo});
  }

  Future<SeleccionPendiente> prepararSeleccion(Cultivo cultivo,
      {String? casoId, String? revisionId}) async {
    if ((casoId == null) != (revisionId == null)) {
      throw StateError('Caso y revisión deben seleccionarse juntos.');
    }
    final id = _id();
    await (await db).transaction((txn) async {
      await txn.delete('selecciones', where: 'estado = ?', whereArgs: ['pendiente']);
      if (casoId != null) {
        final rows = await txn.rawQuery('''SELECT r.id FROM revisiones r
          JOIN casos c ON c.id = r.caso_id
          WHERE r.id = ? AND r.caso_id = ? AND r.estado = 'pendiente'
            AND c.cultivo = ? AND c.estado = 'activo' ''',
          [revisionId, casoId, cultivo.clave]);
        if (rows.length != 1) throw StateError('La revisión ya no está pendiente.');
      }
      await txn.insert('selecciones', {'id': id, 'cultivo': cultivo.clave,
        'caso_id': casoId, 'revision_id': revisionId,
        'estado': 'pendiente', 'creado_utc': _utc(ahora())});
    });
    return SeleccionPendiente(id, cultivo, casoId, revisionId);
  }

  Future<SeleccionPendiente?> seleccionPendiente() async {
    final rows = await (await db).query('selecciones', where: 'estado = ?',
      whereArgs: ['pendiente'], orderBy: 'creado_utc DESC', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SeleccionPendiente(r['id'] as String,
      Cultivo.values.firstWhere((c) => c.clave == r['cultivo']),
      r['caso_id'] as String?, r['revision_id'] as String?);
  }

  Future<void> cerrarSeleccion(String id) async {
    await (await db).update('selecciones', {'estado': 'cerrada'},
      where: 'id = ?', whereArgs: [id]);
  }

  Future<String?> consultaPorIntento(String id) async {
    final rows = await (await db).query('consultas', columns: ['id'],
      where: 'intento_id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  Future<String> guardar({required Cultivo cultivo, required File origen,
      required double score, String? casoId, String? revisionId,
      String? intentoId}) => _conArchivos(() => _guardar(
        cultivo: cultivo, origen: origen, score: score, casoId: casoId,
        revisionId: revisionId, intentoId: intentoId));

  Future<String> _guardar({required Cultivo cultivo, required File origen,
      required double score, String? casoId, String? revisionId,
      String? intentoId}) async {
    if (!score.isFinite || score < 0 || score > 1) {
      throw const FormatException('Puntuación inválida.');
    }
    if ((casoId == null) != (revisionId == null)) {
      throw StateError('Caso y revisión deben seleccionarse juntos.');
    }
    if (intentoId != null) {
      final previous = await consultaPorIntento(intentoId);
      if (previous != null) return previous;
    }
    final d = await db;
    final fecha = ahora().toUtc();
    final id = _id();
    final carpeta = Directory('${(documentsDirectory ?? await getApplicationDocumentsDirectory()).path}/consultas');
    await carpeta.create(recursive: true);
    final foto = File('${carpeta.path}/$id.img');
    final parcial = File('${foto.path}.partial');
    try {
      await (copiarImagen?.call(origen, parcial.path) ?? origen.copy(parcial.path));
      await parcial.rename(foto.path);
      await d.transaction((txn) async {
        if (intentoId != null) {
          final previous = await txn.query('consultas', columns: ['id'],
            where: 'intento_id = ?', whereArgs: [intentoId], limit: 1);
          if (previous.isNotEmpty) throw StateError('La selección ya fue registrada.');
          final selection = await txn.query('selecciones', where: 'id = ? AND estado = ?',
            whereArgs: [intentoId, 'pendiente'], limit: 1);
          if (selection.length != 1 || selection.first['cultivo'] != cultivo.clave ||
              selection.first['caso_id'] != casoId ||
              selection.first['revision_id'] != revisionId) {
            throw StateError('El contexto de la fotografía cambió.');
          }
        }
        final positivo = score >= cultivo.umbral;
        String? caso = casoId;
        if (revisionId != null) {
          if (caso == null) throw StateError('Falta el caso de esta revisión.');
          final rows = await txn.query('revisiones', where: 'id = ? AND caso_id = ? AND estado = ?',
            whereArgs: [revisionId, caso, 'pendiente']);
          final cases = await txn.query('casos', where: 'id = ? AND cultivo = ? AND estado = ?',
            whereArgs: [caso, cultivo.clave, 'activo']);
          if (rows.length != 1 || cases.length != 1) throw StateError('La revisión ya fue atendida o no corresponde al cultivo.');
        } else if (caso != null) {
          throw StateError('Selecciona una revisión pendiente del caso.');
        }
        if (positivo && caso == null) {
          caso = _id();
          await txn.insert('casos', {'id': caso, 'cultivo': cultivo.clave,
            'estado': 'activo', 'creado_utc': _utc(fecha)});
        }
        await txn.insert('consultas', {'id': id, 'fecha_utc': _utc(fecha),
          'cultivo': cultivo.clave, 'imagen': foto.path, 'clase': positivo ? 1 : 0,
          'score': score, 'umbral': cultivo.umbral, 'modelo_sha256': cultivo.sha,
          'caso_id': caso, 'revision_id': revisionId, 'intento_id': intentoId});
        if (revisionId != null) {
          await txn.update('revisiones', {'estado': 'atendida', 'atendida_utc': _utc(fecha),
            'consulta_id': id}, where: 'id = ? AND estado = ?', whereArgs: [revisionId, 'pendiente']);
        }
        if (positivo) {
          await txn.insert('revisiones', {'id': _id(), 'caso_id': caso,
            'creado_utc': _utc(fecha), 'creado_fuente': 'registrado',
            'creado_evidencia': 'consulta:$id',
            'vence_utc': _utc(ReglasSeguimiento.vencer(cultivo, fecha)), 'estado': 'pendiente'});
        } else if (caso != null) {
          await txn.update('casos', {'estado': 'cerrado', 'cerrado_utc': _utc(fecha)},
            where: 'id = ?', whereArgs: [caso]);
        }
        await txn.insert('actividad', {'fecha_utc': _utc(fecha), 'tipo': 'consulta'});
        if (intentoId != null) {
          await txn.update('selecciones', {'estado': 'cerrada'},
            where: 'id = ?', whereArgs: [intentoId]);
        }
      });
      return id;
    } catch (_) {
      if (await parcial.exists()) await parcial.delete();
      if (await foto.exists()) await foto.delete();
      if (intentoId != null) {
        final previous = await consultaPorIntento(intentoId);
        if (previous != null) return previous;
      }
      rethrow;
    }
  }

  Future<void> recuperarHuerfanos() => _conArchivos(_recuperarHuerfanos);

  Future<void> _recuperarHuerfanos() async {
    final root = documentsDirectory ?? await getApplicationDocumentsDirectory();
    final carpeta = Directory('${root.path}/consultas');
    if (!await carpeta.exists()) return;
    final referidas = (await consultas())
      .map((r) => p.normalize(r['imagen'] as String)).toSet();
    final recuperadas = Directory('${root.path}/consultas_recuperadas');
    await for (final entity in carpeta.list()) {
      if (entity is! File ||
          !(entity.path.endsWith('.img') || entity.path.endsWith('.partial')) ||
          referidas.contains(p.normalize(entity.path))) { continue; }
      await recuperadas.create(recursive: true);
      final name = entity.uri.pathSegments.last;
      var target = File('${recuperadas.path}/$name');
      if (await target.exists()) {
        target = File('${recuperadas.path}/${_id()}_$name');
      }
      await entity.rename(target.path);
    }
  }

  Future<List<Map<String, Object?>>> consultas() async =>
      (await db).query('consultas', orderBy: 'fecha_utc DESC');
  Future<List<Map<String, Object?>>> consultasCaso(String casoId) async =>
      (await db).query('consultas', where: 'caso_id = ?', whereArgs: [casoId],
        orderBy: 'fecha_utc DESC');
  Future<List<Map<String, Object?>>> casos() async =>
      (await db).query('casos', orderBy: 'creado_utc DESC');
  Future<List<Map<String, Object?>>> revisiones(String casoId) async =>
      (await db).query('revisiones', where: 'caso_id = ?', whereArgs: [casoId], orderBy: 'vence_utc DESC');
  Future<List<Map<String, Object?>>> pendientes() async =>
      (await db).query('revisiones', where: 'estado = ?', whereArgs: ['pendiente'], orderBy: 'vence_utc');
  Future<DateTime?> ultimaActividad() async {
    final rows = await (await db).query('actividad', orderBy: 'fecha_utc DESC', limit: 1);
    return rows.isEmpty ? null : DateTime.parse(rows.first['fecha_utc'] as String);
  }
  Future<void> estadoAviso(String id, String? revisionId, String tipo,
      DateTime vence, String estado, {String? error, int? androidId,
      String? payload, String? texto,
      List<(String revisionId, String motivo)>? relaciones}) async {
    await antesEstadoAviso?.call(estado);
    await (await db).transaction((txn) async {
      final before = await txn.query('avisos', where: 'id = ?', whereArgs: [id], limit: 1);
      final row = {'id': id, 'revision_id': revisionId,
        'tipo': tipo, 'vence_utc': _utc(vence), 'estado': estado,
        'actualizado_utc': _utc(ahora()), 'error': error,
        'android_id': androidId ?? (before.isEmpty ? null : before.first['android_id']),
        'payload': payload ?? (before.isEmpty ? null : before.first['payload']),
        'texto': texto ?? (before.isEmpty ? null : before.first['texto'])};
      if (before.isEmpty) {
        await txn.insert('avisos', row);
      } else {
        await txn.update('avisos', row, where: 'id = ?', whereArgs: [id]);
      }
      if (relaciones != null) {
        await _sincronizarRelaciones(txn, id, relaciones);
      }
      if (before.isEmpty || before.first['estado'] != estado ||
          before.first['vence_utc'] != _utc(vence) || before.first['error'] != error ||
          before.first['payload'] != row['payload'] || before.first['texto'] != row['texto']) {
        await txn.insert('avisos_eventos', {'aviso_id': id, 'fecha_utc': _utc(ahora()),
          'estado': estado, 'vence_utc': _utc(vence), 'detalle': error});
      }
    });
  }
  static Future<void> _sincronizarRelaciones(DatabaseExecutor d, String id,
      List<(String revisionId, String motivo)> relaciones) async {
    final existentes = await d.query('avisos_relaciones',
      where: 'aviso_id = ?', whereArgs: [id]);
    String clave(String revisionId, String motivo) => '$revisionId|$motivo';
    final antes = existentes.map((r) =>
      clave(r['revision_id'] as String, r['motivo'] as String)).toSet();
    final despues = relaciones.map((r) => clave(r.$1, r.$2)).toSet();
    if (antes.length == despues.length && antes.containsAll(despues)) return;
    await d.delete('avisos_relaciones', where: 'aviso_id = ?', whereArgs: [id]);
    for (final relacion in relaciones) {
      await d.insert('avisos_relaciones', {'aviso_id': id,
        'revision_id': relacion.$1, 'motivo': relacion.$2});
    }
  }
  Future<void> sincronizarRelacionesAviso(String id,
      List<(String revisionId, String motivo)> relaciones) async {
    await (await db).transaction((txn) =>
      _sincronizarRelaciones(txn, id, relaciones));
  }
  Future<List<Map<String, Object?>>> relacionesAviso(String id) async =>
    (await db).query('avisos_relaciones', where: 'aviso_id = ?',
      whereArgs: [id], orderBy: 'motivo, revision_id');
  Future<List<Map<String, Object?>>> avisos() async => (await db).query('avisos');
  Future<Map<String, Object?>?> aviso(String id) async {
    final rows = await (await db).query('avisos', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }
  Future<List<Map<String, Object?>>> eventosAvisos() async =>
    (await db).query('avisos_eventos', orderBy: 'id');
  Future<int> numeroAviso(String id) async {
    return (await db).transaction((txn) async {
      final rows = await txn.query('avisos_ids', where: 'clave = ?', whereArgs: [id], limit: 1);
      if (rows.isNotEmpty) return rows.first['numero'] as int;
      final numero = await txn.insert('avisos_ids', {'clave': id});
      if (numero > 0x7fffffff) throw StateError('Se agotaron los identificadores de avisos.');
      return numero;
    });
  }
  Future<void> cerrar() async {
    await _archivos;
    final opening = _opening;
    if (opening != null) {
      try { await (await opening).close(); } catch (_) { /* apertura fallida */ }
    }
    _opening = null;
  }
}

