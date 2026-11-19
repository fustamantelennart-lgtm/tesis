import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'domain.dart';

/// Half-pixel, antialiased triangle resampler intended to match TensorFlow.
/// Numerical agreement with original validation images remains unverified.
class PreparadorImagen {
  static Uint8List preparar(Uint8List original) {
    final decoded = img.decodeImage(original);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const FormatException('No se pudo leer la fotografía.');
    }
    // image 4.13.1 already orients JPEG pixels and clears Orientation during
    // decode. Apply a remaining orientation only for a decoder that retains it.
    final oriented = decoded.exif.imageIfd.hasOrientation
      ? img.bakeOrientation(decoded) : decoded;
    final source = oriented.convert(numChannels: 3);
    // TensorFlow computes geometry in float32, floors the scaled dimensions,
    // and floors padding calculated from the unrounded dimensions.
    final ratio = math.max(_f32(source.width / 224.0),
      _f32(source.height / 224.0));
    final widthFloat = _f32(source.width / ratio);
    final heightFloat = _f32(source.height / ratio);
    final width = math.max(1, widthFloat.floor());
    final height = math.max(1, heightFloat.floor());
    final left = math.max(0, _f32(_f32(224.0 - widthFloat) / 2).floor());
    final top = math.max(0, _f32(_f32(224.0 - heightFloat) / 2).floor());
    final output = Uint8List(tensorBytes);
    final view = ByteData.sublistView(output);
    final xs = _weights(source.width, width);
    final ys = _weights(source.height, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final rgb = List<double>.filled(3, 0);
        for (final yw in ys[y]) {
          for (final xw in xs[x]) {
            final pixel = source.getPixel(xw.index, yw.index);
            final weight = xw.value * yw.value;
            rgb[0] += pixel.r * weight;
            rgb[1] += pixel.g * weight;
            rgb[2] += pixel.b * weight;
          }
        }
        final offset = ((top + y) * 224 + left + x) * 12;
        for (var c = 0; c < 3; c++) {
          view.setFloat32(offset + c * 4, rgb[c] / 255.0, Endian.little);
        }
      }
    }
    return output;
  }

  static double _f32(double value) => (Float32List(1)..[0] = value)[0];

  static List<List<_Weight>> _weights(int input, int output) {
    final scale = input / output;
    final radius = math.max(1.0, scale);
    return List.generate(output, (target) {
      final center = (target + 0.5) * scale;
      final first = math.max(0, (center - radius - 0.5).ceil());
      final last = math.min(input - 1, (center + radius - 0.5).floor());
      final values = <_Weight>[];
      var sum = 0.0;
      for (var i = first; i <= last; i++) {
        final weight = math.max(0.0, 1.0 - ((i + 0.5 - center) / radius).abs());
        if (weight > 0) {
          values.add(_Weight(i, weight));
          sum += weight;
        }
      }
      return values.map((w) => _Weight(w.index, w.value / sum)).toList();
    });
  }
}

class _Weight {
  const _Weight(this.index, this.value);
  final int index;
  final double value;
}
