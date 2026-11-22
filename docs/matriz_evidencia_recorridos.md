# Matriz de evidencia de recorridos de la aplicación

Esta matriz separa la evidencia visual de la evidencia automatizada. Una
solicitud programada no se interpreta como recepción de una notificación en
Android. Las fechas que muestra la aplicación se convierten a hora local.

| Caso Tabla IX | Pantalla o recorrido | Archivo de evidencia | Resultado observado | Entorno |
|---|---|---|---|---|
| CP01–CP03 | Diagnóstico: cultivo, cámara/galería, fotografía y resultado | Pendiente de captura | La interfaz contiene selección de cultivo, cámara, galería, fotografía, resultado local y enlace a Consultas. | Flutter Android, por comprobar visualmente |
| CP04 | Concordancia Android–Colab | `evidencia/cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md` | Referencia existente; no requiere pantalla adicional. | Samsung SM-A166M, Android 15 |
| CP05–CP06 | Historial de consultas y revisiones pendientes | Pendiente de captura | Un positivo debe crear caso y revisión; una consulta sana inicial se conserva en historial sin caso. | Android físico pendiente |
| CP07–CP08 | Detalle del caso: fecha programada y plazo | Pendiente de captura | La app muestra 72 horas para arroz y 7 días para caña; el estado programado no acredita recepción. | Android físico pendiente |
| CP09 | Atención positiva | Pendiente de captura consecutiva | La revisión atendida permanece visible y el nuevo positivo deja la siguiente revisión pendiente. | Android físico pendiente |
| CP10 | Atención sana | Pendiente de captura consecutiva | El caso pasa a `Seguimiento cerrado` y conserva historial y revisiones. | Android físico pendiente |
| CP11–CP15 | Avisos registrados | Pendiente de captura | La pantalla distingue aviso de revisión, inactividad, agrupado, cancelado, permiso denegado y fallo. La programación/agrupación se respalda además con pruebas de reloj controlado. | Pruebas Windows; recepción Android pendiente |
| CP13, CP16 | Apertura/reapertura y persistencia | Pendiente de captura consecutiva | El estado se obtiene desde SQLite al abrir Consultas y el detalle del caso. | Android físico pendiente |
| CP17 | Archivo ilegible | Pendiente de captura | El flujo debe mostrar error sin consulta válida en historial. | Android físico pendiente |
| CP18 | Permiso denegado | Pendiente de captura | El aviso se registra como permiso denegado; no se declara entrega ficticia. | Android físico pendiente |

## Capturas prioritarias y títulos propuestos

1. **Figura X. Consulta de una fotografía de arroz y resultado local de clasificación.** Debe mostrar el cultivo, la fotografía, la puntuación, el umbral y el resultado.
2. **Figura X. Historial de consultas y revisión pendiente creada después de un resultado positivo.** Debe mostrar la consulta positiva, la revisión y la fecha programada.
3. **Figura X. Detalle de un seguimiento de arroz con revisión programada a 72 horas.** Debe mostrar resultado inicial, fecha local, estado y acción «Atender revisión».
4. **Figura X. Detalle de un seguimiento de caña de azúcar con revisión programada a siete días.** Debe mostrar el plazo propio del cultivo.
5. **Figura X. Atención positiva de una revisión y programación de la revisión siguiente.** Usar dos capturas consecutivas del mismo caso.
6. **Figura X. Cierre del seguimiento tras una revisión con resultado sano.** Debe mostrar «Seguimiento cerrado» y el historial conservado.
7. **Figura X. Estado de avisos registrados para una revisión pendiente.** Debe distinguir programación de recepción efectiva.
8. **Figura X. Aviso local de Android y apertura del seguimiento asociado.** Solo se incorpora cuando se capture el panel del sistema y el destino al tocarlo.

Los casos de recepción real de notificaciones, permisos de Android, cámara,
galería, archivo ilegible y reapertura visual quedan explícitamente pendientes
hasta realizarse en un equipo Android. La evidencia automatizada disponible y
su alcance están descritos en `docs/trazabilidad_cp.md`.
