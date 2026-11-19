# CP04 en Samsung SM-A166M

Ejecución observada el 18–19 de noviembre de 2026 en el Samsung SM-A166M físico, Android 15 (SDK 35). Los resultados corresponden a este teléfono y a la identidad de código `a37762478090a02833a7def451d360a6a36fbfda35f9c31b565328d2b6299a07`. No son mediciones históricas de tiempo de inferencia.

## Entradas y conservación

Se transfirieron las 629 fotografías originales y los 629 tensores de validación a la aplicación de prueba aislada `com.example.campo_cnn.cp04`. Antes de ejecutar, los SHA-256 de los 1.260 archivos transferidos, incluido el manifiesto y README, coincidieron con las referencias locales. La aplicación habitual `com.example.campo_cnn` siguió instalada sin actualización, limpieza ni desinstalación. El manifiesto tiene SHA-256 `912ca1d6932025f8583bf3ef1ec5b362b6b702c067cadf41578e18e53af7ac6d`.

La prueba B perdió la conexión USB después de guardar la fila 394. Se extrajeron los checkpoints, se reconectó el teléfono y se continuó con el mismo ID `1795055343416366_4eb9b22`; el informe final registra 394 filas reutilizadas. Los JSON, CSV, checkpoints y registros completos permanecen en `salidas_finales/` (checkpoints en `checkpoints_filas.zip` y `checkpoints_tensores.zip`) y en el almacenamiento externo de la aplicación de prueba. La ejecución fallida anterior de LDPlayer permanece intacta; su JSON conserva SHA-256 `485d9458268b2df6e62036ee46ceedf2e30fb2ca7a10fe366f1906381d1ce943`.

## Resultados

La fase A introdujo los 629 tensores de Colab directamente en `Motor` y `MotorDiagnostico`: 217 arroz y 412 caña, 0 errores, 0 scores fuera de tolerancia y 0 categorías distintas para ambos ejecutores. Su informe es [completa_tensores_1795054935047517_851f4d24.json](salidas_finales/completa_tensores_1795054935047517_851f4d24.json).

La fase B procesó los bytes de las 629 fotografías originales, verificó las 629 parejas de archivos y produjo [comparacion_1795055343416366_4eb9b22_1795069997505893_27ffab92.json](salidas_finales/comparacion_1795055343416366_4eb9b22_1795069997505893_27ffab92.json) y su [CSV por fotografía](salidas_finales/comparacion_1795055343416366_4eb9b22_1795069997505893_27ffab92.csv). El estado es `comparacion_pasa` y `cp04_aprobado_automaticamente=false`.

| Cultivo | Fotos | Errores de ejecución | Scores fuera de tolerancia | Categorías distintas | Tensores numéricamente distintos | Mayor diferencia absoluta de tensor | Mayor error absoluto de score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Arroz | 217 | 0 | 0 | 0 | 217 | 9,983778 × 10⁻⁶ | 5,960464 × 10⁻⁷ |
| Caña | 412 | 0 | 0 | 0 | 412 | 5,960464 × 10⁻⁷ | 2,384186 × 10⁻⁷ |

El criterio de score conservado fue `abs(android-colab) <= 1e-5 + 1e-4*abs(colab)` y la categoría debía coincidir. Las diferencias de tensor se registran por separado como diagnóstico; no se añadió un límite obligatorio. No hubo fotografías afectadas por incumplimientos de score, categoría o ejecución. Las diferencias numéricas de tensor siguen visibles en cada fila del JSON y CSV.

La revisión local confirmó 630 líneas en el CSV (cabecera y 629 fotos), 629 rutas únicas en el orden del manifiesto y 629 SHA de originales y tensores correctos. [verificacion_informes.json](verificacion_informes.json) registra estas comprobaciones. La matriz CP04 puede revisarse con esta evidencia, pero no se marca como aprobada automáticamente.

El campo `indice` aparece en las 394 filas reutilizadas del JSON final y falta en las 235 filas calculadas tras reanudar. Las 629 filas conservan `ruta_relativa` única y el mismo orden que el manifiesto; el CSV también incluye las 629 rutas. Esta diferencia de formato no altera la comparación de score y categoría, pero conviene uniformarla en una revisión posterior del exportador.

## Herramientas y estado final

`flutter analyze --no-pub` terminó sin incidencias y las 28 pruebas de `test/decodificador_jpeg_test.dart` y `test/preprocesamiento_test.dart` pasaron. Se construyeron APK debug aislados para A y B con el mismo código evaluado; el identificador del APK se inspeccionó antes de instalarlo. Los logs de compilación, transferencia, fase A, fase B y reanudación están en esta carpeta.

Se restauró `stay_on_while_plugged_in` de `2` a su valor previo `0`; se detuvo la aplicación de prueba y se abrió la aplicación habitual. El paquete y los informes CP04 aislados se conservaron, sin desinstalación ni limpieza de datos.

Se compiló además el APK normal corregido `Campo_CNN_Samsung_aplicacion_corregida_release.apk` (no versionado; se regenera con `flutter build apk --release`), SHA-256 `fd9af63a7d98a20d6f5d5ab16ee2d9c4278fc941fe28e513e455d130d528f196`. Su paquete es `com.example.campo_cnn`, contiene los dos modelos y ninguna referencia CP04. **Actualización posterior:** el 19 de noviembre se verificó el mismo identificador y certificado, se conservó el APK anterior y se instaló con `adb install -r` sin borrar datos. La comprobación visual del contenido de SQLite y fotos sigue pendiente; véase [INFORME_ACTUALIZACION_SAMSUNG.md](INFORME_ACTUALIZACION_SAMSUNG.md).
