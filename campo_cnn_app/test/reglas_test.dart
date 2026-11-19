import 'package:campo_cnn/domain.dart';
import 'package:campo_cnn/reglas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1, 10);
  test('arroz vence exactamente a 72 horas y caña a siete días', () {
    expect(ReglasSeguimiento.vencer(Cultivo.arroz, start),
      DateTime.utc(2026, 1, 4, 10));
    expect(ReglasSeguimiento.vencer(Cultivo.cana, start),
      DateTime.utc(2026, 1, 8, 10));
  });
  test('inactividad requiere revisiones pendientes', () {
    expect(ReglasSeguimiento.avisoInactividad(start, 0), isNull);
    expect(ReglasSeguimiento.avisoInactividad(null, 1), isNull);
    expect(ReglasSeguimiento.avisoInactividad(start, 1),
      DateTime.utc(2026, 1, 8, 10));
  });
  test('coincidencia exige el mismo instante, incluso con zonas distintas', () {
    expect(ReglasSeguimiento.coinciden(start,
      DateTime.parse('2026-01-01T05:00:00-05:00')), isTrue);
    expect(ReglasSeguimiento.coinciden(start,
      start.add(const Duration(seconds: 1))), isFalse);
  });
}
