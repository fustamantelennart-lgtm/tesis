# Agente de seguimiento fitosanitario: especificación implementada

## Objetivo y alcance

Campo CNN clasifica fotografías de arroz y caña con dos CNN locales. El agente usa reglas temporales y estado SQLite para mantener revisiones de casos positivos y solicitar avisos locales. No identifica la misma planta o parcela automáticamente, no diagnostica un patógeno por sí solo, no prescribe tratamientos y no aprende reglas. Los plazos de 72 horas y siete días son reglas operativas de esta aplicación; no se presentan como intervalos agronómicos óptimos.

## Arquitectura, entradas y estado

`main.dart` recibe apertura, reanudación, selección y resultado de fotografía y navegación desde avisos. `ControlFlujo` conserva juntos cultivo, caso y revisión y difiere un destino recibido durante una operación. `PreparadorImagen` y `DiagnosticoMotor` preparan la foto y ejecutan la CNN. `Registro` guarda la consulta y transiciones en una transacción. `ReglasSeguimiento` calcula los plazos. `Avisos` compara estado SQLite y solicitudes Android con una cola serializada. `Consultas` muestra historial y ofrece atender una revisión. `medicion.dart` conserva la ruta histórica de medición, separada del agente.

Una **consulta** es una fotografía válida con inferencia y guardado correctos; conserva cultivo, instante UTC, ruta estable, clase, puntuación, umbral y SHA del modelo. Un **caso** activo agrupa consultas vinculadas expresamente por el usuario y pasa a cerrado al atender con un resultado sano. Una **revisión** guarda creación, vencimiento y estado pendiente o atendida. Una revisión vencida sigue pendiente. Un **aviso** registra objetivo, solicitud, estado de programación, contenido y destino. `avisos_relaciones` conserva cada revisión y motivo (`revision` o `inactividad`) de un aviso agrupado. La aceptación de Android no equivale a entrega.

## Reglas y evidencia automatizada

| Regla | Acción implementada | Prueba |
|---|---|---|
| A, arroz positivo inicial | Consulta, caso activo, revisión a 72 horas | `registro_test.dart`, `reglas_test.dart` |
| B, caña positiva inicial | Consulta, caso activo, revisión a siete días | `registro_test.dart`, `reglas_test.dart` |
| C, sano inicial | Solo consulta, sin caso ni revisión | `registro_test.dart` |
| D, revisión positiva | Atiende anterior y crea siguiente en el mismo caso, desde la nueva consulta | `registro_test.dart` |
| E, revisión sana | Atiende, cierra caso y conserva historial; reconciliación cancela avisos obsoletos | `registro_test.dart`, `avisos_test.dart` |
| F, atención anticipada | Acepta la consulta antes del plazo y calcula el siguiente desde ella | `registro_test.dart` |
| G, cancelación o error | No crea consulta válida ni transición; controla copia e imagen ilegible | `registro_test.dart`, pruebas de flujo, imagen e inicio |
| H, duplicados | Intento idempotente, revisión atendida una sola vez, índice único de pendiente por caso | `registro_test.dart`, pruebas de flujo |
| Inactividad | Aviso a siete días de última actividad, solo con pendientes | `avisos_test.dart`, `inicio_widget_test.dart` |
| Coincidencia | Un aviso por instante UTC exacto, relaciones completas, destino de caso único o lista | `avisos_test.dart` |

La actividad se registra al abrir, reanudar y guardar una consulta. Reconciliar en segundo plano, programar o recibir un aviso no escribe actividad. Abrir desde un aviso cuenta como apertura y no atiende la revisión. Una nueva actividad desplaza la fecha de inactividad; si ya no hay pendientes, la reconciliación cancela su aviso. No hay recordatorio diario.

## Persistencia, agrupación y recuperación

SQLite versión 5 agrega `creado_fuente`, `creado_evidencia` y `creado_utc_legado` a las revisiones existentes. La migración invierte el plazo del vencimiento y lo contrasta con consultas positivas y caso; no presupone vencimientos crecientes cuando el reloj retrocede. Las fechas nuevas son `registrado`, las migradas `reconstruido`, y el valor v4 anterior se conserva. La migración mantiene casos, consultas, revisiones, avisos e identificadores. Hay claves foráneas, índice único de pendiente por caso y validación de consulta/cultivo/umbral/modelo. Consulta y transición se confirman juntas.

Las fotografías válidas se copian a almacenamiento privado; copia, barrido y cierre se serializan. Las copias incompletas se limpian y los huérfanos se apartan sin borrar fotografías referenciadas. La selección persistente y `retrieveLostData()` permiten recuperar cámara/galería sin duplicar una consulta. La apertura fallida puede reintentarse.

`Avisos` agrupa solo fechas y horas UTC idénticas. Si coincide inactividad, registra motivo de inactividad para **todas** las revisiones pendientes, además de los motivos de revisión que vencen en ese instante. Un caso afectado abre su detalle; varios abren pendientes. Los números Android se asignan por secuencia SQLite persistente. La reconciliación compara fecha, contenido, destino, número y estado; cancela o reprograma cambios, y repara fallos parciales entre Android y SQLite. Se refresca el permiso al reanudar. Se registra `solicitado`, `programado`, `permiso_denegado`, `fallo_programacion`, `cancelado`, `vencido_pendiente_android` o `vencido_sin_entrega_verificada` según lo observable. Una solicitud inexacta aún pendiente después de vencer se conserva; sin solicitud no se crea una alarma con fecha pasada. Ningún estado afirma recepción.

## Resultados y límites

CP04 usa un recorrido separado: las 629 referencias se leen del directorio externo propio de la app y se verifican por SHA antes de comparar. Un diario por fotografía y la identidad del código, modelos, manifiesto, criterios y entorno permiten recuperar interrupciones sin mezclar ejecuciones. Los informes tienen nombres únicos. Este mecanismo no cambia las reglas del agente ni los criterios de puntuación y categoría. Su transferencia, respaldo y extracción se documentan en [colab/REFERENCIAS_CP04.md](../campo_cnn_app/colab/REFERENCIAS_CP04.md).

La verificación ejecutada de reglas y UI está en [resultados_agente.md](resultados_agente.md). La trazabilidad CP01–CP18 está en [trazabilidad_cp.md](trazabilidad_cp.md). El cotejo de CP01–CP18 con el Word fue realizado en la revisión comunicada por el usuario; esta ejecución conserva los pendientes sin repetir ese cotejo. Las pruebas con dobles de Android no validan recepción, cámara física ni rendimiento del Samsung. CP04 y medición computacional son verificaciones independientes del agente.

