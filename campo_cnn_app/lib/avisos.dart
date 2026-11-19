import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'registro.dart';
import 'reglas.dart';

class AvisoPendienteAndroid {
  const AvisoPendienteAndroid(this.id, this.texto, this.payload);
  final int id;
  final String? texto;
  final String? payload;
}

abstract class ProgramadorAvisos {
  Future<void> iniciar(void Function(String) onTap);
  Future<String?> lanzamiento();
  Future<bool?> solicitarPermiso();
  Future<bool?> permisoActual();
  Future<List<AvisoPendienteAndroid>> pendientes();
  Future<void> programar(int id, DateTime vence, String texto, String payload);
  Future<void> cancelar(int id);
}

class ProgramadorAndroid implements ProgramadorAvisos {
  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<void> iniciar(void Function(String) onTap) async {
    tzdata.initializeTimeZones();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) onTap(r.payload!);
      });
  }

  @override
  Future<String?> lanzamiento() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp == true
      ? details?.notificationResponse?.payload : null;
  }

  AndroidFlutterLocalNotificationsPlugin? get android => plugin
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool?> solicitarPermiso() async => android?.requestNotificationsPermission();
  @override
  Future<bool?> permisoActual() async => android?.areNotificationsEnabled();

  @override
  Future<List<AvisoPendienteAndroid>> pendientes() async =>
    (await plugin.pendingNotificationRequests()).map((n) =>
      AvisoPendienteAndroid(n.id, n.body, n.payload)).toList();

  @override
  Future<void> programar(int id, DateTime vence, String texto, String payload) async {
    await plugin.zonedSchedule(id, 'Campo CNN', texto,
      tz.TZDateTime.from(vence.toUtc(), tz.UTC),
      const NotificationDetails(android: AndroidNotificationDetails(
        'seguimientos', 'Seguimientos',
        channelDescription: 'Recordatorios de revisiones pendientes')),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload);
  }

  @override
  Future<void> cancelar(int id) => plugin.cancel(id);
}

class ResumenAvisos {
  const ResumenAvisos({this.programados = 0, this.denegados = 0,
    this.fallidos = 0, this.vencidos = 0});
  final int programados;
  final int denegados;
  final int fallidos;
  final int vencidos;
  bool get requiereAtencion => denegados > 0 || fallidos > 0 || vencidos > 0;
  String get mensaje {
    if (fallidos > 0) return 'Hay avisos que no pudieron programarse. Revisa el seguimiento.';
    if (denegados > 0) return 'Los avisos están desactivados en Ajustes de Android.';
    if (vencidos > 0) return 'Hay revisiones vencidas. Comprueba los seguimientos.';
    return '$programados avisos programados; su entrega aún no está verificada.';
  }
}

class _Deseado {
  const _Deseado(this.id, this.revisionId, this.tipo, this.vence,
    this.texto, this.payload, this.relaciones);
  final String id;
  final String? revisionId;
  final String tipo;
  final DateTime vence;
  final String texto;
  final String payload;
  final List<(String revisionId, String motivo)> relaciones;
}

class Avisos {
  Avisos(this.registro, this.abrirDestino, {ProgramadorAvisos? programador})
    : programador = programador ?? ProgramadorAndroid();
  final Registro registro;
  final void Function(String payload) abrirDestino;
  final ProgramadorAvisos programador;
  bool? permiso;
  Future<void> _cola = Future<void>.value();

  Future<void> iniciar() async {
    await programador.iniciar(abrirDestino);
    final payload = await programador.lanzamiento();
    if (payload != null) abrirDestino(payload);
    permiso = await programador.solicitarPermiso();
  }

  Future<void> refrescarPermiso() async {
    permiso = await programador.permisoActual();
  }

  Future<ResumenAvisos> reconciliar() {
    final result = _cola.then((_) => _reconciliar());
    _cola = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  List<_Deseado> _plan(List<Map<String, Object?>> revisiones, DateTime? actividad) {
    final porFecha = <String, List<Map<String, Object?>>>{};
    for (final r in revisiones) {
      final key = DateTime.parse(r['vence_utc'] as String).toUtc().toIso8601String();
      porFecha.putIfAbsent(key, () => []).add(r);
    }
    final inactividad = ReglasSeguimiento.avisoInactividad(actividad, revisiones.length);
    final inactivityKey = inactividad?.toUtc().toIso8601String();
    final motivosInactividad = <(String, String)>[
      for (final r in revisiones) (r['id'] as String, 'inactividad')];
    String destino(List<Map<String, Object?>> afectadas) {
      final casos = afectadas.map((r) => r['caso_id'] as String).toSet();
      return casos.length == 1 ? 'caso:${casos.single}' : 'pendientes';
    }
    final result = <_Deseado>[];
    for (final entry in porFecha.entries) {
      final same = entry.value;
      final vence = DateTime.parse(entry.key);
      final coincideInactividad = entry.key == inactivityKey;
      final grouped = same.length > 1 || coincideInactividad;
      if (grouped) {
        final afectadas = coincideInactividad ? revisiones : same;
        final unSoloCaso = afectadas.map((r) => r['caso_id']).toSet().length == 1;
        result.add(_Deseado('grupo:${entry.key}',
          same.length == 1 && unSoloCaso ? same.single['id'] as String : null,
          'grupo', vence,
          afectadas.length == 1 ? 'Tienes una revisión pendiente.' :
            'Tienes ${afectadas.length} revisiones pendientes.',
          destino(afectadas), [
            for (final r in same) (r['id'] as String, 'revision'),
            if (coincideInactividad) ...motivosInactividad,
          ]));
      } else {
        final r = same.single;
        result.add(_Deseado('revision:${r['id']}', r['id'] as String,
          'revision', vence, 'Tienes una revisión pendiente.',
          'caso:${r['caso_id']}', [(r['id'] as String, 'revision')]));
      }
    }
    if (inactividad != null && !porFecha.containsKey(inactivityKey)) {
      result.add(_Deseado('inactividad', null, 'inactividad', inactividad,
        'Tienes revisiones pendientes en Campo CNN.',
        destino(revisiones), motivosInactividad));
    }
    return result;
  }

  Future<ResumenAvisos> _reconciliar() async {
    final revisiones = await registro.pendientes();
    final desired = _plan(revisiones, await registro.ultimaActividad());
    final now = registro.ahora().toUtc();
    final android = {for (final n in await programador.pendientes()) n.id: n};
    final wanted = <int, _Deseado>{};
    for (final item in desired) {
      wanted[await registro.numeroAviso(item.id)] = item;
    }
    for (final old in await registro.avisos()) {
      final number = old['android_id'] as int?;
      if (!desired.any((v) => v.id == old['id']) && old['estado'] != 'cancelado') {
        if (number != null && android.containsKey(number)) {
          await programador.cancelar(number);
          android.remove(number);
        }
        await registro.estadoAviso(old['id'] as String, old['revision_id'] as String?,
          old['tipo'] as String, DateTime.parse(old['vence_utc'] as String),
          'cancelado', androidId: number);
      }
    }
    for (final id in android.keys.toList()) {
      if (!wanted.containsKey(id)) {
        await programador.cancelar(id);
        android.remove(id);
      }
    }
    var scheduledCount = 0, denied = 0, failed = 0, overdue = 0;
    for (final entry in wanted.entries) {
      final number = entry.key;
      final item = entry.value;
      final stored = await registro.aviso(item.id);
      if (permiso != true) {
        if (android.containsKey(number)) await programador.cancelar(number);
        await registro.estadoAviso(item.id, item.revisionId, item.tipo,
          item.vence, 'permiso_denegado', androidId: number,
          payload: item.payload, texto: item.texto,
          relaciones: item.relaciones);
        denied++;
        continue;
      }
      final pending = android[number];
      if (!item.vence.isAfter(now)) {
        // An inexact Android alarm may still be queued after its due time.
        // Keep a matching request; surface the overdue review in the app.
        // If the request is absent, do not schedule a duplicate in the past.
        final matching = pending?.texto == item.texto &&
          pending?.payload == item.payload;
        final estado = matching ? 'vencido_pendiente_android'
          : 'vencido_sin_entrega_verificada';
        if (pending != null && !matching) await programador.cancelar(number);
        if (stored?['estado'] != estado ||
            stored?['vence_utc'] != item.vence.toUtc().toIso8601String() ||
            stored?['texto'] != item.texto || stored?['payload'] != item.payload ||
            stored?['revision_id'] != item.revisionId ||
            stored?['tipo'] != item.tipo) {
          await registro.estadoAviso(item.id, item.revisionId, item.tipo,
            item.vence, estado, androidId: number,
            payload: item.payload, texto: item.texto,
            relaciones: item.relaciones);
        } else {
          await registro.sincronizarRelacionesAviso(item.id, item.relaciones);
        }
        overdue++;
        continue;
      }
      final consistent = stored?['estado'] == 'programado' &&
        stored?['vence_utc'] == item.vence.toUtc().toIso8601String() &&
        stored?['revision_id'] == item.revisionId &&
        stored?['tipo'] == item.tipo &&
        stored?['android_id'] == number && stored?['texto'] == item.texto &&
        stored?['payload'] == item.payload && pending?.texto == item.texto &&
        pending?.payload == item.payload;
      if (consistent) {
        await registro.sincronizarRelacionesAviso(item.id, item.relaciones);
        scheduledCount++;
        continue;
      }
      if (pending != null) await programador.cancelar(number);
      await registro.estadoAviso(item.id, item.revisionId, item.tipo,
        item.vence, 'solicitado', androidId: number, payload: item.payload,
        texto: item.texto, relaciones: item.relaciones);
      try {
        await programador.programar(number, item.vence, item.texto, item.payload);
      } catch (e) {
        await registro.estadoAviso(item.id, item.revisionId, item.tipo,
          item.vence, 'fallo_programacion', error: '$e', androidId: number,
          payload: item.payload, texto: item.texto,
          relaciones: item.relaciones);
        failed++;
        continue;
      }
      // If this write fails, the next reconciliation sees 'solicitado' and
      // cancels/recreates the Android request before recording 'programado'.
      await registro.estadoAviso(item.id, item.revisionId, item.tipo,
        item.vence, 'programado', androidId: number, payload: item.payload,
        texto: item.texto, relaciones: item.relaciones);
      scheduledCount++;
    }
    return ResumenAvisos(programados: scheduledCount, denegados: denied,
      fallidos: failed, vencidos: overdue);
  }
}
