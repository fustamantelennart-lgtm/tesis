import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

enum Cultivo { arroz, cana }

extension CultivoInfo on Cultivo {
  String get titulo => this == Cultivo.arroz ? 'Arroz' : 'Caña de azúcar';
  String get clave => this == Cultivo.arroz ? 'arroz' : 'cana';
  String get enfermedad => this == Cultivo.arroz ? 'Piricularia' : 'Roya';
  String get asset => this == Cultivo.arroz ? 'assets/arroz.tflite' : 'assets/cana.tflite';
  int get cantidadTest => this == Cultivo.arroz ? 219 : 412;
  double get umbral => this == Cultivo.arroz
      ? 0.6501769423484802 : 0.6862450242042542;
  String get sha => this == Cultivo.arroz
      ? '0728e2ddedc0db0959870ef420c204df3094fd780ef520c0d3fb2b10a9090040'
      : '9042f0dffc63a6c143fd64a8d36a34ab25bc96cb74b21e51df35d7e88a368bec';
  int get bytes => this == Cultivo.arroz ? 427936 : 427880;
}

const int tensorBytes = 224 * 224 * 3 * 4;
const String preprocesamiento = 'rgb_exif_tf_bilinear_pad_224_div255_v1';
const int calentamientos = 20;

class Motor {
  Motor(this.cultivo, this.interprete);
  final Cultivo cultivo;
  final Interpreter interprete;

  static Future<Motor> abrir(Cultivo cultivo) async {
    final bytes = (await rootBundle.load(cultivo.asset)).buffer.asUint8List();
    if (bytes.length != cultivo.bytes || sha256.convert(bytes).toString() != cultivo.sha) {
      throw StateError('La huella del modelo ${cultivo.titulo} no coincide.');
    }
    final opciones = InterpreterOptions()..threads = 1;
    final interprete = Interpreter.fromBuffer(bytes, options: opciones);
    final entrada = interprete.getInputTensor(0);
    final salida = interprete.getOutputTensor(0);
    if (entrada.type != TensorType.float32 ||
        entrada.shape.join(',') != '1,224,224,3' ||
        salida.type != TensorType.float32 || salida.shape.join(',') != '1,1') {
      interprete.close();
      throw StateError('Forma o tipo de tensor incompatible.');
    }
    return Motor(cultivo, interprete);
  }

  double inferir(Uint8List tensor) {
    if (tensor.length != tensorBytes) throw FormatException('Tensor incompleto.');
    final salida = <List<double>>[[0.0]];
    interprete.run(tensor, salida);
    final score = salida[0][0];
    if (!score.isFinite || score < 0 || score > 1) {
      throw StateError('La salida del modelo está fuera de [0, 1].');
    }
    return score;
  }

  void cerrar() => interprete.close();
}

class ItemPrueba {
  ItemPrueba(this.archivo, this.etiqueta, this.shaTensor, this.scoreReferencia);
  final String archivo;
  final int etiqueta;
  final String shaTensor;
  final double scoreReferencia;
  factory ItemPrueba.fromJson(Map<String, dynamic> j) => ItemPrueba(
    j['archivo'] as String, j['etiqueta'] as int,
    j['sha256_tensor'] as String, (j['score_referencia'] as num).toDouble());
}

class PaquetePrueba {
  PaquetePrueba(this.archivo, this.cultivo, this.items, this.offset);
  final File archivo;
  final Cultivo cultivo;
  final List<ItemPrueba> items;
  final int offset;

  static Future<PaquetePrueba> abrir(File archivo, Cultivo cultivo) async {
    final f = await archivo.open();
    try {
      final inicio = await f.read(12);
      if (inicio.length != 12 || ascii.decode(inicio.sublist(0, 8)) != 'CBENCH1\n') {
        throw FormatException('Formato de paquete no reconocido.');
      }
      final n = ByteData.sublistView(Uint8List.fromList(inicio), 8).getUint32(0, Endian.little);
      if (n < 20 || n > 1000000) throw FormatException('Cabecera demasiado grande.');
      final cabecera = await f.read(n);
      if (cabecera.length != n) throw FormatException('Cabecera incompleta.');
      final j = jsonDecode(utf8.decode(cabecera)) as Map<String, dynamic>;
      if (j['schema'] != 1 || j['cultivo'] != cultivo.clave ||
          j['particion'] != 'test' || j['modelo_sha256'] != cultivo.sha ||
          j['preprocesamiento'] != preprocesamiento ||
          (j['umbral'] as num?)?.toDouble() != cultivo.umbral ||
          j['tensor_bytes'] != tensorBytes) {
        throw FormatException('Este paquete no corresponde al modelo o al protocolo.');
      }
      final items = (j['items'] as List).map((e) => ItemPrueba.fromJson(
        Map<String, dynamic>.from(e as Map))).toList();
      if (items.length != cultivo.cantidadTest ||
          items.map((e) => e.archivo).toSet().length != items.length ||
          items.any((e) => !e.archivo.startsWith('test/') ||
            (e.etiqueta != 0 && e.etiqueta != 1) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(e.shaTensor) ||
            !e.scoreReferencia.isFinite)) {
        throw FormatException('Inventario de test inválido o incompleto.');
      }
      final offset = 12 + n;
      if (await f.length() != offset + items.length * tensorBytes) {
        throw FormatException('El tamaño del paquete no coincide con su inventario.');
      }
      return PaquetePrueba(archivo, cultivo, items, offset);
    } finally {
      await f.close();
    }
  }
}

class Medida {
  Medida(this.archivo, this.etiqueta, this.score, this.referencia, this.ms);
  final String archivo;
  final int etiqueta;
  final double score;
  final double referencia;
  final double ms;
  int prediccion(double umbral) => score >= umbral ? 1 : 0;
  Map<String, dynamic> toJson(double umbral) => {
    'archivo': archivo, 'etiqueta': etiqueta, 'score_android': score,
    'score_colab': referencia, 'prediccion': prediccion(umbral), 'ms': ms};
}

class Resumen {
  Resumen(this.cultivo, this.fecha, this.dispositivo, this.android,
      this.modo, this.medidas, this.desviacionMaxima);
  final Cultivo cultivo;
  final DateTime fecha;
  final String dispositivo;
  final String android;
  final String modo;
  final List<Medida> medidas;
  final double desviacionMaxima;

  List<double> get tiempos => medidas.map((e) => e.ms).toList()..sort();
  double get media => tiempos.reduce((a, b) => a + b) / tiempos.length;
  double get mediana { final v = tiempos; final n = v.length; return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2; }
  double get desviacion {
    final m = media;
    final suma = tiempos.fold<double>(0, (a, b) => a + (b - m) * (b - m));
    return math.sqrt(suma / (tiempos.length - 1));
  }
  Map<String, dynamic> toJson() => {
    'cultivo': cultivo.clave, 'fecha_utc': fecha.toUtc().toIso8601String(),
    'dispositivo': dispositivo, 'android': android, 'modo': modo,
    'procesador': 'CPU', 'hilos': 1, 'calentamientos': calentamientos,
    'mediciones': medidas.length, 'unidades': 'ms',
    'alcance': 'solo Interpreter.run; se excluyen lectura, tensor, interfaz y almacenamiento',
    'modelo_sha256': cultivo.sha, 'modelo_bytes': cultivo.bytes,
    'preprocesamiento': preprocesamiento, 'umbral': cultivo.umbral,
    'media_ms': media, 'desviacion_muestral_ms': desviacion,
    'mediana_ms': mediana, 'minimo_ms': tiempos.first, 'maximo_ms': tiempos.last,
    'desviacion_maxima_score': desviacionMaxima,
    'medidas': medidas.map((e) => e.toJson(cultivo.umbral)).toList(),
  };
}

