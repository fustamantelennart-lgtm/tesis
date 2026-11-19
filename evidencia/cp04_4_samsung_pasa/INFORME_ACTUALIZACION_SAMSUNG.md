# Actualización de Campo CNN en Samsung SM-A166M

Ejecución observada el 19 de noviembre de 2026. Se actualizó únicamente `com.example.campo_cnn` con `adb install -r`, sin desinstalar ni ejecutar `pm clear`.

## Protección y compatibilidad previas

- Los informes CP04 completos (JSON, CSV y 629 checkpoints) ya estaban extraídos en `salidas_finales/`. El JSON final conserva SHA-256 `074da84f2de3f45d42dfab831ff0c8f823cd5825a036f1e68ec7083285a0361`. La app de prueba `com.example.campo_cnn.cp04` y su informe permanecen en el Samsung después de actualizar la app normal.
- Se extrajo una copia del APK habitual anterior como `aplicacion_normal_antes.apk`, SHA-256 `f8ceef8875069e1233a5b98f9b9b00626932967389b9ea0a42a90de871a9e5cc`.
- APK anterior y corregido: `applicationId=com.example.campo_cnn`, `versionCode=1`, `versionName=0.1.0`, certificado V2 SHA-256 `f472f76e83a9bc4f488d71ab565b096b1ed4907f11d1de9f11ef00a58299e13d`. El detalle está en `compatibilidad_apk_normal.txt`.
- La instalación no es depurable: `run-as` no permite extraer SQLite y fotos privadas. La función Exportar de la app comparte JSON/CSV de consultas, pero no constituye respaldo completo de fotos, casos y revisiones. La protección aplicada para la actualización fue conservar el APK previo y usar [`adb install -r`](https://developer.android.com/tools/adb?hl=es-419), cuya opción `-r` conserva los datos de la aplicación.

## Resultado de instalación

`instalacion_aplicacion_normal.log` registra `Success`. El APK extraído del Samsung después de instalar tiene SHA-256 `fd9af63a7d98a20d6f5d5ab16ee2d9c4278fc941fe28e513e455d130d528f196`, idéntico al APK corregido preparado. Android mantuvo `firstInstallTime=2026-11-14 17:53:26` y `dataDir=/data/user/0/com.example.campo_cnn`; cambió `lastUpdateTime` al 19 de noviembre. La app inició y su proceso permaneció activo sin errores AndroidRuntime/Flutter observados.

**Verificación de contenido pendiente de observación:** el teléfono estaba bloqueado y apareció un diálogo Android de permiso. No se han comparado aún en pantalla los recuentos y detalles de consultas, fotos, casos y revisiones, ni se ha probado cámara, galería, modo avión, seguimiento, cierre o recepción de avisos reales. La continuidad de `dataDir` por sí sola no acredita la integridad de cada registro. No se marca CP01–CP18 como aprobado por esta instalación.
