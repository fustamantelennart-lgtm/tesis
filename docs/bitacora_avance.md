# Campo CNN: avance y trazabilidad (15-11-2026)

## Resultado CP04 en Samsung físico (18–19-11-2026)

La versión corregida se comparó en el Samsung SM-A166M, Android 15. La fase A ejecutó los 629 tensores de Colab directamente en `Motor` y `MotorDiagnostico`: 217 arroz y 412 caña, sin errores, scores fuera de tolerancia ni categorías distintas. La fase B procesó los 629 originales externos: 629 entradas verificadas y comparadas, 0 errores, 0 scores fuera de tolerancia y 0 categorías distintas. Los 629 tensores tuvieron diferencias numéricas pequeñas, registradas como diagnóstico y sin límite obligatorio nuevo. Tras perder la conexión USB en 394/629, la fase B reanudó el mismo ID y reutilizó exactamente 394 checkpoints verificados. El informe final tiene estado `comparacion_pasa` y no aprueba CP04 automáticamente. [Informe, JSON/CSV y registros completos](../evidencia/cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md).

La aplicación habitual del Samsung se conservó: CP04 se instaló con otro identificador, `com.example.campo_cnn.cp04`. Al terminar se restauró el ajuste de pantalla previo y se abrió la aplicación normal. El resultado fallido anterior de LDPlayer se conserva como evidencia histórica; no representa el Samsung ni sus tiempos. La recepción real de avisos y los demás recorridos Android no observados siguen pendientes. Las secciones inferiores describen etapas anteriores y no sustituyen este resultado.

**Actualización posterior, 19-11-2026.** Se copió el APK habitual anterior, se confirmaron `applicationId`, versión y certificado idénticos y se actualizó con `adb install -r`, sin desinstalar ni limpiar datos. El APK instalado coincide por SHA-256 con el corregido; Android conservó `firstInstallTime` y `dataDir`, y la app inició sin errores observados. La instalación no depurable impidió extraer un respaldo completo de SQLite y fotos. **La conservación de consultas, fotos, casos y revisiones aún requiere comprobación visual en el teléfono**; tampoco se han ejecutado los recorridos funcionales ni observado avisos reales. [Evidencia de actualización](../evidencia/cp04_4_samsung_pasa/INFORME_ACTUALIZACION_SAMSUNG.md).

## Resultado CP04 observado en LDPlayer (18-11-2026)

La comparación CP04 completa se ejecutó en **LDPlayer** (`emulator-5554`, Android 14; identificadores Android SONY SOV44 emulados). Se transfirieron las 629 fotografías y los 629 tensores externos; antes de ejecutar, el manifiesto y los 1.258 binarios coincidieron por SHA-256. El informe `1795038207632528_881fd9f5` registró **629 verificadas y comparadas, 0 errores de ejecución, 387 scores fuera de tolerancia y 194 diferencias de categoría**. Por cultivo: arroz 217 comparadas, 171 fallos de score y 2 de categoría; caña 412 comparadas, 216 fallos de score y 192 de categoría. Los 629 tensores presentan diferencias numéricas, documentadas aparte sin umbral obligatorio. El estado fue `comparacion_falla`; **CP04 no está aprobado**. El detalle, fotografías afectadas, informes íntegros y log están en [el informe de LDPlayer](../evidencia/cp04_1_ldplayer_falla/INFORME_CP04_LDPLAYER.md). Las afirmaciones posteriores de esta bitácora de que faltaba ejecutar CP04 son históricas.

Se conservaron respaldos privados antes y después, así como los informes JSON/CSV y 629 checkpoints en LDPlayer y en el equipo. El APK normal se reinstaló con `adb install -r`, sin limpiar ni desinstalar. Tras un reinicio de LDPlayer se verificó la interfaz «Diagnóstico en campo» y que los informes seguían en el dispositivo. Estos resultados **no son del Samsung ni miden sus tiempos de inferencia**; la recepción real de avisos sigue pendiente.

## Ajustes previos a la ejecución CP04 (18-11-2026)

**Apertura en LDPlayer.** Se confirmó que el APK debug anterior se había compilado con la entrada `integration_test/concordancia_test.dart`, que ejecuta CP04 y no `lib/main.dart`; sin manifiesto externo la prueba falla antes de mostrar Campo CNN. Se generó `Campo_CNN_aplicacion_LDPlayer_debug.apk` con `-t lib/main.dart`, se respaldaron los datos privados existentes y se actualizó LDPlayer con `adb install -r`. La nueva apertura llegó al diálogo Android de permiso de notificaciones. El usuario eligió «Permitir»; se aplicó esa misma elección en la instancia conectada. ADB confirmó el permiso concedido, la navegación de Campo CNN visible y el cuadro cerrado. La captura `campo_cnn_estado_ldplayer.png` muestra la pantalla «Diagnóstico en campo» con Inicio, Diagnóstico, Medición, Historial y Consultas. El APK de CP04 se identifica ahora con nombre separado en su guía para evitar instalarlo como aplicación normal.

**Resultados finales de esta revisión.** `flutter analyze --no-pub` terminó con **No issues found** y `flutter test --reporter expanded --no-pub` terminó con **46 pruebas aprobadas y una omitida** por la DLL TFLite de Windows ausente. `flutter build apk --release --no-pub` produjo `build/app/outputs/flutter-apk/app-release.apk` (70,8 MB) y la compilación debug con entrada `integration_test/concordancia_test.dart` produjo `app-debug.apk` (aproximadamente 215 MB). La inspección ZIP del release encontró dos modelos y cero referencias CP04. Los SHA-256 de los modelos siguen siendo `0728e2ddedc0db0959870ef420c204df3094fd780ef520c0d3fb2b10a9090040` y `9042f0dffc63a6c143fd64a8d36a34ab25bc96cb74b21e51df35d7e88a368bec`.

**Observación preparatoria en LDPlayer.** Se identificó `emulator-5554` SOV44 Android 14. Antes de actualizar con `adb install -r`, se extrajo y verificó un respaldo `.tgz` binario del espacio privado en `_local/resguardos_android/` (fuera del repositorio). La app creó sus carpetas CP04 con propietario de la aplicación y pasó una comprobación de escritura; al faltar `manifest.json` externo, terminó con el error previsto. Se guardaron logs de la apertura. ADB transfirió y recuperó un README pequeño con SHA-256 idéntico. No se usaron `pm clear` ni desinstalación. En **esa etapa preparatoria** aún no se habían transferido ni comparado las 629 fotos; la ejecución completa posterior se registra al inicio de este archivo.

La revisión comunicada por el usuario ya cotejó el contenido de CP01–CP18 con el Word. En esta ejecución se conserva esa trazabilidad y se dejan pendientes las pruebas sin evidencia; no se atribuye a esta ejecución una lectura nueva del documento. Las afirmaciones de secciones anteriores sobre referencias ausentes y falta de cotejo describen estados históricos. Hay manifiesto `listo`, 629 originales y 629 tensores de validación; la comparación posterior en LDPlayer falló los criterios y requiere investigar sus discrepancias.

SQLite pasó a esquema 5. Para revisiones históricas se reconstruye la creación invirtiendo el plazo registrado en el vencimiento; se coteja con consultas positivas y caso, sin ordenar exclusivamente por vencimiento. `creado_fuente` y `creado_evidencia` distinguen fecha registrada y reconstruida; `creado_utc_legado` conserva el valor anterior de v4. La prueba con retroceso del reloj verifica que la revisión posterior puede vencer antes que la previa. Una prueba de widget con SQLite real comprueba que apertura desde aviso y reanudación agregan actividad, mientras revisión, fechas, caso y número de consultas permanecen idénticos.

CP04 ahora lee `manifest.json`, 629 originales y 629 tensores desde el directorio externo propio de la aplicación. La versión habitual del APK no empaqueta esas referencias. El diario por fila permite continuar tras una interrupción y solo reutiliza un resultado después de verificar los bytes y la identidad de manifiesto, modelos, criterios, código y entorno. Los informes tienen ID e instantes únicos. Se considera completa una comparación únicamente con 629 entradas verificadas y comparadas y conteos correctos por cultivo. El procedimiento sin desinstalación está en [colab/REFERENCIAS_CP04.md](../campo_cnn_app/colab/REFERENCIAS_CP04.md).

La ruta histórica de medición y sus evidencias no se modificaron. Su cronómetro rodea la llamada completa `Motor.inferir(tensor)`: incluye validación del tamaño del tensor, creación del contenedor de salida, `Interpreter.run`, lectura y validación del score, además de las operaciones auxiliares ejecutadas dentro de esa llamada. La lectura del paquete, comprobación SHA y actualización de pantalla permanecen fuera. No se reinterpretan ni cambian los tiempos históricos.

Verificación de esta revisión: `flutter analyze --no-pub` sin incidencias, `flutter test --reporter expanded --no-pub` con 46 pruebas aprobadas y una omitida por la biblioteca TFLite ausente en Windows, y compilaciones Android debug del comparador y release de la aplicación terminadas. No se ejecutó una comparación CP04 completa ni se observó recepción real de avisos.

> **Actualización del agente, 18-11-2026.** Las secciones antiguas de esta bitácora describen estados de fechas anteriores. La especificación vigente está en [agente_seguimiento.md](agente_seguimiento.md), la matriz detallada en [trazabilidad_cp.md](trazabilidad_cp.md) y el borrador de resultados en [resultados_agente.md](resultados_agente.md). En particular, la afirmación histórica de que faltan originales CP04 ya no aplica: `integration_test/fixtures/manifest.json` está `listo`, con 629 registros, 629 originales y 629 tensores de validación. CP04 aún no está aprobado.

## Verificación del agente, 18-11-2026

Se inspeccionaron las reglas, SQLite, avisos, UI, flujo, motor, medición y Android. Ya existían las reglas principales, transacción de consultas, idempotencia, recuperación de selección y fotos, cola de avisos e identificadores persistentes. Se completó `creado_utc` de revisiones (esquema 4 y migración sin borrar datos), la relación persistente de avisos agrupados con sus motivos y todas las revisiones afectadas, el destino dirigido de un solo caso, la distinción visible de pendiente vencida y el tipo de actividad `reanudacion`. La migración reconstruye fechas antiguas con la mejor evidencia disponible; no pretende recuperar un instante que antes no se almacenaba.

Tres regresiones fallaron antes del cambio (fecha de creación ausente, destino del aviso agrupado de un caso y etiqueta de revisión vencida) y pasaron después. `flutter analyze` terminó con **No issues found**. `flutter test --reporter expanded` terminó con **42 pruebas aprobadas, una omitida** en Windows; la omitida requiere la DLL TFLite de Windows. Las pruebas del agente usan reloj controlado, SQLite FFI, widgets y un doble del programador Android; no prueban recepción física.

Se comprobaron SHA-256 de `assets/arroz.tflite` y `assets/cana.tflite` contra `domain.dart`: `0728e2ddedc0db0959870ef420c204df3094fd780ef520c0d3fb2b10a9090040` y `9042f0dffc63a6c143fd64a8d36a34ab25bc96cb74b21e51df35d7e88a368bec`. No se cambiaron modelos, umbrales, preprocesamiento, `Motor`, `medicion.dart`, tolerancia ni referencias CP04. El manifiesto CP04 declara TensorFlow 2.21.0 y Pillow 11.3.0, `arroz/val=217` y `cana/val=412`; sus archivos se preservaron. El registro previo del ejecutor indica una prueba superada en emulador, pero `concordancia_log.txt` no acredita CP04 completo. Se detectó `emulator-5554` (SOV44, Android 14); no es un Samsung físico. El Word `TESIS-VERSION ACTUALIZADA (5).docx` no estuvo disponible: falta el cotejo literal.

La compilación `flutter build apk --release --flavor standard` terminó correctamente: `build/app/outputs/flutter-apk/app-standard-release.apk` (70,8 MB). Se añadió una variante `cp04` exclusiva para los 1,7 GB de referencias; el APK estándar contiene ambos modelos y **cero** assets `integration_test/fixtures/`, según inspección ZIP. El manifiesto Android combinado estándar conserva `com.example.campo_cnn`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` y los receptores de notificación y reinicio. La primera compilación sin variantes se interrumpió al detectar que empaquetaba todas las fotos de CP04; se eliminó exclusivamente su APK parcial `app-release.apk` y su suma obsoleta. La comparación CP04 nueva en emulador se registra por separado en `concordancia_agente_2026-11-18.log` y solo podrá calificarse tras terminar y revisar su informe.

Se intentó `flutter test integration_test/concordancia_test.dart -d emulator-5554 --flavor cp04`. La compilación de los assets CP04 no llegó a la instalación ni a ejecutar la prueba; tras unos 14 minutos sin avance de registro y con saturación de recursos se detuvo el intento y el daemon Gradle. `concordancia_agente_2026-11-18.log` conserva el registro. **No existe un informe nuevo de score o categoría**, por lo que CP04 continúa pendiente. Después de detenerlo, `flutter analyze` volvió a terminar con **No issues found** y las 8 pruebas de `test/avisos_test.dart` pasaron. El APK estándar ya compilado sigue siendo válido; la prueba CP04 debe ejecutarse en un entorno con recursos suficientes o mediante lotes trazables, manteniendo sus 629 referencias y el criterio original.

## Fuentes y diferencias

- Se inspeccionó el proyecto descomprimido entregado. `TESIS-VERSION ACTUALIZADA (4).docx`, `referencias_validacion.csv`, los metadatos de conversión y las fotografías originales de validación/desarrollo **no están entre los archivos accesibles**. Por ello no se pueden cotejar los textos exactos de RF01–RF12/CP01–CP18 ni certificar concordancia.
- El prototipo tenía diagnóstico exploratorio sin consultas persistidas. La medición `.cbm` usa tensores ya preparados y no valida el procesamiento de fotografías.
- Se mantienen los dos modelos, sus umbrales y `lib/medicion.dart`. El ejecutor `Motor` no fue alterado. El diagnóstico ahora llama a `IsolateInterpreter` sobre un `Motor` verificado; la medición histórica sigue usando `Motor.inferir` y no corresponde a esta versión de diagnóstico.
- Se reemplazó `img.copyResize` por un remuestreo separable de núcleo triangular, coordenadas de medio píxel y antialias al reducir, orientación EXIF, RGB, relleno de ceros y Float32/255. Esto se diseñó para reflejar `tf.image.resize_with_pad`; **no se ha demostrado equivalencia numérica** con TensorFlow en fotografías originales. El criterio de integración pendiente es `abs(android-colab) <= 1e-5 + 1e-4 * abs(colab)` y cero cambios de categoría, sin ajustar umbrales. Se necesita comparar los mismos bytes originales, incluidos los de captura de cámara.

## Implementado

- [x] SHA-256 y tamaños de modelos comprobados; `Motor` comprueba además formas y tipos al abrir.
- [x] Preparación de imagen independiente con pruebas de imagen ilegible, gradiente, relleno asimétrico y orientación EXIF. Preparación e inferencia del diagnóstico fuera del isolate de interfaz.
- [x] Consultas, casos, revisiones, actividad, selección de foto y estados/eventos de avisos en SQLite con claves foráneas; esquema versión 3 con migraciones. Las consultas y transiciones de revisiones se confirman en una transacción. Copia durable provisional y recuperación de huérfanos sin borrarlos.
- [x] Positivo inicial abre caso; arroz programa revisión a 72 horas, caña a 7 días. Sano inicial queda como consulta. Revisión positiva crea siguiente; sana cierra el caso, con historial conservado.
- [x] Historial de consultas y detalle de caso separados del historial de mediciones. Exportación de puntuaciones completas de consultas en JSON/CSV.
- [x] Programación local inexacta y reconciliación al abrir/reanudar; permiso actualizado, reprogramación por fecha/contenido, agrupación por instante, números Android persistentes únicos y eventos históricos. Un aviso agrupado abre la lista de pendientes.
- [x] Reglas temporales con reloj inyectable y pruebas unitarias. Pruebas SQLite de reapertura, migración, cierre, cultivo ajeno, duplicado, saneamiento de copia, sano inicial y revisión positiva de caña.
- [x] Contexto inmutable de revisión, bloqueo de navegación incompatible, cancelación explícita y recuperación idempotente de `image_picker.retrieveLostData()`.
- [x] Fechas locales en consultas y caso; fotografías y consultas del caso; fallos de exportación visibles.
- [ ] Comparación numérica con las imágenes originales y referencias de validación.
- [ ] Pruebas de SQLite y avisos en el Samsung físico, incluidos apagado/reinicio y permisos denegados.
- [ ] Cotejo literal de RF/CP con el Word.

La actividad se actualiza al abrir/reanudar la app y al guardar una consulta válida. Abrir no atiende revisiones. La inactividad se programa a siete días de la última actividad únicamente cuando hay revisiones pendientes. Los avisos que coinciden exactamente se agrupan y abren la lista de revisiones pendientes. Android puede retrasar alarmas inexactas por ahorro de batería. `programado` solo significa aceptación de la solicitud por el plugin; no demuestra entrega.

## Recorridos revisados

| Recorrido | Comprobación disponible | Falta observar |
|---|---|---|
| Cultivo → cámara/galería → fotografía válida → consulta | Contexto persistente, tensor en isolate, modelo SHA/forma verificados, consulta SQLite transaccional | Captura y score reales en Samsung |
| Positivo inicial → caso → revisión | Pruebas SQLite arroz/caña y reloj; caso identificable con fotos | Navegación táctil y aviso real |
| Revisión positiva/sana | Pruebas de siguiente revisión/cierre, rechazo de duplicados y cultivo ajeno | Repetición sobre teléfono |
| Cancelación, cambio y recuperación | Pruebas del controlador y selección idempotente; `retrieveLostData` integrado | Destrucción real de actividad por Android |
| Inactividad, permiso, coincidencia y reinicio | Programador falso con cambios de permiso, fecha, agrupación, cancelación y fallo parcial | Ajustes de Android, apagado/reinicio y entrega física |
| Exportación y persistencia | Pruebas SQLite de reapertura; error de exportación visible en interfaz | Compartir archivo y reapertura en teléfono |

La inferencia asíncrona del diagnóstico y su compatibilidad efectiva con el Samsung no están medidas. La prueba del isolate solo verifica que la preparación de una imagen grande produce el mismo tensor que la ruta directa; no representa una medición de tiempos de interfaz.

## Matriz CP01–CP18

Estados: **parcial** = implementación o prueba aislada disponible, sin satisfacer todos los resultados esperados; **pendiente** = falta evidencia indispensable. Los criterios resumidos proceden del texto entregado, no del Word ausente.

| CP | Estado | Evidencia disponible | Incidencia o pendiente |
|---|---|---|---|
| 01 modelo por cultivo | Parcial | Selección y SHA en `Motor` | Probar en teléfono |
| 02 cámara/galería | Parcial | Selectores y recuperación idempotente del contexto | Probar captura, galería y recreación real |
| 03 sin internet | Parcial | TFLite y SQLite locales | Prueba en modo avión |
| 04 concordancia | Pendiente | Preparador separado | Faltan CSV, metadatos, imágenes originales y comparación numérica |
| 05 positivo crea revisión | Parcial | Prueba SQLite de arroz positivo | Probar en teléfono y caña |
| 06 sano inicial sin revisión | Parcial | Prueba SQLite de caña sana | Probar en teléfono |
| 07 aviso al plazo | Parcial | Programador falso comprueba fechas y reinicio | Verificar recepción real; no se garantiza instante exacto |
| 08 sin aviso anticipado | Parcial | Fecha solicitada comprobada en prueba | Observación en teléfono |
| 09 revisión positiva | Parcial | Prueba SQLite de caña positiva | Probar en teléfono |
| 10 revisión sana | Parcial | Prueba SQLite de cierre | Probar en teléfono |
| 11 inactividad con pendientes | Parcial | Prueba de planificación y reprogramación | Verificar emisión |
| 12 sin pendientes | Parcial | Prueba de cancelación al atender todos | Verificar ausencia física |
| 13 abrir reinicia inactividad | Parcial | Prueba con reloj y nueva actividad | Verificar en teléfono |
| 14 atender todas cancela | Parcial | Prueba de cancelación en programador falso | Verificar Android |
| 15 coincidencia sin duplicación | Parcial | Pruebas de uno y varios casos | Verificar alarmas y recepción |
| 16 cierre y reapertura | Parcial | Prueba SQLite FFI | Probar en teléfono |
| 17 archivo ilegible | Parcial | Prueba unitaria | Probar selector y estado UI |
| 18 permiso denegado | Parcial | Prueba falsa de permiso y eventos sin entrega | Probar Android y Ajustes |

## Compilar e instalar sin borrar datos

Desde `campo_cnn_app`: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug` o `flutter build apk --release`. Con el teléfono conectado: `flutter devices` y `flutter install --debug` o `flutter install --release` según la variante compilada para **actualizar la misma aplicación**; no desinstalar ni usar `pm clear` porque eliminarían SQLite e imágenes privadas. La variante release existente usa firma de depuración; mantener el mismo `applicationId` y firma para actualizar. Si Android rechaza la actualización por firma distinta, conservar primero una copia de los datos y resolver la firma antes de instalar.

## Archivos modificados

`pubspec.yaml`, `pubspec.lock`, `lib/main.dart`, `lib/preprocesamiento.dart`, `lib/registro.dart`, `lib/reglas.dart`, `lib/avisos.dart`, `lib/consultas.dart`, `lib/flujo.dart`, `lib/diagnostico_motor.dart`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `test/reglas_test.dart`, `test/preprocesamiento_test.dart`, `test/registro_test.dart`, `test/avisos_test.dart`, `test/flujo_test.dart`, `test/diagnostico_motor_test.dart`, `README.md`, `AVANCE.md`, `HALLAZGOS.md`.

## Verificaciones ejecutadas

`flutter test` pasó 23 pruebas de imagen, reglas, flujo, SQLite, avisos y contrato del ejecutor asíncrono. `flutter analyze` terminó sin incidencias. `flutter build apk --release` compiló correctamente el código final en `build/app/outputs/flutter-apk/app-release.apk` (70,8 MB). El manifiesto combinado release contiene `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` y ambos receptores de avisos; minSdk 24 y targetSdk 36. También aparecen permisos heredados de plugins (`READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE` y `READ_PHONE_STATE`), que deben revisarse antes de distribución pública. `flutter devices` no detectó un dispositivo Android; no se ejecutaron pruebas en el Samsung.

## Actualización integral del 15-11-2026

La tabla anterior describe la entrega previa. Esta actualización añade una compuerta de inicio con reintento, recuperación de selección conservada durante fallos parciales, exclusión mutua entre guardado y barrido, normalización de rutas, limpieza de resultado por contexto, retención de navegación diferida y conservación de alarmas inexactas pendientes después del vencimiento. `hallazgos.md` registra qué pruebas fallaron antes de corregir. Se preservaron los modelos, las etiquetas, los umbrales y la ruta histórica de `medicion.dart`.

La geometría de `preprocesamiento.dart` se corrigió conforme a la implementación publicada de TensorFlow 2.20: cálculo en float32, `floor` de las dimensiones y relleno calculado desde el tamaño flotante. **No se ha confirmado que 2.20 sea la versión efectiva de Colab ni la equivalencia completa del remuestreo.** El script `colab/generar_referencias_integracion.py` genera a partir de los mismos bytes originales seleccionados tensores `.bin`, scores TFLite, versiones y SHA-256. Debe ejecutarse en Colab junto con la versión de TensorFlow usada para entrenar. Comparar el tensor por separado del score y aplicar al score el criterio `abs(android-colab) <= 1e-5 + 1e-4*abs(colab)` con cero cambios de categoría. No se cambió la tolerancia ni el umbral.

La política de vencidos distingue `vencido_pendiente_android` (la solicitud aún figura en Android) y `vencido_sin_entrega_verificada` (no figura). La primera se conserva; la segunda se muestra como revisión vencida en la app y no se reprograma con fecha pasada. Ninguno de esos estados demuestra entrega. Al atender todos los pendientes se cancelan las solicitudes restantes. Varios avisos de navegación usan el destino más reciente, que se mantiene hasta resolver expresamente la revisión activa.

Verificación actual: `flutter analyze` terminó con **No issues found**; `flutter test` terminó con **33 aprobadas, una omitida** por faltar `libtensorflowlite_c-win.dll` en el VM de Windows. `flutter build apk --release` creó `build/app/outputs/flutter-apk/app-release.apk` (70,8 MB). La prueba omitida y `integration_test/ejecutor_test.dart` ejecutan ambos modelos reales con tensor válido, inferencia directa y asíncrona y varias consultas; están **pendientes en teléfono**. `flutter devices` mostró Windows, Chrome y Edge, sin Android. El manifiesto combinado release conserva `com.example.campo_cnn`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` y ambos receptores; no se cambiaron firma ni `applicationId`.

### CP01–CP18, estado actualizado

El Word `TESIS-VERSION ACTUALIZADA (4).docx` no está accesible, por lo que esta matriz usa los resúmenes de la entrega anterior y **no representa cotejo literal con el Word**. Ningún CP está aprobado por observación física.

| CP | Estado actualizado | Evidencia nueva y comprobación pendiente |
|---|---|---|
| 01 | Parcial | SHA/tipo/forma en código; comparación directa/asíncrona pendiente en Android. |
| 02 | Parcial | Inicio bloquea selector hasta recuperar selección; captura/galería real pendiente. |
| 03 | Parcial | Modelos y SQLite locales; modo avión en Samsung pendiente. |
| 04 | Pendiente | Geometría corregida; faltan Word, versión Colab, CSV, fotos originales y comparación numérica de tensor y scores. |
| 05 | Parcial | Caso y revisión positiva probados en SQLite; recorrido físico pendiente. |
| 06 | Parcial | Sano inicial sin revisión probado en SQLite; teléfono pendiente. |
| 07 | Parcial | Plazo y alarma tardía probados con programador falso; entrega Android pendiente. |
| 08 | Parcial | No se solicita aviso antes de fecha; observar emisión física pendiente. |
| 09 | Parcial | Revisión positiva probada en SQLite; interfaz física pendiente. |
| 10 | Parcial | Cierre por revisión sana probado; teléfono pendiente. |
| 11 | Parcial | Inactividad a 7 días con pendientes probada; recepción física pendiente. |
| 12 | Parcial | Cancelación sin pendientes probada; ausencia física pendiente. |
| 13 | Parcial | Apertura/reanudación reinicia inactividad en código; teléfono pendiente. |
| 14 | Parcial | Atender todos cancela solicitudes falsas; Android pendiente. |
| 15 | Parcial | Agrupación de casos probada; entrega coincidente pendiente. |
| 16 | Parcial | Reapertura y migración en SQLite FFI; datos reales del Samsung pendientes. |
| 17 | Parcial | Imagen ilegible rechazada; error y reintento con selector real pendientes. |
| 18 | Parcial | Permiso recuperado tras vencimiento probado con falso; Ajustes Android pendiente. |

En el Samsung SM-A166M: actualizar el APK con la misma firma sin desinstalar ni borrar datos; abrir en modo avión; probar cámara y galería, positivo/sano de ambos cultivos, revisión del mismo cultivo después de otra consulta, cancelación de selector, error y reintento, salida tras guardar, aviso al plazo y después del plazo, permiso denegado y restaurado en Ajustes, reinicio, coincidencia de casos, reapertura y exportación. Ejecutar `flutter test integration_test/ejecutor_test.dart -d <id-Android>` con el teléfono conectado. Registrar fotos originales, scores y estados observados; no aprobar CP04 sin ejecutar la comparación con Colab.

## Trazabilidad CP04 y comparador (16-11-2026)

La revisión del generador confirmó que solo leía el primer nivel, ignoraba fotos ilegibles, aceptaba salida vacía, no exigía las huellas de modelos y no identificaba cultivo/partición/ruta. Se corrigió en `colab/generar_referencias_integracion.py`: selección CSV de rutas relativas con subcarpetas, conteos JSON por cultivo/partición, verificación SHA-256 de ambos modelos antes de inferir, versiones efectivas exigidas por argumento y manifiesto de error ante cualquier exclusión o conteo incompleto. Cada foto de validación se puntúa únicamente con el modelo de su cultivo. La guía exacta está en `colab/REFERENCIAS_CP04.md`.

`integration_test/concordancia_test.dart` carga los mismos bytes originales, prepara el tensor con el código Flutter, ejecuta el motor asíncrono y exporta JSON y CSV con diferencias de tensor, scores, tolerancia fija de score y coincidencia de categoría. La evaluación metodológica usa puntuación y categoría; el tensor es diagnóstico. `TENSOR_MAX_ABS` es opcional y solo añade un recuento técnico si existe un límite justificado y documentado. `lib/comparacion_referencias.dart` tiene pruebas unitarias que muestran que un tensor puede diferir aunque score y categoría cumplan. El directorio de fixtures se incluye como asset para la prueba; retirar las fotos de allí antes de generar un APK de distribución.

**CP04 permanece pendiente.** Faltan la versión efectiva de TensorFlow/Pillow del experimento, fotos originales, selección y conteos reales, ejecución del generador en Colab, ejecución de la comparación en Samsung y cotejo literal con el Word. Ningún score nuevo se atribuye a las mediciones históricas. La ejecución local verificó solo la validación del manifiesto y la lógica del comparador, no la concordancia de los modelos sobre fotografías reales.

Verificación del cambio del 16-11-2026: `py -3.12 -m unittest discover -s colab -p test_generar_referencias_integracion.py -v` pasó **4 pruebas**, incluida la generación completa hacia una salida nueva con backend controlado; `flutter test` pasó **36 pruebas y omitió una** por la biblioteca TFLite ausente en el VM de Windows; `flutter analyze` informó **No issues found**; `flutter build apk --release` generó el APK de **70,8 MB**. La inspección del APK confirmó que solo `integration_test/fixtures/README.txt` se incorporó desde el directorio de referencias: no hay fotos originales en el paquete actual. La prueba `integration_test/concordancia_test.dart` quedó compilable y analizada, pero **no ejecutada en Android** porque no hay Samsung conectado ni referencias reales.
