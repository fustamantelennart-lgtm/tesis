# Trazabilidad provisional CP01–CP18 (18-11-2026)

El contenido de CP01–CP18 fue cotejado con el Word en la revisión comunicada por el usuario. Esta ejecución conserva esa matriz, sin repetir el cotejo documental. "Automatizada" significa prueba local con SQLite FFI, widgets o dobles de Android; "emulador" solo significa una ejecución realmente observada. Ningún CP se aprueba en teléfono físico sin evidencia.

| CP / requisito previo | Implementación | Prueba ejecutada / entorno | Evidencia y resultado | Pendiente concreto |
|---|---|---|---|---|
| 01 modelo por cultivo | `domain.dart`, `Motor` | SHA de archivos y fase A CP04 sobre 629 tensores en Samsung | Ambos modelos ejecutados en `Motor` y `MotorDiagnostico`, con 0 errores de score y categoría; [informe](../evidencia/cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md) | Recorrido de diagnóstico habitual con cámara/galería en Samsung |
| 02 cámara/galería | `main.dart`, selección persistente, `retrieveLostData` | Widgets y flujo; Windows | Recuperación y contexto automatizados | Captura, galería y recreación real |
| 03 sin internet | Modelos y SQLite locales | Inspección de arquitectura; Windows | Implementado | Modo avión en Android físico |
| 04 concordancia | Manifiesto y 629 originales/tensores externos; checkpoints y comparador | Fases A y B completas en Samsung SM-A166M, Android 15; LDPlayer anterior conservado | Samsung: 629 comparadas, 0 errores, 0 scores fuera de tolerancia y 0 categorías distintas; 394 checkpoints reutilizados; [informe y evidencias](../evidencia/cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md). [Fallo histórico LDPlayer](../evidencia/cp04_1_ldplayer_falla/INFORME_CP04_LDPLAYER.md) | Revisión formal de la evidencia CP04; no aprobar automáticamente |
| 05 positivo crea revisión | `Registro`, reglas 72 h y 7 d | `registro_test.dart`; SQLite FFI/Windows | Automatizada aprobada | Recorrido en Samsung |
| 06 sano inicial sin revisión | `Registro` | `registro_test.dart`; SQLite FFI/Windows | Automatizada aprobada | Recorrido en Samsung |
| 07 aviso al plazo | `Avisos`, programador inexacto | `avisos_test.dart`; doble Android/Windows | Solicitud/fecha automatizadas | Recepción real y hora observada |
| 08 sin aviso anticipado | `Avisos` | `avisos_test.dart`; doble Android/Windows | Fecha objetivo comprobada | Observar comportamiento Android |
| 09 revisión positiva | `Registro` | `registro_test.dart`; SQLite FFI/Windows | Mismo caso, siguiente revisión automatizados | Recorrido con cámara en Samsung |
| 10 revisión sana | `Registro`, `Avisos` | `registro_test.dart`, `avisos_test.dart`; Windows | Cierre, historial y cancelación simulada | Recorrido y cancelación en Samsung |
| 11 inactividad con pendientes | `ReglasSeguimiento`, `Avisos` | `avisos_test.dart`; reloj y doble Android | Siete días automatizados | Recepción real |
| 12 sin pendientes | `Avisos` | `avisos_test.dart`; doble Android | Cancelación automatizada | Ausencia de aviso observada |
| 13 abrir reinicia inactividad | `main.dart`, `Registro` | Widget con SQLite real y caso activo; Windows | Actividad cambia; revisión, fechas, caso y consultas no cambian | Ciclo de vida físico y aviso real |
| 14 atender todas cancela | `Registro`, `Avisos` | `avisos_test.dart`; doble Android | Cancelación automatizada | Solicitud real en Android |
| 15 coincidencia sin duplicar | `Avisos`, `avisos_relaciones` | `avisos_test.dart`; SQLite FFI/doble Android | Agrupación, motivos y destino automatizados | Recepción y navegación real |
| 16 cierre/reapertura | `Registro`, migración a v5 | SQLite FFI; Windows; actualización APK Samsung con `adb install -r` | Historial y retroceso de reloj automatizados; Android conservó `firstInstallTime` y `dataDir` tras actualizar; [evidencia](../evidencia/cp04_4_samsung_pasa/INFORME_ACTUALIZACION_SAMSUNG.md) | Verificar visualmente consultas, fotos, casos y revisiones antes y después de reapertura |
| 17 archivo ilegible | `PreparadorImagen`, flujo | Pruebas de imagen y selección; Windows | Rechazo automatizado sin transición | Selector e interfaz Android |
| 18 permiso denegado | `Avisos`, interfaz de consultas | `avisos_test.dart`; doble Android/Windows | Estado sin entrega ficticia automatizado | Cambiar permiso en Ajustes y observar |

La suite Flutter anterior terminó con 46 pruebas aprobadas y una omitida; `flutter analyze` no informó incidencias. La ejecución posterior en Samsung completó CP04 A y B con los criterios de score y categoría satisfechos; su aprobación formal no es automática. La recepción real de avisos y los recorridos Android ajenos a CP04 permanecen pendientes.


