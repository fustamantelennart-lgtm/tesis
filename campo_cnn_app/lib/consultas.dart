import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'domain.dart';
import 'registro.dart';

String fechaLocal(Object? value) {
  if (value == null) return 'Sin fecha';
  final d = DateTime.parse(value as String).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} '
      '${two(d.hour)}:${two(d.minute)} (hora local)';
}

bool revisionVencida(Map<String, Object?> revision, DateTime ahora) =>
    revision['estado'] == 'pendiente' &&
    !DateTime.parse(revision['vence_utc'] as String)
        .toUtc()
        .isAfter(ahora.toUtc());

String cultivoVisible(Object? valor) =>
    valor == 'arroz' ? 'Arroz' : 'Caña de azúcar';

String plazoVisible(Object? cultivo) => cultivo == 'arroz'
    ? 'Plazo de seguimiento: 72 horas'
    : 'Plazo de seguimiento: 7 días';

String estadoCasoVisible(Object? estado) =>
    estado == 'cerrado' ? 'Seguimiento cerrado' : 'Seguimiento activo';

String estadoRevisionVisible(Object? estado) =>
    estado == 'atendida' ? 'Revisión atendida' : 'Revisión pendiente';

String estadoAvisoVisible(Object? estado) => switch (estado) {
      'programado' => 'Programado en Android',
      'solicitado' => 'Solicitud en proceso',
      'cancelado' => 'Cancelado',
      'permiso_denegado' => 'Permiso de notificaciones denegado',
      'fallo_programacion' => 'Error al programar',
      'vencido_pendiente_android' =>
        'Vencido; solicitud aún visible en Android',
      'vencido_sin_entrega_verificada' => 'Vencido; entrega no verificada',
      _ => 'Estado: $estado',
    };

String tipoAvisoVisible(Object? tipo) => switch (tipo) {
      'revision' => 'Aviso de revisión',
      'inactividad' => 'Aviso por inactividad',
      'grupo' => 'Aviso agrupado',
      _ => 'Aviso',
    };

String cuentaRegresiva(Object? vence, DateTime ahora) {
  if (vence == null) return 'Sin fecha programada';
  final restante =
      DateTime.parse(vence as String).toLocal().difference(ahora.toLocal());
  if (restante <= Duration.zero) return 'La fecha programada ya fue alcanzada';
  final dias = restante.inDays;
  final horas = restante.inHours.remainder(24);
  final minutos = restante.inMinutes.remainder(60);
  if (dias > 0) return 'Faltan $dias ${dias == 1 ? 'día' : 'días'} y $horas h';
  if (horas > 0) return 'Faltan $horas h y $minutos min';
  return 'Faltan $minutos min';
}

bool avisoEnFecha(Map<String, Object?> aviso, DateTime ahora) =>
    !DateTime.parse(aviso['vence_utc'] as String)
        .toLocal()
        .isAfter(ahora.toLocal());

const _verdeSeguimiento = Color(0xFF176B57);
const _fondoSuave = Color(0xFFEAF4EF);

Widget _encabezadoSeccion(
        BuildContext context, IconData icono, String titulo, int cantidad) =>
    Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Icon(icono, color: _verdeSeguimiento, size: 21),
          const SizedBox(width: 8),
          Expanded(
            child: Text(titulo,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _fondoSuave,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$cantidad',
                style: const TextStyle(
                  color: _verdeSeguimiento,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );

Widget _indicadorResumen(
        IconData icono, String etiqueta, int valor, Color color) =>
    Container(
      width: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, size: 20, color: color),
        const SizedBox(height: 10),
        Text('$valor',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Text(etiqueta,
            style: const TextStyle(fontSize: 12, color: Color(0xFF52635D))),
      ]),
    );

Widget _estadoVacio(IconData icono, String mensaje) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration:
              const BoxDecoration(color: _fondoSuave, shape: BoxShape.circle),
          child: Icon(icono, color: _verdeSeguimiento),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(mensaje,
                style: const TextStyle(color: Color(0xFF52635D)))),
      ]),
    );

Widget _etiquetaEstado(String texto, {Color color = _verdeSeguimiento}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(texto,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );

class Consultas extends StatefulWidget {
  const Consultas({super.key, required this.registro, required this.onCaso});
  final Registro registro;
  final ValueChanged<String> onCaso;
  @override
  State<Consultas> createState() => _ConsultasState();
}

class _ConsultasState extends State<Consultas> {
  bool exportando = false;
  String? errorExportacion;
  Timer? _contador;

  @override
  void initState() {
    super.initState();
    _contador = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _contador?.cancel();
    super.dispose();
  }

  Future<void> _exportar(List<Map<String, Object?>> rows) async {
    if (exportando) return;
    setState(() {
      exportando = true;
      errorExportacion = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      final json = File('${dir.path}/consultas_$stamp.json');
      final csv = File('${dir.path}/consultas_$stamp.csv');
      await json.writeAsString(
        const JsonEncoder.withIndent('  ').convert(rows),
      );
      String cell(Object? value) =>
          '"${(value ?? '').toString().replaceAll('"', '""')}"';
      final columns = [
        'id',
        'fecha_utc',
        'cultivo',
        'clase',
        'score',
        'umbral',
        'modelo_sha256',
        'imagen',
        'caso_id',
        'revision_id',
      ];
      await csv.writeAsString(
        [
          columns.join(','),
          for (final row in rows) columns.map((c) => cell(row[c])).join(','),
        ].join('\n'),
      );
      await Share.shareXFiles([
        XFile(json.path),
        XFile(csv.path),
      ], text: 'Consultas Campo CNN');
    } catch (e) {
      if (mounted) setState(() => errorExportacion = 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: Future.wait([
          widget.registro.consultas(),
          widget.registro.casos(),
          widget.registro.pendientes(),
          widget.registro.avisos(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
              child: Text('No se pudo abrir el historial: ${snapshot.error}'),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final consultas = snapshot.data![0];
          final casos = snapshot.data![1];
          final pendientes = snapshot.data![2];
          final avisos = List<Map<String, Object?>>.from(snapshot.data![3])
            ..sort(
              (a, b) => (b['actualizado_utc'] as String).compareTo(
                a['actualizado_utc'] as String,
              ),
            );
          final avisosConProblema = avisos
              .where(
                (a) =>
                    a['estado'] == 'permiso_denegado' ||
                    a['estado'] == 'fallo_programacion' ||
                    a['estado'] == 'vencido_sin_entrega_verificada',
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _verdeSeguimiento,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: const BoxDecoration(
                        color: Color(0x33FFFFFF), shape: BoxShape.circle),
                    child: const Icon(Icons.fact_check_outlined,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Centro de seguimiento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            )),
                        SizedBox(height: 3),
                        Text('Consultas, revisiones y avisos locales',
                            style: TextStyle(
                              color: Color(0xD9FFFFFF),
                              fontSize: 13,
                            )),
                      ])),
                  IconButton(
                    onPressed: exportando ? null : () => _exportar(consultas),
                    icon: const Icon(Icons.ios_share_outlined,
                        color: Colors.white),
                    tooltip: 'Exportar puntuaciones completas',
                  ),
                  IconButton(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    tooltip: 'Actualizar',
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _indicadorResumen(Icons.event_note_outlined, 'Pendientes',
                        pendientes.length, const Color(0xFFC16B20)),
                    const SizedBox(width: 10),
                    _indicadorResumen(Icons.folder_open_outlined, 'Casos',
                        casos.length, _verdeSeguimiento),
                    const SizedBox(width: 10),
                    _indicadorResumen(Icons.notifications_none_rounded,
                        'Avisos', avisos.length, const Color(0xFF3F6FA8)),
                  ])),
              if (exportando)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: LinearProgressIndicator(),
                ),
              if (errorExportacion != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _estadoVacio(Icons.error_outline, errorExportacion!),
                ),
              if (avisosConProblema.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                        '${avisosConProblema.length} avisos requieren atención. '
                        'Comprueba permisos y revisiones pendientes.'),
                  ),
                ),
              _encabezadoSeccion(context, Icons.event_note_outlined,
                  'Revisiones pendientes', pendientes.length),
              if (pendientes.isEmpty)
                _estadoVacio(Icons.event_available_outlined,
                    'No hay revisiones pendientes por atender.'),
              for (final r in pendientes)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFFFF1E2),
                      child: Icon(Icons.schedule,
                          color: revisionVencida(r, widget.registro.ahora())
                              ? const Color(0xFFB42318)
                              : const Color(0xFFC16B20)),
                    ),
                    title: Text(
                        revisionVencida(r, widget.registro.ahora())
                            ? 'Revisión pendiente vencida'
                            : 'Revisión pendiente',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${cultivoVisible(r['cultivo'])} · ${plazoVisible(r['cultivo'])}\n'
                        'Programada para ${fechaLocal(r['vence_utc'])}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onCaso(r['caso_id'] as String),
                  ),
                ),
              _encabezadoSeccion(context, Icons.folder_open_outlined,
                  'Seguimientos', casos.length),
              if (casos.isEmpty)
                _estadoVacio(Icons.folder_open_outlined,
                    'Los casos positivos aparecerán aquí con su historial.'),
              for (final c in casos)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: CircleAvatar(
                      backgroundColor: c['estado'] == 'cerrado'
                          ? const Color(0xFFE8F0EC)
                          : _fondoSuave,
                      child: Icon(
                          c['estado'] == 'cerrado'
                              ? Icons.task_alt_outlined
                              : Icons.monitor_heart_outlined,
                          color: _verdeSeguimiento),
                    ),
                    title: Text(cultivoVisible(c['cultivo']),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        'Consulta inicial: ${fechaLocal(c['creado_utc'])}'),
                    trailing: _etiquetaEstado(estadoCasoVisible(c['estado']),
                        color: c['estado'] == 'cerrado'
                            ? const Color(0xFF52635D)
                            : _verdeSeguimiento),
                    onTap: () => widget.onCaso(c['id'] as String),
                  ),
                ),
              _encabezadoSeccion(context, Icons.notifications_none_rounded,
                  'Avisos registrados', avisos.length),
              if (avisos.isEmpty)
                _estadoVacio(Icons.notifications_off_outlined,
                    'Aún no hay solicitudes de aviso registradas.'),
              for (final a in avisos)
                Builder(builder: (context) {
                  final fechaAlcanzada =
                      avisoEnFecha(a, widget.registro.ahora());
                  final cancelado = a['estado'] == 'cancelado';
                  final listoParaAtender = fechaAlcanzada && !cancelado;
                  final color = listoParaAtender
                      ? const Color(0xFFC16B20)
                      : const Color(0xFF3F6FA8);
                  final titulo = cancelado
                      ? 'Aviso cancelado'
                      : listoParaAtender
                          ? 'Revisión pendiente por atender'
                          : '${tipoAvisoVisible(a['tipo'])} programado';
                  final detalle = cancelado
                      ? 'Este aviso dejó de ser necesario porque no hay una revisión pendiente asociada.'
                      : listoParaAtender
                          ? 'La fecha del aviso fue alcanzada. Atiende la revisión para registrar una nueva fotografía.'
                          : '${cuentaRegresiva(a['vence_utc'], widget.registro.ahora())}. '
                              'Android mostrará el aviso en la fecha programada.';
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.12),
                                child: Icon(
                                    listoParaAtender
                                        ? Icons.notifications_active_outlined
                                        : Icons.notifications_outlined,
                                    color: color)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(titulo,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(detalle,
                                      style: const TextStyle(
                                          color: Color(0xFF52635D))),
                                  const SizedBox(height: 7),
                                  Text(
                                      'Programado para ${fechaLocal(a['vence_utc'])}',
                                      style: TextStyle(
                                          color: color,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ])),
                          ]),
                    ),
                  );
                }),
              _encabezadoSeccion(context, Icons.history_rounded,
                  'Historial de consultas', consultas.length),
              if (consultas.isEmpty)
                _estadoVacio(Icons.image_search_outlined,
                    'Aún no hay fotografías analizadas en esta instalación.'),
              for (final q in consultas)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(q['imagen'] as String),
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              const SizedBox(
                                  width: 54,
                                  height: 54,
                                  child: Icon(Icons.broken_image)),
                        )),
                    title: Text(cultivoVisible(q['cultivo']),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${fechaLocal(q['fecha_utc'])}\n'
                        'Puntuación: ${(q['score'] as num).toStringAsPrecision(17)}'),
                    isThreeLine: true,
                    trailing: _etiquetaEstado(
                        q['clase'] == 1 ? 'Positivo' : 'Sano',
                        color: q['clase'] == 1
                            ? const Color(0xFFB42318)
                            : _verdeSeguimiento),
                    onTap: q['caso_id'] == null
                        ? null
                        : () => widget.onCaso(q['caso_id'] as String),
                  ),
                ),
            ],
          );
        },
      );
}

class CasoDetalle extends StatefulWidget {
  const CasoDetalle({
    super.key,
    required this.registro,
    required this.casoId,
    required this.onAtender,
  });
  final Registro registro;
  final String? casoId;
  final void Function(String revisionId, String casoId, Cultivo cultivo)
      onAtender;
  @override
  State<CasoDetalle> createState() => _CasoDetalleState();
}

class _CasoDetalleState extends State<CasoDetalle> {
  @override
  Widget build(BuildContext context) {
    final id = widget.casoId;
    if (id == null)
      return const Center(child: Text('Selecciona un seguimiento.'));
    return FutureBuilder(
      future: Future.wait([
        widget.registro.casos(),
        widget.registro.revisiones(id),
        widget.registro.consultasCaso(id),
      ]),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Text('No se pudo abrir el caso: ${snapshot.error}'),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final cases = snapshot.data![0].where((c) => c['id'] == id);
        if (cases.isEmpty)
          return const Center(child: Text('Caso no encontrado.'));
        final c = cases.first;
        final cultivo = Cultivo.values.firstWhere(
          (v) => v.clave == c['cultivo'],
        );
        final revisiones = snapshot.data![1];
        final consultas = snapshot.data![2];
        final apertura = consultas.isEmpty ? null : consultas.last;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Seguimiento · ${cultivo.titulo}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('Estado del caso: ${estadoCasoVisible(c['estado'])}'),
            Text(
              'Resultado que abrió el caso: ${apertura?['clase'] == 1 ? 'Positivo' : 'No disponible'}',
            ),
            Text(
              'Fecha de la consulta inicial: ${fechaLocal(apertura?['fecha_utc'] ?? c['creado_utc'])}',
            ),
            Text(plazoVisible(c['cultivo'])),
            const Text(
              'Cerrar el seguimiento no confirma recuperación fitosanitaria.',
            ),
            const SizedBox(height: 12),
            Text(
              'Revisiones del caso (${revisiones.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final r in revisiones)
              Card(
                child: ListTile(
                  title: Text(
                    revisionVencida(r, widget.registro.ahora())
                        ? 'Revisión pendiente vencida'
                        : estadoRevisionVisible(r['estado']),
                  ),
                  subtitle: Text(
                    'Creada: ${fechaLocal(r['creado_utc'])}'
                    '${r['creado_fuente'] == 'reconstruido' ? ' (fecha reconstruida)' : ''}\n'
                    'Programada para ${fechaLocal(r['vence_utc'])}\n'
                    '${r['atendida_utc'] == null ? 'Estado: Pendiente' : 'Atendida: ${fechaLocal(r['atendida_utc'])}'}',
                  ),
                  isThreeLine: true,
                  trailing: r['estado'] == 'pendiente'
                      ? FilledButton(
                          onPressed: () =>
                              widget.onAtender(r['id'] as String, id, cultivo),
                          child: const Text('Atender revisión'),
                        )
                      : null,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Historial del caso',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final q in consultas)
              Card(
                child: ListTile(
                  leading: Image.file(
                    File(q['imagen'] as String),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        const Icon(Icons.broken_image),
                  ),
                  title: Text(q['clase'] == 1 ? cultivo.enfermedad : 'Sano'),
                  subtitle: Text(
                    '${fechaLocal(q['fecha_utc'])}\n'
                    'Puntuación: ${(q['score'] as num).toStringAsPrecision(17)}',
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        );
      },
    );
  }
}
