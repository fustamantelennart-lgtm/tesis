import 'dart:typed_data';

/// RGB intercalado de 8 bits, ya orientado.
class ImagenRgb {
  const ImagenRgb(this.ancho, this.alto, this.rgb);
  final int ancho;
  final int alto;
  final Uint8List rgb;
}

/// Decodificador JPEG con la aritmetica entera de libjpeg-turbo, la biblioteca
/// que usa Pillow 11.3.0 para generar las referencias de Colab:
/// Huffman secuencial/progresivo (jdhuff.c, jdphuff.c), IDCT ISLOW
/// (jidctint.c), upsampling "fancy" (jdsample.c), YCbCr->RGB (jdcolor.c) y
/// la orientacion de `ImageOps.exif_transpose`. Solo JPEG de 8 bits con
/// codificacion Huffman y 1 o 3 componentes.
class DecodificadorJpeg {
  static bool esJpeg(Uint8List bytes) =>
    bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  /// Decodifica el primer frame (como Pillow con MPO) y aplica [orientacion]
  /// EXIF 1..8; cualquier otro valor se trata como 1.
  static ImagenRgb decodificar(Uint8List bytes, {int orientacion = 1}) =>
    _Decodificacion(bytes).ejecutar(orientacion);
}

const _natural = <int>[
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
  12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
  // Entradas extra de libjpeg para datos corruptos.
  63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63, 63,
];

const _maxPixeles = 100000000;

Never _error(String detalle) => throw FormatException('JPEG no admitido: $detalle');

class _Huffman {
  _Huffman(Uint8List cuentas, this.valores) {
    // jpeg_make_d_derived_tbl: codigos canonicos por longitud.
    final codigos = <int>[];
    final longitudes = <int>[];
    var codigo = 0;
    for (var l = 1; l <= 16; l++) {
      for (var i = 0; i < cuentas[l - 1]; i++) {
        codigos.add(codigo++);
        longitudes.add(l);
      }
      if (codigos.isNotEmpty && codigo >= (1 << l)) _error('tabla Huffman invalida');
      codigo <<= 1;
    }
    if (codigos.length != valores.length) _error('tabla Huffman incompleta');
    var p = 0;
    for (var l = 1; l <= 16; l++) {
      final n = cuentas[l - 1];
      if (n > 0) {
        offset[l] = p - codigos[p];
        p += n;
        maximo[l] = codigos[p - 1];
      } else {
        maximo[l] = -1;
      }
    }
    maximo[17] = 0x7FFFFFFF;
    for (var i = 0; i < codigos.length; i++) {
      final l = longitudes[i];
      if (l > _bitsRapidos) continue;
      final inicio = codigos[i] << (_bitsRapidos - l);
      final fin = inicio + (1 << (_bitsRapidos - l));
      for (var j = inicio; j < fin; j++) {
        rapida[j] = (l << 8) | valores[i];
      }
    }
  }

  static const _bitsRapidos = 9;
  final Uint8List valores;
  final maximo = Int32List(18);
  final offset = Int32List(17);
  final rapida = Uint16List(1 << _bitsRapidos);
}

class _Componente {
  _Componente(this.id, this.h, this.v, this.tq);
  final int id;
  final int h;
  final int v;
  final int tq;
  late int anchoMuestras;
  late int altoMuestras;
  late int bloquesAncho;
  late int bloquesAlto;
  late int bloquesLineaMcu;
  late Int16List coeficientes;
  Int32List? cuantizacion;
  _Huffman? dc;
  _Huffman? ac;
  int previo = 0;
}

/// Lector de bits de jdhuff.c: al encontrar un marcador inserta ceros.
class _Bits {
  _Bits(this.datos, this.pos);
  final Uint8List datos;
  int pos;
  int acumulador = 0;
  int cantidad = 0;
  bool enMarcador = false;

  void _llenar() {
    while (cantidad <= 24) {
      var byte = 0;
      if (!enMarcador && pos < datos.length) {
        byte = datos[pos];
        if (byte == 0xFF) {
          final siguiente = pos + 1 < datos.length ? datos[pos + 1] : 0xD9;
          if (siguiente == 0) {
            pos += 2;
          } else {
            enMarcador = true;
            byte = 0;
          }
        } else {
          pos++;
        }
      } else {
        enMarcador = true;
      }
      acumulador = ((acumulador << 8) | byte) & 0xFFFFFFFFFFFF;
      cantidad += 8;
    }
  }

  int leer(int n) {
    if (n == 0) return 0;
    if (cantidad < n) _llenar();
    cantidad -= n;
    return (acumulador >> cantidad) & ((1 << n) - 1);
  }

  int bit() => leer(1);

  int decodificar(_Huffman tabla) {
    if (cantidad < 16) _llenar();
    final entrada = tabla.rapida[(acumulador >> (cantidad - _Huffman._bitsRapidos)) &
      ((1 << _Huffman._bitsRapidos) - 1)];
    if (entrada != 0) {
      cantidad -= entrada >> 8;
      return entrada & 0xFF;
    }
    var l = _Huffman._bitsRapidos + 1;
    var codigo = (acumulador >> (cantidad - l)) & ((1 << l) - 1);
    while (codigo > tabla.maximo[l]) {
      l++;
      if (l > 16) {
        // libjpeg advierte y devuelve 0 ante un codigo imposible.
        cantidad -= 16;
        return 0;
      }
      codigo = (acumulador >> (cantidad - l)) & ((1 << l) - 1);
    }
    cantidad -= l;
    final indice = tabla.offset[l] + codigo;
    return indice >= 0 && indice < tabla.valores.length ? tabla.valores[indice] : 0;
  }

  /// process_restart: descarta bits pendientes y consume RSTn si esta.
  void reiniciar() {
    acumulador = 0;
    cantidad = 0;
    enMarcador = false;
    while (pos < datos.length) {
      if (datos[pos] != 0xFF) { pos++; continue; }
      var p = pos;
      while (p < datos.length && datos[p] == 0xFF) { p++; }
      if (p >= datos.length) { pos = p; return; }
      final marcador = datos[p];
      if (marcador == 0) { pos = p + 1; continue; }
      if (marcador >= 0xD0 && marcador <= 0xD7) pos = p + 1;
      return;
    }
  }
}

int _extender(int valor, int s) =>
  s == 0 ? 0 : valor < (1 << (s - 1)) ? valor - (1 << s) + 1 : valor;

class _Decodificacion {
  _Decodificacion(this.datos);
  final Uint8List datos;
  int pos = 2;
  final cuantizacion = List<Int32List?>.filled(4, null);
  final tablasDc = List<_Huffman?>.filled(4, null);
  final tablasAc = List<_Huffman?>.filled(4, null);
  final componentes = <_Componente>[];
  int intervalo = 0;
  bool jfif = false;
  int? adobe;
  bool progresivo = false;
  bool hayFrame = false;
  int scans = 0;
  int ancho = 0;
  int alto = 0;
  int maxH = 1;
  int maxV = 1;
  int mcusLinea = 0;
  int mcusColumna = 0;

  int _u16(int p) {
    if (p + 1 >= datos.length) _error('datos truncados');
    return (datos[p] << 8) | datos[p + 1];
  }

  int _siguienteMarcador() {
    while (true) {
      while (pos < datos.length && datos[pos] != 0xFF) { pos++; }
      while (pos < datos.length && datos[pos] == 0xFF) { pos++; }
      if (pos >= datos.length) return -1;
      final marcador = datos[pos++];
      if (marcador != 0) return marcador;
    }
  }

  ImagenRgb ejecutar(int orientacion) {
    if (!DecodificadorJpeg.esJpeg(datos)) _error('falta SOI');
    while (true) {
      final marcador = _siguienteMarcador();
      if (marcador == -1 || marcador == 0xD9) break;
      if ((marcador >= 0xD0 && marcador <= 0xD7) || marcador == 0x01) continue;
      final largo = _u16(pos);
      if (largo < 2 || pos + largo > datos.length) _error('segmento invalido');
      final inicio = pos + 2;
      final fin = pos + largo;
      pos = fin;
      switch (marcador) {
        case 0xE0:
          jfif = jfif || (fin - inicio >= 14 && datos[inicio] == 0x4A &&
            datos[inicio + 1] == 0x46 && datos[inicio + 2] == 0x49 &&
            datos[inicio + 3] == 0x46 && datos[inicio + 4] == 0);
        case 0xEE:
          if (fin - inicio >= 12 && datos[inicio] == 0x41 &&
              datos[inicio + 1] == 0x64 && datos[inicio + 2] == 0x6F &&
              datos[inicio + 3] == 0x62 && datos[inicio + 4] == 0x65) {
            adobe = datos[inicio + 11];
          }
        case 0xDB:
          _dqt(inicio, fin);
        case 0xC0 || 0xC1 || 0xC2:
          _sof(marcador, inicio, fin);
        case 0xC4:
          _dht(inicio, fin);
        case 0xDD:
          intervalo = _u16(inicio);
        case 0xDA:
          _sos(inicio, fin);
        case 0xC3 || 0xC5 || 0xC6 || 0xC7 || 0xC8 || 0xC9 || 0xCA || 0xCB ||
            0xCC || 0xCD || 0xCE || 0xCF:
          _error('codificacion SOF/aritmetica 0x${marcador.toRadixString(16)}');
        default:
          break;
      }
    }
    if (!hayFrame || scans == 0) _error('sin frame o sin scans');
    return _componer(orientacion);
  }

  void _dqt(int p, int fin) {
    while (p < fin) {
      final precision = datos[p] >> 4;
      final indice = datos[p] & 15;
      p++;
      if (indice > 3 || precision > 1) _error('DQT invalida');
      final tabla = Int32List(64);
      for (var i = 0; i < 64; i++) {
        if (precision == 0) {
          tabla[_natural[i]] = datos[p++];
        } else {
          tabla[_natural[i]] = _u16(p);
          p += 2;
        }
      }
      cuantizacion[indice] = tabla;
    }
  }

  void _sof(int marcador, int p, int fin) {
    if (hayFrame) _error('mas de un SOF');
    if (datos[p] != 8) _error('precision ${datos[p]} bits');
    alto = _u16(p + 1);
    ancho = _u16(p + 3);
    final n = datos[p + 5];
    if (ancho == 0 || alto == 0 || ancho * alto > _maxPixeles) _error('dimensiones');
    if (n != 1 && n != 3) _error('$n componentes');
    if (p + 6 + 3 * n > fin) _error('SOF truncado');
    progresivo = marcador == 0xC2;
    for (var i = 0; i < n; i++) {
      final q = p + 6 + 3 * i;
      final h = datos[q + 1] >> 4;
      final v = datos[q + 1] & 15;
      if (h < 1 || h > 4 || v < 1 || v > 4 || datos[q + 2] > 3) _error('muestreo');
      componentes.add(_Componente(datos[q], h, v, datos[q + 2]));
    }
    for (final c in componentes) {
      if (c.h > maxH) maxH = c.h;
      if (c.v > maxV) maxV = c.v;
    }
    mcusLinea = (ancho + 8 * maxH - 1) ~/ (8 * maxH);
    mcusColumna = (alto + 8 * maxV - 1) ~/ (8 * maxV);
    for (final c in componentes) {
      c.anchoMuestras = (ancho * c.h + maxH - 1) ~/ maxH;
      c.altoMuestras = (alto * c.v + maxV - 1) ~/ maxV;
      c.bloquesAncho = (c.anchoMuestras + 7) >> 3;
      c.bloquesAlto = (c.altoMuestras + 7) >> 3;
      c.bloquesLineaMcu = mcusLinea * c.h;
      c.coeficientes = Int16List(c.bloquesLineaMcu * mcusColumna * c.v * 64);
    }
    hayFrame = true;
  }

  void _dht(int p, int fin) {
    while (p < fin) {
      final clase = datos[p] >> 4;
      final indice = datos[p] & 15;
      if (clase > 1 || indice > 3 || p + 17 > fin) _error('DHT invalida');
      final cuentas = Uint8List.sublistView(datos, p + 1, p + 17);
      var total = 0;
      for (final c in cuentas) { total += c; }
      if (total > 256 || p + 17 + total > fin) _error('DHT invalida');
      final valores = Uint8List.fromList(
        Uint8List.sublistView(datos, p + 17, p + 17 + total));
      final tabla = _Huffman(Uint8List.fromList(cuentas), valores);
      if (clase == 0) { tablasDc[indice] = tabla; } else { tablasAc[indice] = tabla; }
      p += 17 + total;
    }
  }

  void _sos(int p, int fin) {
    if (!hayFrame) _error('SOS antes de SOF');
    if (++scans > 1000) _error('demasiados scans');
    final n = datos[p];
    if (n < 1 || n > componentes.length || p + 1 + 2 * n + 3 > fin) _error('SOS invalido');
    final enScan = <_Componente>[];
    for (var i = 0; i < n; i++) {
      final id = datos[p + 1 + 2 * i];
      final tablas = datos[p + 2 + 2 * i];
      final c = componentes.firstWhere((e) => e.id == id,
        orElse: () => _error('componente $id'));
      c.dc = tablasDc[tablas >> 4];
      c.ac = tablasAc[tablas & 15];
      // latch_quant_tables: la tabla queda fijada en el primer scan.
      c.cuantizacion ??= cuantizacion[c.tq] ?? _error('falta DQT ${c.tq}');
      enScan.add(c);
    }
    final q = p + 1 + 2 * n;
    final ss = datos[q];
    final se = datos[q + 1];
    final ah = datos[q + 2] >> 4;
    final al = datos[q + 2] & 15;
    if (progresivo) {
      if (ss > se || se > 63 || (ss == 0 && se != 0) || (ss > 0 && n != 1) ||
          al > 13) {
        _error('scan progresivo invalido');
      }
    } else if (ss != 0 || se != 63 || ah != 0 || al != 0) {
      _error('scan secuencial invalido');
    }
    for (final c in enScan) {
      final necesitaDc = !progresivo || (ss == 0 && ah == 0);
      final necesitaAc = !progresivo || ss > 0;
      if ((necesitaDc && c.dc == null) || (necesitaAc && c.ac == null)) {
        _error('falta tabla Huffman');
      }
      // jpeg_make_d_derived_tbl rechaza simbolos DC mayores que 15.
      if (necesitaDc && c.dc!.valores.any((s) => s > 15)) _error('tabla DC');
      c.previo = 0;
    }
    final bits = _Bits(datos, pos);
    final intercalado = n > 1;
    final porFila = intercalado ? mcusLinea : enScan.single.bloquesAncho;
    final total = intercalado ? mcusLinea * mcusColumna
      : enScan.single.bloquesAncho * enScan.single.bloquesAlto;
    var eobrun = 0;

    void bloque(_Componente c, int fila, int columna) {
      final coef = c.coeficientes;
      final o = (fila * c.bloquesLineaMcu + columna) * 64;
      if (!progresivo) {
        final s = bits.decodificar(c.dc!);
        c.previo += _extender(bits.leer(s), s);
        coef[o] = c.previo;
        for (var k = 1; k < 64; k++) {
          final rs = bits.decodificar(c.ac!);
          final r = rs >> 4;
          final s2 = rs & 15;
          if (s2 != 0) {
            k += r;
            coef[o + _natural[k]] = _extender(bits.leer(s2), s2);
          } else {
            if (r != 15) break;
            k += 15;
          }
        }
        return;
      }
      if (ss == 0) {
        if (ah == 0) {
          final s = bits.decodificar(c.dc!);
          c.previo += _extender(bits.leer(s), s);
          coef[o] = c.previo << al;
        } else if (bits.bit() != 0) {
          coef[o] |= 1 << al;
        }
        return;
      }
      if (ah == 0) {
        // decode_mcu_AC_first
        if (eobrun > 0) { eobrun--; return; }
        for (var k = ss; k <= se; k++) {
          final rs = bits.decodificar(c.ac!);
          final r = rs >> 4;
          final s = rs & 15;
          if (s != 0) {
            k += r;
            coef[o + _natural[k]] = _extender(bits.leer(s), s) << al;
          } else if (r == 15) {
            k += 15;
          } else {
            eobrun = (1 << r) + bits.leer(r) - 1;
            break;
          }
        }
        return;
      }
      // decode_mcu_AC_refine
      final p1 = 1 << al;
      final m1 = -1 << al;
      void refinar(int z) {
        if (bits.bit() != 0 && (coef[z] & p1) == 0) {
          coef[z] += coef[z] >= 0 ? p1 : m1;
        }
      }
      var k = ss;
      if (eobrun == 0) {
        for (; k <= se; k++) {
          final rs = bits.decodificar(c.ac!);
          var r = rs >> 4;
          var s = rs & 15;
          if (s != 0) {
            s = bits.bit() != 0 ? p1 : m1;
          } else if (r != 15) {
            eobrun = (1 << r) + bits.leer(r);
            break;
          }
          do {
            final z = o + _natural[k];
            if (coef[z] != 0) {
              refinar(z);
            } else {
              if (--r < 0) break;
            }
            k++;
          } while (k <= se);
          if (s != 0 && k <= 63) coef[o + _natural[k]] = s;
        }
      }
      if (eobrun > 0) {
        for (; k <= se; k++) {
          final z = o + _natural[k];
          if (coef[z] != 0) refinar(z);
        }
        eobrun--;
      }
    }

    for (var mcu = 0; mcu < total; mcu++) {
      if (intervalo > 0 && mcu > 0 && mcu % intervalo == 0) {
        bits.reiniciar();
        for (final c in enScan) { c.previo = 0; }
        eobrun = 0;
      }
      final fila = mcu ~/ porFila;
      final columna = mcu % porFila;
      if (intercalado) {
        for (final c in enScan) {
          for (var y = 0; y < c.v; y++) {
            for (var x = 0; x < c.h; x++) {
              bloque(c, fila * c.v + y, columna * c.h + x);
            }
          }
        }
      } else {
        bloque(enScan.single, fila, columna);
      }
    }
    pos = bits.pos;
  }

  /// IDCT de cada componente sobre un plano de bloques completos.
  Uint8List _plano(_Componente c) {
    final ancho = c.bloquesAncho * 8;
    final salida = Uint8List(ancho * c.bloquesAlto * 8);
    final trabajo = Int32List(64);
    final q = c.cuantizacion!;
    for (var by = 0; by < c.bloquesAlto; by++) {
      for (var bx = 0; bx < c.bloquesAncho; bx++) {
        _idctIslow(c.coeficientes, (by * c.bloquesLineaMcu + bx) * 64, q,
          salida, by * 8 * ancho + bx * 8, ancho, trabajo);
      }
    }
    c.coeficientes = Int16List(0);
    return salida;
  }

  ImagenRgb _componer(int orientacion) {
    final planos = [for (final c in componentes) _plano(c)];
    final rgb = componentes.length == 1 ? false : _esRgb();
    final salida = Uint8List(ancho * alto * 3);
    final transpuesta = orientacion >= 5 && orientacion <= 8;
    final anchoSalida = transpuesta ? alto : ancho;
    final altoSalida = transpuesta ? ancho : alto;
    final filas = [for (final _ in componentes) Uint8List(ancho + 16)];
    final upsampling = [for (final c in componentes) _metodo(c)];
    for (var y = 0; y < alto; y++) {
      for (var i = 0; i < componentes.length; i++) {
        upsampling[i](componentes[i], planos[i], y, filas[i]);
      }
      final (base, paso) = _destino(orientacion, y);
      var d = base;
      if (componentes.length == 1) {
        final g = filas[0];
        for (var x = 0; x < ancho; x++, d += paso) {
          salida[d] = g[x];
          salida[d + 1] = g[x];
          salida[d + 2] = g[x];
        }
      } else if (rgb) {
        final r = filas[0], g = filas[1], b = filas[2];
        for (var x = 0; x < ancho; x++, d += paso) {
          salida[d] = r[x];
          salida[d + 1] = g[x];
          salida[d + 2] = b[x];
        }
      } else {
        final yy = filas[0], cb = filas[1], cr = filas[2];
        for (var x = 0; x < ancho; x++, d += paso) {
          final l = yy[x];
          final vb = cb[x];
          final vr = cr[x];
          salida[d] = _limitar(l + _crR[vr]);
          salida[d + 1] = _limitar(l + ((_cbG[vb] + _crG[vr]) >> 16));
          salida[d + 2] = _limitar(l + _cbB[vb]);
        }
      }
    }
    return ImagenRgb(anchoSalida, altoSalida, salida);
  }

  /// default_decompress_parms de libjpeg-turbo para tres componentes.
  bool _esRgb() {
    if (jfif) return false;
    if (adobe != null) return adobe == 0;
    final ids = componentes.map((c) => c.id).toList();
    return ids[0] == 82 && ids[1] == 71 && ids[2] == 66;
  }

  /// Indice de salida y paso por pixel, segun ImageOps.exif_transpose.
  (int, int) _destino(int orientacion, int y) {
    final w = ancho, h = alto;
    return switch (orientacion) {
      2 => ((y * w + w - 1) * 3, -3),
      3 => (((h - 1 - y) * w + w - 1) * 3, -3),
      4 => ((h - 1 - y) * w * 3, 3),
      5 => (y * 3, h * 3),
      6 => ((h - 1 - y) * 3, h * 3),
      7 => (((w - 1) * h + h - 1 - y) * 3, -h * 3),
      8 => (((w - 1) * h + y) * 3, -h * 3),
      _ => (y * w * 3, 3),
    };
  }

  /// jinit_upsampler: escoge el metodo como libjpeg-turbo con fancy activo.
  void Function(_Componente, Uint8List, int, Uint8List) _metodo(_Componente c) {
    if (c.h == maxH && c.v == maxV) return _completo;
    if (c.h * 2 == maxH && c.v == maxV) {
      return c.anchoMuestras > 2 ? _h2v1Fancy : _entero;
    }
    if (c.h == maxH && c.v * 2 == maxV) return _h1v2Fancy;
    if (c.h * 2 == maxH && c.v * 2 == maxV) {
      return c.anchoMuestras > 2 ? _h2v2Fancy : _entero;
    }
    if (maxH % c.h == 0 && maxV % c.v == 0) return _entero;
    _error('fraccion de muestreo');
  }

  static int _fila(_Componente c, int fila) =>
    fila < 0 ? 0 : fila >= c.altoMuestras ? c.altoMuestras - 1 : fila;

  void _completo(_Componente c, Uint8List plano, int y, Uint8List fila) {
    final o = y * c.bloquesAncho * 8;
    fila.setRange(0, ancho, plano, o);
  }

  void _entero(_Componente c, Uint8List plano, int y, Uint8List fila) {
    final eh = maxH ~/ c.h;
    final ev = maxV ~/ c.v;
    final o = (y ~/ ev) * c.bloquesAncho * 8;
    for (var x = 0; x < ancho; x++) {
      fila[x] = plano[o + x ~/ eh];
    }
  }

  void _h2v1Fancy(_Componente c, Uint8List plano, int y, Uint8List fila) {
    final o = y * c.bloquesAncho * 8;
    final n = c.anchoMuestras;
    var actual = plano[o];
    fila[0] = actual;
    fila[1] = (actual * 3 + plano[o + 1] + 2) >> 2;
    var d = 2;
    for (var i = 1; i < n - 1; i++) {
      final v = plano[o + i] * 3;
      fila[d++] = (v + plano[o + i - 1] + 1) >> 2;
      fila[d++] = (v + plano[o + i + 1] + 2) >> 2;
    }
    actual = plano[o + n - 1];
    fila[d++] = (actual * 3 + plano[o + n - 2] + 1) >> 2;
    fila[d] = actual;
  }

  void _h1v2Fancy(_Componente c, Uint8List plano, int y, Uint8List fila) {
    final stride = c.bloquesAncho * 8;
    final entrada = y >> 1;
    final abajo = (y & 1) == 1;
    final cerca = _fila(c, entrada) * stride;
    final lejos = _fila(c, abajo ? entrada + 1 : entrada - 1) * stride;
    final sesgo = abajo ? 2 : 1;
    for (var x = 0; x < ancho; x++) {
      fila[x] = (plano[cerca + x] * 3 + plano[lejos + x] + sesgo) >> 2;
    }
  }

  void _h2v2Fancy(_Componente c, Uint8List plano, int y, Uint8List fila) {
    final stride = c.bloquesAncho * 8;
    final entrada = y >> 1;
    final cerca = _fila(c, entrada) * stride;
    final lejos = _fila(c, (y & 1) == 0 ? entrada - 1 : entrada + 1) * stride;
    final n = c.anchoMuestras;
    var esta = plano[cerca] * 3 + plano[lejos];
    var siguiente = plano[cerca + 1] * 3 + plano[lejos + 1];
    fila[0] = (esta * 4 + 8) >> 4;
    fila[1] = (esta * 3 + siguiente + 7) >> 4;
    var anterior = esta;
    esta = siguiente;
    var d = 2;
    for (var i = 2; i < n; i++) {
      siguiente = plano[cerca + i] * 3 + plano[lejos + i];
      fila[d++] = (esta * 3 + anterior + 8) >> 4;
      fila[d++] = (esta * 3 + siguiente + 7) >> 4;
      anterior = esta;
      esta = siguiente;
    }
    fila[d++] = (esta * 3 + anterior + 8) >> 4;
    fila[d] = (esta * 4 + 7) >> 4;
  }
}

int _limitar(int v) => v < 0 ? 0 : v > 255 ? 255 : v;

/// Limite post-IDCT de libjpeg (RANGE_MASK = 1023, centrado en 128).
int _rangoIdct(int x) {
  var v = x & 1023;
  if (v >= 512) v -= 1024;
  return _limitar(v + 128);
}

int _fix(double x) => (x * 65536 + 0.5).toInt();

final _crR = _tabla((x) => (_fix(1.40200) * x + 32768) >> 16);
final _cbB = _tabla((x) => (_fix(1.77200) * x + 32768) >> 16);
final _crG = _tabla((x) => -_fix(0.71414) * x);
final _cbG = _tabla((x) => -_fix(0.34414) * x + 32768);

Int32List _tabla(int Function(int) f) =>
  Int32List.fromList([for (var i = 0; i < 256; i++) f(i - 128)]);

/// jpeg_idct_islow de libjpeg-turbo (CONST_BITS 13, PASS1_BITS 2).
void _idctIslow(Int16List coef, int o, Int32List q, Uint8List salida,
    int destino, int stride, Int32List ws) {
  for (var c = 0; c < 8; c++) {
    final i = o + c;
    if (coef[i + 8] == 0 && coef[i + 16] == 0 && coef[i + 24] == 0 &&
        coef[i + 32] == 0 && coef[i + 40] == 0 && coef[i + 48] == 0 &&
        coef[i + 56] == 0) {
      final dc = (coef[i] * q[c]) << 2;
      for (var r = 0; r < 64; r += 8) { ws[r + c] = dc; }
      continue;
    }
    var z2 = coef[i + 16] * q[16 + c];
    var z3 = coef[i + 48] * q[48 + c];
    var z1 = (z2 + z3) * 4433;
    var tmp2 = z1 + z3 * -15137;
    var tmp3 = z1 + z2 * 6270;
    z2 = coef[i] * q[c];
    z3 = coef[i + 32] * q[32 + c];
    var tmp0 = (z2 + z3) << 13;
    var tmp1 = (z2 - z3) << 13;
    final tmp10 = tmp0 + tmp3;
    final tmp13 = tmp0 - tmp3;
    final tmp11 = tmp1 + tmp2;
    final tmp12 = tmp1 - tmp2;
    tmp0 = coef[i + 56] * q[56 + c];
    tmp1 = coef[i + 40] * q[40 + c];
    tmp2 = coef[i + 24] * q[24 + c];
    tmp3 = coef[i + 8] * q[8 + c];
    z1 = tmp0 + tmp3;
    z2 = tmp1 + tmp2;
    z3 = tmp0 + tmp2;
    var z4 = tmp1 + tmp3;
    final z5 = (z3 + z4) * 9633;
    tmp0 *= 2446;
    tmp1 *= 16819;
    tmp2 *= 25172;
    tmp3 *= 12299;
    z1 *= -7373;
    z2 *= -20995;
    z3 = z3 * -16069 + z5;
    z4 = z4 * -3196 + z5;
    tmp0 += z1 + z3;
    tmp1 += z2 + z4;
    tmp2 += z2 + z3;
    tmp3 += z1 + z4;
    const r = 1 << 10;
    ws[c] = (tmp10 + tmp3 + r) >> 11;
    ws[56 + c] = (tmp10 - tmp3 + r) >> 11;
    ws[8 + c] = (tmp11 + tmp2 + r) >> 11;
    ws[48 + c] = (tmp11 - tmp2 + r) >> 11;
    ws[16 + c] = (tmp12 + tmp1 + r) >> 11;
    ws[40 + c] = (tmp12 - tmp1 + r) >> 11;
    ws[24 + c] = (tmp13 + tmp0 + r) >> 11;
    ws[32 + c] = (tmp13 - tmp0 + r) >> 11;
  }
  for (var f = 0; f < 8; f++) {
    final w = f * 8;
    final d = destino + f * stride;
    if (ws[w + 1] == 0 && ws[w + 2] == 0 && ws[w + 3] == 0 &&
        ws[w + 4] == 0 && ws[w + 5] == 0 && ws[w + 6] == 0 && ws[w + 7] == 0) {
      final v = _rangoIdct((ws[w] + 16) >> 5);
      for (var x = 0; x < 8; x++) { salida[d + x] = v; }
      continue;
    }
    var z2 = ws[w + 2];
    var z3 = ws[w + 6];
    var z1 = (z2 + z3) * 4433;
    var tmp2 = z1 + z3 * -15137;
    var tmp3 = z1 + z2 * 6270;
    var tmp0 = (ws[w] + ws[w + 4]) << 13;
    var tmp1 = (ws[w] - ws[w + 4]) << 13;
    final tmp10 = tmp0 + tmp3;
    final tmp13 = tmp0 - tmp3;
    final tmp11 = tmp1 + tmp2;
    final tmp12 = tmp1 - tmp2;
    tmp0 = ws[w + 7];
    tmp1 = ws[w + 5];
    tmp2 = ws[w + 3];
    tmp3 = ws[w + 1];
    z1 = tmp0 + tmp3;
    z2 = tmp1 + tmp2;
    z3 = tmp0 + tmp2;
    var z4 = tmp1 + tmp3;
    final z5 = (z3 + z4) * 9633;
    tmp0 *= 2446;
    tmp1 *= 16819;
    tmp2 *= 25172;
    tmp3 *= 12299;
    z1 *= -7373;
    z2 *= -20995;
    z3 = z3 * -16069 + z5;
    z4 = z4 * -3196 + z5;
    tmp0 += z1 + z3;
    tmp1 += z2 + z4;
    tmp2 += z2 + z3;
    tmp3 += z1 + z4;
    const r = 1 << 17;
    salida[d] = _rangoIdct((tmp10 + tmp3 + r) >> 18);
    salida[d + 7] = _rangoIdct((tmp10 - tmp3 + r) >> 18);
    salida[d + 1] = _rangoIdct((tmp11 + tmp2 + r) >> 18);
    salida[d + 6] = _rangoIdct((tmp11 - tmp2 + r) >> 18);
    salida[d + 2] = _rangoIdct((tmp12 + tmp1 + r) >> 18);
    salida[d + 5] = _rangoIdct((tmp12 - tmp1 + r) >> 18);
    salida[d + 3] = _rangoIdct((tmp13 + tmp0 + r) >> 18);
    salida[d + 4] = _rangoIdct((tmp13 - tmp0 + r) >> 18);
  }
}
