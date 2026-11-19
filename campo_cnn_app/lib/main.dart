import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'domain.dart';
import 'medicion.dart';
import 'preprocesamiento.dart';
import 'registro.dart';
import 'avisos.dart';
import 'consultas.dart';
import 'flujo.dart';
import 'diagnostico_motor.dart';

void main() => runApp(const CampoApp());

class CampoApp extends StatelessWidget {
  const CampoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Campo CNN', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF16765C),
      scaffoldBackgroundColor: const Color(0xFFF5F7F2),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF5F7F2))),
    home: const Inicio(),
  );
}

class Inicio extends StatefulWidget {
  const Inicio({super.key, this.registroInicial, this.avisosFactory,
    this.recuperarPerdida, this.antesIniciar});
  final Registro? registroInicial;
  final Avisos Function(Registro, void Function(String))? avisosFactory;
  final Future<LostDataResponse> Function()? recuperarPerdida;
  final Future<void> Function()? antesIniciar;
  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> with WidgetsBindingObserver {
  final flujo = ControlFlujo();
  int pagina = 0;
  late final registro = widget.registroInicial ?? Registro();
  late final avisos = widget.avisosFactory?.call(registro, _abrirAviso) ??
    Avisos(registro, _abrirAviso);
  bool listo = false;
  bool iniciando = false;
  String? errorInicio;
  LostDataResponse? _perdidaPendiente;
  String? casoAbierto;
  SeleccionPendiente? recuperada;
  String? recuperadaRuta;
  bool avisosIniciados = false;
  void _abrirAviso(String payload) {
    final destino = flujo.abrirDestino(payload);
    if (destino != null && mounted) _navegarAviso(destino);
  }
  void _navegarAviso(String payload) {
    setState(() {
      if (payload.startsWith('caso:')) {
        casoAbierto = payload.substring(5);
        pagina = 5;
      } else if (payload == 'pendientes') {
        casoAbierto = null;
        pagina = 4;
      }
    });
  }
  void _finalizarOperacion() {
    setState(() => flujo.finalizar());
    final destino = flujo.consumirDestino();
    if (destino != null) _navegarAviso(destino);
  }
  void _cancelarRevision() {
    if (flujo.cancelarRevision()) {
      setState(() { recuperada = null; recuperadaRuta = null; });
      final destino = flujo.consumirDestino();
      if (destino != null) _navegarAviso(destino);
    }
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _iniciar();
  }
  Future<void> _iniciar() async {
    if (iniciando) return;
    setState(() { iniciando = true; listo = false; errorInicio = null; });
    try {
      await widget.antesIniciar?.call();
      await registro.actividad('apertura');
      await registro.recuperarHuerfanos();
      final perdida = _perdidaPendiente ??=
        await (widget.recuperarPerdida?.call() ?? ImagePicker().retrieveLostData());
      final seleccion = await registro.seleccionPendiente();
      if (perdida.isEmpty || perdida.files == null || perdida.files!.isEmpty) {
        if (seleccion != null) await registro.cerrarSeleccion(seleccion.id);
        if (perdida.exception != null && mounted) {
          _mensaje('No se pudo recuperar la fotografía: ${perdida.exception}');
        }
      } else if (seleccion != null && await registro.consultaPorIntento(seleccion.id) == null) {
        if (mounted) {
          setState(() {
            recuperada = seleccion;
            recuperadaRuta = perdida.files!.first.path;
            if (seleccion.casoId != null && seleccion.revisionId != null) {
              flujo.seleccionarRevision(ContextoRevision(
                seleccion.casoId!, seleccion.revisionId!, seleccion.cultivo));
            } else {
              flujo.cambiarCultivo(seleccion.cultivo);
            }
            pagina = 1;
          });
        }
      } else {
        if (seleccion != null) await registro.cerrarSeleccion(seleccion.id);
        if (mounted) _mensaje('La fotografía recuperada no tiene una revisión pendiente válida.');
      }
      await avisos.iniciar();
      avisosIniciados = true;
      final resumen = await avisos.reconciliar();
      if (!mounted) return;
      setState(() { listo = true; iniciando = false; _perdidaPendiente = null; });
      if (resumen.requiereAtencion && mounted) _mensaje(resumen.mensaje);
    } catch (e) {
      if (mounted) {
        setState(() {
          iniciando = false;
          errorInicio = 'No se pudo iniciar Campo CNN: $e';
        });
      }
    }
  }
  Future<void> _reanudar() async {
    if (!listo) return;
    try {
      await registro.actividad('reanudacion');
      if (avisosIniciados) {
        await avisos.refrescarPermiso();
        final resumen = await avisos.reconciliar();
        if (resumen.requiereAtencion && mounted) _mensaje(resumen.mensaje);
      }
    } catch (e) { if (mounted) _mensaje('No se pudieron actualizar los avisos: $e'); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reanudar();
  }
  void _mensaje(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    registro.cerrar();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [Icon(Icons.eco_outlined), SizedBox(width: 10), Text('Campo CNN')]),
      actions: [Padding(padding: const EdgeInsets.only(right: 14), child: Chip(
        label: Text(flujo.cultivo.titulo), avatar: const Icon(Icons.grass, size: 17)))]),
    body: !listo ? Center(child: errorInicio == null
      ? const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(), SizedBox(height: 16), Text('Iniciando Campo CNN…')])
      : Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(20), child: Text(errorInicio!)),
          FilledButton(onPressed: iniciando ? null : _iniciar,
            child: const Text('Reintentar'))]))
      : SafeArea(child: IndexedStack(index: pagina, children: [
      PanelInicio(cultivo: flujo.cultivo, onCultivo: (v) {
        if (flujo.cambiarCultivo(v)) { setState(() {}); }
        else { _mensaje('Termina o cancela la revisión antes de cambiar de cultivo.'); }
      }, abrir: (n) { if (!flujo.ocupado) setState(() => pagina = n); }),
      Diagnostico(key: ValueKey('diag_${flujo.cultivo.clave}'),
        cultivo: flujo.cultivo, registro: registro, avisos: avisos,
        contexto: flujo.revision, recuperada: recuperada, recuperadaRuta: recuperadaRuta,
        onIniciar: () { final ok = flujo.iniciar(); if (ok) setState(() {}); return ok; },
        onFinalizar: _finalizarOperacion,
        onConfirmado: () => setState(() => flujo.confirmar()),
        onCancelar: _cancelarRevision,
        onRecuperada: () => setState(() { recuperada = null; recuperadaRuta = null; }),
        onGuardado: () => setState(() { casoAbierto = null; pagina = 4; })),
      Rendimiento(key: ValueKey('bench_${flujo.cultivo.clave}'), cultivo: flujo.cultivo),
      const Historial(),
      Consultas(registro: registro, onCaso: (id) => setState(() { casoAbierto = id; pagina = 5; })),
      CasoDetalle(key: ValueKey(casoAbierto), registro: registro, casoId: casoAbierto,
        onAtender: (id, caseId, crop) {
          if (flujo.seleccionarRevision(ContextoRevision(caseId, id, crop))) {
            setState(() => pagina = 1);
          }
        }),
    ])),
    bottomNavigationBar: !listo ? null : NavigationBar(selectedIndex: pagina > 4 ? 4 : pagina,
      onDestinationSelected: (n) {
        if (flujo.ocupado || (flujo.revision != null && n != 1)) {
          _mensaje('Termina o cancela la revisión antes de salir.');
          return;
        }
        setState(() => pagina = n);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Inicio'),
        NavigationDestination(icon: Icon(Icons.document_scanner_outlined), label: 'Diagnóstico'),
        NavigationDestination(icon: Icon(Icons.speed_outlined), label: 'Medición'),
        NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
        NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Consultas'),
      ]),
  );
}

class PanelInicio extends StatelessWidget {
  const PanelInicio({super.key, required this.cultivo, required this.onCultivo, required this.abrir});
  final Cultivo cultivo;
  final ValueChanged<Cultivo> onCultivo;
  final ValueChanged<int> abrir;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const SizedBox(height: 15),
    Text('Diagnóstico en campo', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Dos CNN locales · funcionamiento sin conexión · registro de evidencias'),
    const SizedBox(height: 22),
    Text('Cultivo', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    SegmentedButton<Cultivo>(segments: const [
      ButtonSegment(value: Cultivo.arroz, label: Text('Arroz')),
      ButtonSegment(value: Cultivo.cana, label: Text('Caña'))],
      selected: {cultivo}, onSelectionChanged: (v) => onCultivo(v.first)),
    const SizedBox(height: 18),
    _tarjeta(context, Icons.image_search, 'Consultar una fotografía',
      'Resultado local con umbral fijado en validación. La concordancia del preprocesamiento móvil debe comprobarse.',
      'Abrir diagnóstico', () => abrir(1)),
    const SizedBox(height: 12),
    _tarjeta(context, Icons.query_stats, 'Medir rendimiento',
      '${cultivo.cantidadTest} fotografías de test · 20 calentamientos · CPU, 1 hilo · tiempo de inferencia por imagen.',
      'Abrir medición', () => abrir(2)),
    const SizedBox(height: 12),
    _tarjeta(context, Icons.folder_copy_outlined, 'Conservar evidencia',
      'Resultados por imagen, resumen, dispositivo y archivos para la tesis.',
      'Ver historial', () => abrir(3)),
    const SizedBox(height: 20),
    Text('Modelo ${cultivo.titulo}: ${cultivo.bytes} bytes · Float32 sin cuantización',
      style: Theme.of(context).textTheme.bodySmall),
  ]);
}

Widget _tarjeta(BuildContext c, IconData icono, String titulo, String descripcion,
    String accion, VoidCallback onTap) => Card(child: Padding(padding: const EdgeInsets.all(18),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icono, size: 30, color: Theme.of(c).colorScheme.primary), const SizedBox(height: 12),
    Text(titulo, style: Theme.of(c).textTheme.titleLarge), const SizedBox(height: 5),
    Text(descripcion), const SizedBox(height: 10),
    TextButton.icon(onPressed: onTap, icon: const Icon(Icons.arrow_forward), label: Text(accion)),
  ])));

class Diagnostico extends StatefulWidget {
  const Diagnostico({super.key, required this.cultivo, required this.registro,
    required this.avisos, required this.onGuardado, required this.onIniciar,
    required this.onFinalizar, required this.onConfirmado,
    required this.onCancelar, required this.onRecuperada,
    this.contexto, this.recuperada, this.recuperadaRuta});
  final Cultivo cultivo;
  final Registro registro;
  final Avisos avisos;
  final ContextoRevision? contexto;
  final SeleccionPendiente? recuperada;
  final String? recuperadaRuta;
  final bool Function() onIniciar;
  final VoidCallback onFinalizar;
  final VoidCallback onConfirmado;
  final VoidCallback onCancelar;
  final VoidCallback onRecuperada;
  final VoidCallback onGuardado;
  @override
  State<Diagnostico> createState() => _DiagnosticoState();
}

class _DiagnosticoState extends State<Diagnostico> {
  File? foto;
  double? score;
  bool ocupado = false;
  String? error;
  String? consultaId;
  String? _recuperacionProcesada;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarRecuperacion());
  }

  @override
  void didUpdateWidget(covariant Diagnostico oldWidget) {
    super.didUpdateWidget(oldWidget);
    final anterior = oldWidget.contexto;
    final actual = widget.contexto;
    if (!ocupado && actual != null &&
        (anterior?.casoId != actual.casoId ||
         anterior?.revisionId != actual.revisionId ||
         anterior?.cultivo != actual.cultivo)) {
      foto = null;
      score = null;
      consultaId = null;
      error = null;
    }
    if (widget.recuperada != null &&
        _recuperacionProcesada != widget.recuperada?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revisarRecuperacion());
    }
  }

  void _revisarRecuperacion() {
    final selection = widget.recuperada;
    final path = widget.recuperadaRuta;
    if (!mounted || selection == null || path == null ||
        _recuperacionProcesada == selection.id) { return; }
    _recuperacionProcesada = selection.id;
    _usarRecuperada(File(path), selection);
  }

  Future<void> _usarRecuperada(File file, SeleccionPendiente selection) async {
    if (!widget.onIniciar()) {
      _recuperacionProcesada = null;
      return;
    }
    setState(() { ocupado = true; error = null; score = null; foto = null; });
    try { await _procesar(file, selection); }
    catch (e) {
      await widget.registro.cerrarSeleccion(selection.id);
      if (mounted) setState(() => error = 'No se pudo recuperar la fotografía: $e');
    } finally {
      widget.onRecuperada();
      widget.onFinalizar();
      if (mounted) setState(() => ocupado = false);
    }
  }

  Future<void> _elegir(ImageSource origen) async {
    if (ocupado || !widget.onIniciar()) return;
    setState(() { ocupado = true; error = null; foto = null; score = null; consultaId = null; });
    SeleccionPendiente? seleccion;
    try {
      final contexto = widget.contexto;
      seleccion = await widget.registro.prepararSeleccion(widget.cultivo,
        casoId: contexto?.casoId, revisionId: contexto?.revisionId);
      final picked = await ImagePicker().pickImage(source: origen);
      if (picked == null) {
        await widget.registro.cerrarSeleccion(seleccion.id);
        return;
      }
      await _procesar(File(picked.path), seleccion);
    } catch (e) {
      if (seleccion != null) await widget.registro.cerrarSeleccion(seleccion.id);
      if (mounted) setState(() => error = '$e');
    } finally {
      widget.onFinalizar();
      if (mounted) setState(() => ocupado = false);
    }
  }

  Future<void> _procesar(File selected, SeleccionPendiente seleccion) async {
    final bytes = await compute(PreparadorImagen.preparar, await selected.readAsBytes());
    final resultado = await MotorDiagnostico.inferir(seleccion.cultivo, bytes);
    final id = await widget.registro.guardar(cultivo: seleccion.cultivo,
      origen: selected, score: resultado, casoId: seleccion.casoId,
      revisionId: seleccion.revisionId, intentoId: seleccion.id);
    widget.onConfirmado();
    String? avisoError;
    try {
      final resumen = await widget.avisos.reconciliar();
      if (resumen.requiereAtencion) avisoError = resumen.mensaje;
    } catch (e) { avisoError = 'Consulta guardada. No se pudieron actualizar los avisos: $e'; }
    if (mounted) {
      setState(() { foto = selected; score = resultado;
        consultaId = id; error = avisoError; });
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Diagnóstico · ${widget.cultivo.titulo}',
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Selecciona una imagen de la galería o toma una fotografía.'),
    if (widget.contexto != null) Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Row(children: [Expanded(child: Text(
          'Atendiendo revisión ${widget.contexto!.revisionId} del caso ${widget.contexto!.casoId}.')),
        TextButton(onPressed: ocupado ? null : () {
          setState(() { foto = null; score = null; consultaId = null; error = null; });
          widget.onCancelar();
        },
          child: const Text('Cancelar revisión'))]))),
    const SizedBox(height: 16),
    Wrap(spacing: 8, children: [
      FilledButton.icon(onPressed: ocupado ? null : () => _elegir(ImageSource.camera),
        icon: const Icon(Icons.camera_alt_outlined), label: const Text('Cámara')),
      OutlinedButton.icon(onPressed: ocupado ? null : () => _elegir(ImageSource.gallery),
        icon: const Icon(Icons.photo_library_outlined), label: const Text('Galería')),
    ]),
    if (ocupado) const Padding(padding: EdgeInsets.all(18), child: LinearProgressIndicator()),
    if (foto != null) Padding(padding: const EdgeInsets.symmetric(vertical: 14),
      child: ClipRRect(borderRadius: BorderRadius.circular(16),
        child: Image.file(foto!, height: 250, fit: BoxFit.cover))),
    if (score != null) Card(child: Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(score! >= widget.cultivo.umbral ? widget.cultivo.enfermedad : 'Sano',
          style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('Puntuación del modelo: ${score!.toStringAsPrecision(17)}'),
        Text('Umbral: ${widget.cultivo.umbral.toStringAsFixed(6)}'),
        const Text('Resultado de esta fotografía; no confirma el patógeno ni describe toda la parcela.'),
        if (consultaId != null) Text('Consulta guardada: $consultaId'),
        if (consultaId != null) TextButton(onPressed: ocupado ? null : widget.onGuardado,
          child: const Text('Ver consultas y seguimientos')),
      ]))),
    if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const SizedBox(height: 16),
    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text(
      'La concordancia numérica con las imágenes originales de validación sigue pendiente de comprobar.'))),
  ]);
}

class Rendimiento extends StatefulWidget {
  const Rendimiento({super.key, required this.cultivo});
  final Cultivo cultivo;
  @override
  State<Rendimiento> createState() => _RendimientoState();
}

class _RendimientoState extends State<Rendimiento> {
  PaquetePrueba? paquete;
  bool ocupado = false;
  int hecho = 0;
  String? error;
  Resumen? resultado;
  File? guardado;

  Future<void> _importar() async {
    setState(() { error = null; paquete = null; resultado = null; });
    try {
      // Algunos gestores Android no reconocen el MIME de .cbm.
      final elegido = await FilePicker.platform.pickFiles(type: FileType.any,
        withData: false);
      if (elegido == null) return;
      final path = elegido.files.single.path;
      if (path == null || !elegido.files.single.name.toLowerCase().endsWith('.cbm')) {
        throw StateError('Selecciona un paquete .cbm guardado en el teléfono.');
      }
      final p = await PaquetePrueba.abrir(File(path), widget.cultivo);
      if (mounted) setState(() => paquete = p);
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }

  Future<void> _medir() async {
    final p = paquete;
    if (p == null) return;
    setState(() { ocupado = true; hecho = 0; error = null; resultado = null; guardado = null; });
    try {
      final r = await Medidor.ejecutar(p, (n, _) { if (mounted) setState(() => hecho = n); });
      final f = await ArchivoResultados.guardar(r);
      if (mounted) setState(() { resultado = r; guardado = f; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => ocupado = false); }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Medición · ${widget.cultivo.titulo}',
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Text('CPU · 1 hilo · $calentamientos calentamientos · ${widget.cultivo.cantidadTest} inferencias medidas'),
    const SizedBox(height: 16),
    _tarjeta(context, Icons.inventory_2_outlined, 'Paquete de prueba',
      paquete == null ? 'Genera el archivo .cbm en Colab con el cuaderno incluido.'
        : '${paquete!.items.length} tensores verificados por inventario · ${paquete!.archivo.path.split('/').last}',
      'Seleccionar .cbm', ocupado ? () {} : _importar),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: paquete == null || ocupado ? null : _medir,
      icon: const Icon(Icons.play_arrow), label: const Text('Iniciar medición completa')),
    if (ocupado) Padding(padding: const EdgeInsets.symmetric(vertical: 15),
      child: Column(children: [LinearProgressIndicator(value: hecho / widget.cultivo.cantidadTest),
        Text('$hecho / ${widget.cultivo.cantidadTest} imágenes')])),
    if (resultado != null) Card(child: Padding(padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Medición completa', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Media: ${resultado!.media.toStringAsFixed(3)} ms'),
        Text('Desviación estándar: ${resultado!.desviacion.toStringAsFixed(3)} ms'),
        Text('Mediana: ${resultado!.mediana.toStringAsFixed(3)} ms'),
        Text('Máxima diferencia de puntuación con Colab: ${resultado!.desviacionMaxima.toStringAsExponential(2)}'),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: guardado == null ? null : () async {
          final csv = await ArchivoResultados.csv(guardado!);
          await Share.shareXFiles([XFile(guardado!.path), XFile(csv.path)],
            text: 'Medición ${widget.cultivo.titulo}');
        }, icon: const Icon(Icons.ios_share), label: const Text('Exportar JSON y CSV')),
      ]))),
    if (error != null) Card(child: Padding(padding: const EdgeInsets.all(16),
      child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
    const SizedBox(height: 12),
    const Text('La medición se invalida si falta una imagen, cambia un tensor o discrepa una predicción con Colab. Usa siempre el mismo teléfono y una compilación profile o release.'),
  ]);
}

class Historial extends StatefulWidget {
  const Historial({super.key});
  @override
  State<Historial> createState() => _HistorialState();
}

class _HistorialState extends State<Historial> {
  @override
  Widget build(BuildContext context) => FutureBuilder<List<File>>(
    future: ArchivoResultados.listar(), builder: (context, snapshot) {
      final archivos = snapshot.data ?? [];
      return ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [Expanded(child: Text('Historial', style: Theme.of(context).textTheme.headlineSmall)),
          IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh))]),
        const SizedBox(height: 8),
        if (archivos.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20),
          child: Text('Todavía no hay mediciones guardadas.'))),
        for (final f in archivos) FutureBuilder<String>(future: f.readAsString(),
          builder: (context, state) {
            if (!state.hasData) return const ListTile(title: Text('Cargando…'));
            final j = jsonDecode(state.data!) as Map<String, dynamic>;
            return Card(child: ListTile(
              title: Text('${j['cultivo']} · ${(j['media_ms'] as num).toStringAsFixed(3)} ms'),
              subtitle: Text('${j['fecha_utc']}\n${j['dispositivo']} · ${j['mediciones']} imágenes'),
              isThreeLine: true,
              trailing: IconButton(icon: const Icon(Icons.ios_share), onPressed: () async {
                final csv = await ArchivoResultados.csv(f);
                await Share.shareXFiles([XFile(f.path), XFile(csv.path)]);
              }),
            ));
          }),
      ]);
    });
}
