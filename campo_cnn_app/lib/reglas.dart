import 'domain.dart';

class ReglasSeguimiento {
  static Duration plazo(Cultivo cultivo) => cultivo == Cultivo.arroz
    ? const Duration(hours: 72) : const Duration(days: 7);

  static DateTime vencer(Cultivo cultivo, DateTime consulta) =>
    consulta.toUtc().add(plazo(cultivo));

  static DateTime? avisoInactividad(DateTime? ultimaActividad, int pendientes) =>
    ultimaActividad == null || pendientes == 0 ? null :
      ultimaActividad.toUtc().add(const Duration(days: 7));

  static bool coinciden(DateTime a, DateTime b) => a.toUtc() == b.toUtc();
}
