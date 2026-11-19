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
  !DateTime.parse(revision['vence_utc'] as String).toUtc()
    .isAfter(ahora.toUtc());

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
  Future<void> _exportar(List<Map<String, Object?>> rows) async {
    if (exportando) return;
    setState(() { exportando = true; errorExportacion = null; });
    try {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final json = File('${dir.path}/consultas_$stamp.json');
    final csv = File('${dir.path}/consultas_$stamp.csv');
    await json.writeAsString(const JsonEncoder.withIndent('  ').convert(rows));
    String cell(Object? value) => '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final columns = ['id', 'fecha_utc', 'cultivo', 'clase', 'score', 'umbral',
      'modelo_sha256', 'imagen', 'caso_id', 'revision_id'];
    await csv.writeAsString([
      columns.join(','),
      for (final row in rows) columns.map((c) => cell(row[c])).join(','),
    ].join('\n'));
    await Share.shareXFiles([XFile(json.path), XFile(csv.path)],
      text: 'Consultas Campo CNN');
    } catch (e) {
      if (mounted) setState(() => errorExportacion = 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => exportando = false);
    }
  }
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: Future.wait([widget.registro.consultas(), widget.registro.casos(),
      widget.registro.pendientes(), widget.registro.avisos()]),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('No se pudo abrir el historial: ${snapshot.error}'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final consultas = snapshot.data![0];
      final casos = snapshot.data![1];
      final pendientes = snapshot.data![2];
      final avisosConProblema = snapshot.data![3].where((a) =>
        a['estado'] == 'permiso_denegado' || a['estado'] == 'fallo_programacion' ||
        a['estado'] == 'vencido_sin_entrega_verificada').toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [Expanded(child: Text('Consultas y seguimientos',
          style: Theme.of(context).textTheme.headlineSmall)),
          IconButton(onPressed: exportando ? null : () => _exportar(consultas), icon: const Icon(Icons.ios_share),
            tooltip: 'Exportar puntuaciones completas'),
          IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh))]),
        if (exportando) const LinearProgressIndicator(),
        if (errorExportacion != null) Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Text(errorExportacion!))),
        if (avisosConProblema.isNotEmpty) Card(child: Padding(
          padding: const EdgeInsets.all(12), child: Text(
            '${avisosConProblema.length} avisos requieren atención. '
            'Comprueba los permisos de Android y las revisiones pendientes. '
            'Una fecha vencida no confirma que el aviso haya llegado.'))),
        Text('Revisiones pendientes (${pendientes.length})',
          style: Theme.of(context).textTheme.titleLarge),
        for (final r in pendientes) Card(child: ListTile(
          title: Text(revisionVencida(r, widget.registro.ahora())
            ? 'Revisión pendiente vencida' : 'Revisión pendiente'),
          subtitle: Text('Para ${fechaLocal(r['vence_utc'])}'),
          onTap: () => widget.onCaso(r['caso_id'] as String))),
        const SizedBox(height: 16),
        Text('Seguimientos (${casos.length})', style: Theme.of(context).textTheme.titleLarge),
        for (final c in casos) Card(child: ListTile(
          title: Text('${c['cultivo']} · ${c['estado']}'),
          subtitle: Text(fechaLocal(c['creado_utc'])),
          onTap: () => widget.onCaso(c['id'] as String))),
        const SizedBox(height: 16),
        Text('Historial de consultas (${consultas.length})',
          style: Theme.of(context).textTheme.titleLarge),
        for (final q in consultas) Card(child: ListTile(
          leading: Image.file(File(q['imagen'] as String), width: 48, height: 48,
            fit: BoxFit.cover, errorBuilder: (context, error, stack) => const Icon(Icons.broken_image)),
          title: Text('${q['cultivo']} · ${q['clase'] == 1 ? 'Positivo' : 'Sano'}'),
          subtitle: Text('${fechaLocal(q['fecha_utc'])}\nPuntuación: ${(q['score'] as num).toStringAsPrecision(17)}'),
          isThreeLine: true,
          onTap: q['caso_id'] == null ? null : () => widget.onCaso(q['caso_id'] as String))),
      ]);
    });
}

class CasoDetalle extends StatefulWidget {
  const CasoDetalle({super.key, required this.registro, required this.casoId,
    required this.onAtender});
  final Registro registro;
  final String? casoId;
  final void Function(String revisionId, String casoId, Cultivo cultivo) onAtender;
  @override
  State<CasoDetalle> createState() => _CasoDetalleState();
}

class _CasoDetalleState extends State<CasoDetalle> {
  @override
  Widget build(BuildContext context) {
    final id = widget.casoId;
    if (id == null) return const Center(child: Text('Selecciona un seguimiento.'));
    return FutureBuilder(future: Future.wait([
      widget.registro.casos(), widget.registro.revisiones(id),
      widget.registro.consultasCaso(id)]),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('No se pudo abrir el caso: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final cases = snapshot.data![0].where((c) => c['id'] == id);
        if (cases.isEmpty) return const Center(child: Text('Caso no encontrado.'));
        final c = cases.first;
        final cultivo = Cultivo.values.firstWhere((v) => v.clave == c['cultivo']);
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Seguimiento · ${cultivo.titulo}',
            style: Theme.of(context).textTheme.headlineSmall),
          Text('Estado: ${c['estado']} · creado: ${fechaLocal(c['creado_utc'])}'),
          const Text('Cerrar el seguimiento no confirma recuperación fitosanitaria.'),
          const SizedBox(height: 12),
          for (final r in snapshot.data![1]) Card(child: ListTile(
            title: Text(revisionVencida(r, widget.registro.ahora())
              ? 'Revisión pendiente vencida' : 'Revisión ${r['estado']}'),
            subtitle: Text('Creada: ${fechaLocal(r['creado_utc'])}'
              '${r['creado_fuente'] == 'reconstruido' ? ' (fecha reconstruida)' : ''}\n'
              'Programada para ${fechaLocal(r['vence_utc'])}\n'
              '${r['atendida_utc'] == null ? '' : 'Atendida: ${fechaLocal(r['atendida_utc'])}'}'),
            isThreeLine: true,
            trailing: r['estado'] == 'pendiente' ? FilledButton(
              onPressed: () => widget.onAtender(r['id'] as String, id, cultivo),
              child: const Text('Atender')) : null)),
          const SizedBox(height: 16),
          Text('Fotografías y consultas del caso',
            style: Theme.of(context).textTheme.titleLarge),
          for (final q in snapshot.data![2]) Card(child: ListTile(
            leading: Image.file(File(q['imagen'] as String), width: 64, height: 64,
              fit: BoxFit.cover, errorBuilder: (context, error, stack) =>
                const Icon(Icons.broken_image)),
            title: Text(q['clase'] == 1 ? cultivo.enfermedad : 'Sano'),
            subtitle: Text('${fechaLocal(q['fecha_utc'])}\n'
              'Puntuación: ${(q['score'] as num).toStringAsPrecision(17)}'),
            isThreeLine: true)),
        ]);
      });
  }
}
