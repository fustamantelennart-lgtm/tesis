# Evidencia

Registros originales de las ejecuciones y verificaciones, en orden cronológico. Los informes JSON/CSV se conservan como archivos y sus SHA-256 coinciden con los citados en cada informe. Los checkpoints por fotografía (un JSON por cada una de las 629 fotos) están comprimidos en `.zip`, byte a byte, para no llenar el repositorio con miles de archivos.

| Carpeta | Qué contiene | Resultado |
|---|---|---|
| [cp04_1_ldplayer_falla/](cp04_1_ldplayer_falla/INFORME_CP04_LDPLAYER.md) | Primera ejecución completa de CP04, en el emulador LDPlayer (18-11-2026), antes de las correcciones | `comparacion_falla`: 387 scores fuera de tolerancia y 194 categorías distintas |
| [cp04_2_investigacion_exif/](cp04_2_investigacion_exif/) | Diagnóstico de la doble orientación EXIF: regresiones antes/después, muestra de 6 fotos y comparación por etapas con Pillow | Causa en caña: rotación aplicada dos veces |
| [cp04_3_decodificador/](cp04_3_decodificador/) | Verificación del decodificador JPEG equivalente a libjpeg-turbo sobre las 629 fotos | RGB idéntico a Pillow en 629/629; tensor ≤ 1×10⁻⁵ de Colab |
| [cp04_4_samsung_pasa/](cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md) | Ejecución completa con el código corregido en Samsung SM-A166M físico (18–19-11-2026), fases A y B, y actualización de la app normal | `comparacion_pasa`: 0 scores fuera de tolerancia y 0 categorías distintas |
| [registros_app/](registros_app/) | Logs de compilación, pruebas y preparación del emulador (15–18-11-2026) y captura de pantalla de LDPlayer | — |

## Archivos comprimidos

| Archivo | Contenido | SHA-256 |
|---|---|---|
| `cp04_1_ldplayer_falla/salidas_despues/checkpoints_filas.zip` | 629 `fila_*.json` de la ejecución en LDPlayer | `a7f6336741832f7226b51926fb4c7d35ac67ae2c740c2d5c680638fcd31bc5ad` |
| `cp04_4_samsung_pasa/salidas_fase_a/checkpoints_tensores.zip` | 629 `diagnostico_tensor_*.json` de la fase A | `d141295d45237f268910af83f8c97901e0d81106a73cba1b438962e4e0ba4c6b` |
| `cp04_4_samsung_pasa/salidas_finales/checkpoints_filas.zip` | 629 `fila_*.json` de la fase B | `0ce02b8bbffc817c03856a811e74094fb94cf27180940d9abc0c1fd7f9a5a53e` |
| `cp04_4_samsung_pasa/salidas_finales/checkpoints_tensores.zip` | 629 `diagnostico_tensor_*.json` incluidos en la extracción final | `c9c9ec4b46bf405b6bb3a064bbe51211bfdf1780ac3e17ea00f518d75b4a57af` |
| `cp04_4_samsung_pasa/capturas_intermedias.zip` | Extracciones de seguridad durante la fase B (`salidas_parcial_b`, `_0323`, `_0475`, `salidas_reconexion_0394`), 4.859 archivos; muestran la reanudación tras la desconexión USB en la fila 394 | `698d41570726418f318c8ec055f5822514df4eca455b3b9949505d00424c296e` |

Antes de eliminar los originales, se comprobó que cada archivo comprimido tiene el mismo SHA-256 que su original.

## No incluido

- Respaldos `.tgz` del espacio privado de la app y APK extraídos del teléfono (`aplicacion_normal_*.apk`). Sus SHA-256 están en los informes.
- Imágenes RGB de Pillow de `cp04_2_investigacion_exif/pillow_etapas/` (17–22 MB cada una), derivadas de las fotografías de validación; se regeneran con `campo_cnn_app/scripts/generar_etapas_pillow_cp04.py`.
