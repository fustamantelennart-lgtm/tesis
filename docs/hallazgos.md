# Contraste previo de hallazgos (15-11-2026)

## Contraste CP04 corregido en Samsung (18–19-11-2026)

El fallo anterior de LDPlayer se investigó por etapas. La prueba independiente con Pillow 11.3.0 cubrió orientaciones EXIF 1–8 y mostró el riesgo de aplicar la orientación dos veces; la verificación local de las 629 imágenes encontró RGB coincidente con Pillow tras la corrección del decodificador. La ejecución posterior en Samsung SM-A166M separó tensores de Colab directos en ambos motores (fase A) y preprocesamiento desde originales (fase B). Ambas fases cubrieron 217 arroz y 412 caña con 0 errores, 0 incumplimientos de score y 0 diferencias de categoría. El tensor no es idéntico bit a bit: su mayor diferencia absoluta fue 9,983778 × 10⁻⁶ en arroz y 5,960464 × 10⁻⁷ en caña; estas métricas no se usaron como criterio obligatorio. La fase B reanudó 394 checkpoints tras una desconexión USB. [Informe y evidencias Samsung](../evidencia/cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md). La aprobación formal de CP04 sigue sujeta a revisión de esta evidencia; el comparador no la marca automáticamente. El hallazgo de LDPlayer abajo se conserva como registro de la versión anterior.

## Hallazgo CP04 observado en LDPlayer (18-11-2026)

La ejecución completa `1795038207632528_881fd9f5` verificó y comparó las 629 fotografías en LDPlayer, sin errores de ejecución. El criterio de score falló en 171/217 de arroz y 216/412 de caña; la categoría difirió en 2 y 192, respectivamente. Los 629 tensores difirieron numéricamente, con métricas separadas y sin límite obligatorio inventado. El informe es `comparacion_falla`, por lo que CP04 no se aprueba. Las fotografías, SHA e informes íntegros están en [INFORME_CP04_LDPLAYER.md](../evidencia/cp04_1_ldplayer_falla/INFORME_CP04_LDPLAYER.md). Las notas posteriores que dicen que no había referencias o ejecución CP04 describen revisiones anteriores. LDPlayer no equivale al Samsung físico ni a sus tiempos de inferencia.

## Verificaciones previas a la ejecución completa (18-11-2026)

La prueba del procedimiento Android confirmó que `adb shell mkdir` crea carpetas externas con propietario `shell`, lo que impide a `run-as` escribir allí. Se cambió la primera apertura del test para crear `entrada` y `salidas` desde el proceso de la app. La actualización se hizo con `adb install -r` después de verificar un respaldo binario local; no se desinstaló ni se ejecutó `pm clear`. La transferencia de ida y vuelta de un README pequeño conservó su SHA-256. Esta observación **no** constituye comparación CP04 de fotografías.

La compilación release detectó que el registrador Android generado hace referencia a `integration_test` sin enlazarlo en esa variante. Se añadió su dependencia release en Gradle; la compilación posterior concluyó y el APK no contiene referencias CP04. No se alteraron modelos ni umbrales.

La prueba anterior de apertura/reanudación usaba un registro simulado sin caso. Se añadió una prueba con SQLite real, caso activo y revisión pendiente, que compara antes y después actividad, consulta, caso, estado y fechas de la revisión. La reconstrucción v4 dependía de vencimientos crecientes; con un reloj que retrocede daba una fecha incorrecta. El esquema v5 conserva el valor legado y marca el origen reconstruido usando consultas, caso y vencimiento menos plazo. Las referencias CP04 ya existen; el comparador anterior las empaquetaba en el APK y solo exportaba al final. Ahora usa archivos externos, checkpoints por fotografía y reanudación condicionada a identidad verificable.

Según la revisión comunicada por el usuario, CP01–CP18 ya fueron cotejados con el Word; los apartados históricos de este archivo que dicen que faltaba ese cotejo no describen el estado actual. Ninguna prueba Android o recepción de aviso se declara aprobada sin observación.

> **Registro anterior a la ejecución completa, 18-11-2026.** En ese momento los originales y tensores CP04 ya existían, pero faltaba compararlos. La ejecución posterior en LDPlayer se documenta al inicio de este archivo. El cotejo de CP01–CP18 con el Word fue comunicado por el usuario como realizado en su revisión; esta ejecución no repitió la lectura.

## Hallazgos del agente contrastados antes de editar

| Hallazgo | Comprobación contra código y prueba previa | Corrección y límite |
|---|---|---|
| Revisión sin fecha de creación | Confirmado: esquema v3 solo tenía vencimiento y atención; la regresión obtuvo `null`. | Esquema v4 y migración; prueba de creación, atención anticipada y migración. La fecha histórica migrada es reconstruida. |
| Aviso agrupado sin relaciones completas ni destino de caso único | Confirmado: un grupo guardaba como máximo `revision_id`; una sola coincidencia abría `pendientes`. La regresión falló. | Tabla `avisos_relaciones`, motivos por revisión y destino de caso cuando hay uno; pruebas de una y varias revisiones/casos. |
| Revisión vencida indistinguible de pendiente futura | Confirmado en lista y detalle; la prueba de widget no halló la etiqueta. | Se muestra `Revisión pendiente vencida`, sin cambiar el estado persistente ni presumir entrega. |
| Reanudación etiquetada como apertura | Confirmado: `_reanudar` registraba `apertura`. | Registra `reanudacion`; prueba de ciclo de vida con doble. |
| Datos y evidencias CP04 ausentes | **No se reproduce en esta versión:** manifiesto `listo` y 1258 binarios presentes. | Preservados; el registro de concordancia anterior no acredita comparación completa. CP04 permanece pendiente. |
| Riesgo de instalación sobre datos del emulador | Confirmado que el paquete ya estaba instalado; `run-as` mostró solo archivos de ejecución, caché y `profileInstalled`, sin base SQLite ni informes privados. | Revisar procedimiento antes de cada integración; no desinstalar para resolver migraciones. No hay prueba física de Samsung. |

La suite local completa pasó 42 pruebas y omitió una por la DLL TFLite de Windows. `flutter analyze` no informó incidencias. La compilación y cualquier ejecución nueva en Android se consignan en `bitacora_avance.md`; no se declaran aprobadas por esta tabla.

Se cotejó el adjunto del usuario con `lib/`, las pruebas y Android antes de modificar el código. **Confirmado** significa que se observó en el código; **sin reproducción física** significa que falta el Samsung o las referencias externas. Ningún hallazgo directamente comprobable resultó falso.

| Hallazgo | Resultado del contraste | Evidencia previa |
|---|---|---|
| Inactividad no se reprograma | Confirmado | `avisos.dart` comparaba solo identificador en `existing` |
| Caso de navegación y revisión mezclados | Confirmado | `main.dart` usaba `casoAbierto` con `revisionActiva` |
| Revisión residual tras guardar | Confirmado | Se limpiaba únicamente en `onGuardado` al pulsar “Ver consultas” |
| Navegación/cultivo durante operación | Confirmado | La barra y el selector permanecían activos mientras `Diagnostico.ocupado` |
| Permiso solo al iniciar | Confirmado | `_reanudar` no consultaba permiso de Android |
| Fallos de programación invisibles | Confirmado | `reconciliar` guardaba estado y terminaba normalmente |
| Concordancia TensorFlow | No demostrada | Solo existía prueba de imagen constante; faltan CSV, metadatos e imágenes originales |
| Coincidencia de varios casos | Confirmado | Cada revisión recibía aviso propio y la inactividad solo se suprimía |
| Colisiones de ID Android | Confirmado como riesgo | ID calculado por hash de 31 bits sin unicidad |
| Futuro fallido de SQLite | Confirmado | `_opening ??= _abrir()` no lo restablecía tras error |
| Copia parcial y huérfanos | Confirmado | `origen.copy` ocurría antes del `try`; no había barrido al iniciar |
| Android/SQLite desincronizados | Confirmado | `existing.contains(id)` omitía reparar la fila persistida |
| Pérdida de eventos de aviso | Confirmado | `ConflictAlgorithm.replace` sustituía el estado previo |
| Horas UTC en interfaz | Confirmado | Las fechas ISO UTC se imprimían directamente |
| Errores de exportación invisibles | Confirmado | `_exportar` no capturaba excepciones |
| `retrieveLostData()` | Confirmado ausente | No aparecía en `main.dart` |
| Preparación síncrona | Confirmado en código; efecto físico sin reproducción | `PreparadorImagen.preparar` se llamaba desde el isolate UI |
| Fotos/consultas en detalle | Confirmado ausente | `CasoDetalle` solo consultaba `casos` y `revisiones` |
| Invariantes y migración | Confirmado como cobertura insuficiente | No había índice de pendiente único ni pruebas de migración o score inválido |
| Avisos vencidos/reinicio | Sin reproducción física | El código registraba vencido sin evidencia de entrega; no hay Samsung conectado |
| Manifiesto combinado/release | Pendiente de comprobación | La entrega anterior solo compiló debug |

El Word, `referencias_validacion.csv`, metadatos de conversión y fotografías originales siguen ausentes del proyecto y de los adjuntos disponibles. El criterio CP04 no puede aprobarse sin ellos.

## Resolución implementada

| Área | Corrección y prueba | Límite restante |
|---|---|---|
| Inactividad y agrupación | Se cotejan fecha, texto y destino; se cancela y reprograma si cambian. Revisiones del mismo instante se agrupan y llevan a la lista de pendientes. Pruebas con uno y varios casos, apertura y atención total. | Recepción real en Android sin observar. |
| Contexto y navegación | `ControlFlujo` conserva caso, revisión y cultivo juntos; bloquea cambios durante el análisis; cancela explícitamente y limpia al guardar. Pruebas de cambio, duplicación y destino diferido. | Recorrido táctil en Samsung pendiente. |
| Permisos y errores | Se consulta permiso al reanudar, el resumen de reconciliación llega a la interfaz y el historial muestra avisos problemáticos. Prueba de permiso denegado, concedido y fallo. | Cambio real desde Ajustes pendiente. |
| Identidad y consistencia de avisos | Números Android secuenciales persistentes, historial de eventos y estados `solicitado`/`programado`. Una reconciliación repara programación Android aceptada con escritura SQLite fallida. Pruebas de colisión evitada, fallo parcial y reinicio simulado. | No existe evidencia de entrega por el SO. |
| SQLite e imágenes | Reintento de apertura, migración 2→3, validación de puntuación/umbral/clase/cultivo, índice de pendiente único, copia provisional con limpieza y recuperación de huérfanos a carpeta separada. Pruebas de errores y migración. | Migración sobre datos reales del teléfono pendiente. |
| Cámara y galería | `retrieveLostData()` recupera la foto con selección persistente e ID idempotente; prueba de reinicio de selección y consulta única. | Muerte real de actividad Android pendiente. |
| Procesamiento | Pruebas de gradiente, relleno asimétrico y orientación EXIF. Se detectó que el decodificador JPEG no trasladaba EXIF al objeto; ahora se lee del original. La preparación usa `compute`; el diagnóstico usa `IsolateInterpreter`. | Falta comparación con TensorFlow sobre imágenes originales y prueba de rendimiento en teléfono. |
| Interfaz | Fechas locales explícitas, fotos/consultas por caso, errores visibles de exportación. | Inspección visual en teléfono pendiente. |

La versión medida anteriormente sigue usando `Motor.inferir` desde `medicion.dart`. El diagnóstico nuevo usa el mismo modelo y un hilo mediante un ejecutor asíncrono; sus tiempos y su comportamiento no deben atribuirse a las mediciones históricas.

## Revisión integral adicional (15-11-2026)

Se contrastó la solicitud nueva con el código actual antes de editar. Los fallos de navegación diferida, copia frente a barrido y alarma inexacta vencida se reprodujeron con pruebas que **fallaron antes de la corrección**. La prueba de inferencia real falló por ausencia de `libtensorflowlite_c-win.dll` en el VM de Windows; esto es un límite del entorno, no evidencia de un fallo Android.

| Hallazgo | Contraste y corrección | Prueba/evidencia | Límite |
|---|---|---|---|
| Geometría `resize_with_pad` | Confirmado: se usaba `.round()` y mitad del espacio entero. Se implementó geometría float32 con `floor` de dimensiones y relleno flotante según fuente de TensorFlow 2.20. | El caso 3×1 ya ocupa 74 filas; pruebas de imagen y EXIF. | No se conoce la versión efectiva de TensorFlow de Colab. No se ejecutó comparación tensor a tensor ni de scores con fotos originales. |
| Inicialización interactiva | Confirmado: `_iniciar()` corría mientras se construía la interfaz operativa. Ahora hay carga, error y reintento; una respuesta de `retrieveLostData()` se conserva si falla una fase posterior. | Widgets: inicio lento, selección antigua pendiente, fallo parcial y reintento. | Muerte de actividad y selector físico pendientes en teléfono. |
| Copia y barrido | Confirmado con prueba fallida: el barrido movía un `.partial` durante la copia. Se serializan guardar, barrer y cerrar; además se normalizan rutas al reconocer fotos referidas. | Regresión con copia detenida por `Completer`; después del arreglo la foto registrada existe y no pasa a recuperadas. | Falta repetir con almacenamiento del Samsung. |
| Resultado visual entre revisiones | Confirmado por inspección: la clave solo incluía cultivo. Se borra foto/score/ID al entrar en otra revisión, se indica caso y revisión y se conserva el resultado al confirmar la anterior. | Widgets: revisión A→B y confirmación→nueva revisión. | Falta recorrido completo con cámara y error de inferencia físico. |
| Navegación diferida | Confirmado con prueba fallida: `consumirDestino()` liberaba el destino mientras seguía activa la revisión. Ahora lo conserva hasta confirmar o cancelar expresamente. El último aviso recibido sustituye al anterior. | Regresión de operación fallida y avisos consecutivos; callbacks de `main.dart` revisados. | Recepción real de múltiples notificaciones pendiente. |
| Alarma vencida inexacta | Confirmado con prueba fallida: se cancelaba la solicitud pendiente por superar el plazo. Ahora se conserva si coincide con contenido y destino; se registra `vencido_pendiente_android` y se muestra el pendiente. Sin solicitud Android queda `vencido_sin_entrega_verificada`, sin reprogramar en el pasado. | Pruebas de alarma tardía, permiso recuperado, reinicio y atención total. | Android no informa entrega verificada a esta capa; probar en Samsung. |
| Ejecutor asíncrono válido | Cobertura insuficiente confirmada: solo se rechazaba un tensor corto. Se añadió prueba de equivalencia directa/asíncrona con ambos modelos y consultas repetidas, más prueba de integración Android. | El VM de Windows no cargó `libtensorflowlite_c-win.dll`; la prueba local se omite explícitamente. | Pendiente en teléfono; no atribuirle tiempos históricos. |

No se reprodujo una diferencia numérica concreta de score frente a Colab porque faltan `TESIS-VERSION ACTUALIZADA (4).docx`, `referencias_validacion.csv`, fotografías originales y metadatos de conversión. Tampoco pudo cotejarse literalmente RF01–RF12 ni CP01–CP18. Ninguna prueba de teléfono fue aprobada sin observación.

## Seguimiento de referencias CP04 (16-11-2026)

Se confirmaron los cinco problemas del generador señalado por el usuario: lectura superficial, exclusión silenciosa, manifiesto potencialmente vacío, ausencia de verificación obligatoria de modelos e identidad incompleta de fotos. El generador ahora exige CSV de selección y JSON de conteos, recorre subcarpetas por ruta relativa, verifica versiones y SHA de modelos, registra cada error y falla si no procesa todo. Las pruebas Python cubren subcarpetas, duplicados, ausencias, conteos y modelos alterados.

Se añadió una prueba de integración Android que compara **valores** Float32 de tensor (máximo, media, RMSE, distintos y fuera de límite), score con el criterio fijo y categoría. Exporta CSV/JSON incluso si las comparaciones fallan. La lógica aislada de comparación tiene pruebas Dart. No se ejecutó la comparación real: siguen ausentes las entradas de validación y el Samsung. CP04 continúa **pendiente**; no se inventó una tolerancia de tensor ni una versión de TensorFlow.

## Corrección del recorrido de generación (16-11-2026)

Una prueba nueva de recorrido completo con salida inexistente falló primero: `FileNotFoundError` al escribir `original_*.bin`, seguida de `procesadas: 0` y manifiesto `error`. Se creó la carpeta antes del bucle de escritura. La prueba ahora verifica original, tensor y manifiesto `listo` con un backend TensorFlow controlado; no pretende demostrar concordancia numérica. También se precisó que el resultado metodológico de la prueba Android depende de score y categoría. Las métricas de tensor se exportan como diagnóstico y ningún límite adicional se hace obligatorio sin justificación. El informe señala expresamente que CP04 no se aprueba automáticamente.
