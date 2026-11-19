# CP04 ejecutado en LDPlayer — 18-11-2026

## Alcance y entorno

La ejecución `1795038207632528_881fd9f5` procesó secuencialmente las 629 fotografías de validación del manifiesto original: 217 de arroz y 412 de caña. El entorno fue **LDPlayer**, conectado por ADB como `emulator-5554` y configurado con Android 14. Android informó `SONY SOV44` e `isPhysicalDevice=true`; son metadatos emulados y **no identifican un Samsung físico**. Esta ejecución no mide ni acredita tiempos de inferencia del Samsung.

El código evaluado tuvo SHA-256 de identidad `dc7401a3ef4a668e4f6617d9e21e75158bcab7a741b0e7ba5e754137881432a1`. El manifiesto tuvo SHA-256 `912ca1d6932025f8583bf3ef1ec5b362b6b702c067cadf41578e18e53af7ac6d`. Los modelos, preprocesamiento, umbrales, selección y tolerancia de score no se modificaron para esta ejecución. `TENSOR_MAX_ABS` quedó sin definir.

Antes de instalar el ejecutor se verificó respaldo privado, espacio libre (46 GB en almacenamiento externo LDPlayer; 33,7 GB en el equipo), manifiesto `listo`, conteos locales y los 1.258 SHA-256 de originales y tensores. ADB transfirió 1.260 archivos (incluidos manifiesto y README), 0 omitidos. En LDPlayer coincidieron el SHA del manifiesto y los 1.258 SHA de binarios. Se instaló el ejecutor con `adb install -r`, sin `pm clear` ni desinstalación.

## Resultado metodológico

El informe JSON tiene estado **`comparacion_falla`**. Registra `total_esperado=629`, `entradas_verificadas=629`, `comparadas=629`, `reutilizadas=0`, 629 filas JSON, 629 filas CSV y 629 checkpoints persistidos. No hubo errores de ejecución. El criterio original fue `abs(android-colab) <= 1e-5 + 1e-4*abs(colab)` y categoría idéntica. CP04 **no se aprueba** con este resultado.

| Cultivo | Comparadas | Errores de ejecución | Score fuera de tolerancia | Categoría diferente | Afectadas por score o categoría |
|---|---:|---:|---:|---:|---:|
| Arroz | 217 | 0 | 171 | 2 | 171 |
| Caña | 412 | 0 | 216 | 192 | 216 |
| **Total** | **629** | **0** | **387** | **194** | **387** |

Las 194 diferencias de categoría están incluidas entre las 387 fotografías fuera de tolerancia de score. Los mayores errores absolutos de score fueron `0.032714903354644775` en `arroz/val/sano/val_arroz_sano_0037.jpg` y `0.9999999466771321` en `cana/val/sano/train_cana_sano_0559.JPG`. Dos ejemplos con categoría distinta en arroz son `arroz/val/piricularia/val_arroz_piricularia_0060.jpg` y `arroz/val/sano/val_arroz_sano_0005.jpg`. En caña, un ejemplo es `cana/val/sano/test_cana_sano_0002.JPG` (score de referencia `0.0006828965269960463`, score Android `1.0`). Las rutas y SHA de **todas** las afectadas están en `fotografias_afectadas.csv`; `scores_fuera_tolerancia.csv` y `categorias_diferentes.csv` permiten revisar cada tipo por separado.

## Tensor: diagnóstico separado

No se fijó un límite obligatorio de tensor. Los 629 tensores Android presentan al menos un valor distinto del tensor de referencia; estas diferencias ayudan a investigar la causa, pero el estado anterior se decide por score y categoría.

| Cultivo | Tensores con diferencias | Mínimo del máximo absoluto por foto | Promedio del máximo absoluto | Mayor máximo absoluto | Fotografía con mayor máximo |
|---|---:|---:|---:|---:|---|
| Arroz | 217/217 | 0.006871551275253296 | 0.01750059400294577 | 0.034970156848430634 | `arroz/val/sano/val_arroz_sano_0047.jpg` |
| Caña | 412/412 | 0.003870785236358643 | 0.9525219245433176 | 1.0000001192092896 | `cana/val/roya/train_cana_roya_0555.jpg` |

El JSON y CSV originales contienen por fotografía máximo, índice, media absoluta, RMSE y cantidad de valores distintos. Se extrajeron además a `tensores_diferentes.csv` para consultarlos por separado del resultado metodológico. La magnitud de caña exige investigación posterior; este informe no atribuye una causa sin comprobarla.

## Evidencia y conservación

En `salidas_despues/` se conservan el JSON y CSV completos, los 629 archivos `fila_*.json` y el metadato `ejecucion_*.json`. Los SHA-256 locales de los informes coinciden con los archivos que permanecen en LDPlayer:

- JSON: `485d9458268b2df6e62036ee46ceedf2e30fb2ca7a10fe366f1906381d1ce943`
- CSV: `808d5540c28dd6c6f3598af60946011f2ad48c2ccca23c93781917f86e298dca`

También se conservan `ejecucion_cp04_ldplayer.log`, `transferencia.log`, `sha256_dispositivo.txt`, `compilacion_cp04.log`, `extraccion.log`, el manifiesto copiado, los resúmenes y las listas de discrepancias. Los respaldos privados verificados antes y después están en `_local/resguardos_android/` (fuera del repositorio): `privado_emulator-5554_20261118_163740_7441520.tgz` y `privado_emulator-5554_20261118_170445_0661856.tgz`. El ejecutor falló la expectativa final porque detectó discrepancias, después de escribir todos los informes.

Finalmente se reinstaló el APK normal con `adb install -r`. LDPlayer necesitó un reinicio sin borrado para iniciar el proceso; después se observó la pantalla «Diagnóstico en campo» y se confirmó que los 629 checkpoints y ambos informes seguían en el dispositivo. `campo_cnn_restaurado.png` conserva la captura final. La recepción real de avisos y la ejecución en Samsung siguen pendientes.
