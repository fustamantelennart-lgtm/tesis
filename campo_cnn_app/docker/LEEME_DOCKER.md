# Campo CNN en Docker

Este contenedor trae el entorno exacto con el que se compiló y verificó Campo CNN: Flutter 3.44.6 (revisión `ee80f08b`), Dart 3.12.2, JDK 21, Android SDK 36, NDK 28.2 y Python con Pillow 11.3.0 / libjpeg-turbo 3.1.1. Con él puedes analizar, probar, compilar los APK y verificar el preprocesamiento CP04 sin instalar nada más que Docker.

**Qué no hace:** no ejecuta la app ni CP04 en Android. Docker no tiene acceso a USB en Windows/macOS y no incluye emulador. Los APK se generan aquí y se instalan desde tu equipo con tu propio `adb`.

## Requisitos

- Docker Desktop (o Docker Engine con Compose v2).
- Unos 12 GB libres de disco (imagen ~6 GB más cachés de Gradle y pub).
- Funciona con la RAM por defecto de Docker Desktop (~4 GB); con 6 GB o más va más holgado. Si Gradle se queda sin memoria, ver *Problemas frecuentes*.
- En Mac con Apple Silicon funciona emulando x86_64, pero es bastante más lento.

## Primer uso

Desde la carpeta `campo_cnn_app`:

```bash
docker compose build                    # 15–30 min la primera vez; verifica cada versión
docker compose run --rm campo todo      # analizar + probar + APK release
```

La primera ejecución descarga Gradle y las dependencias de pub a volúmenes de Docker; las siguientes son rápidas. Los resultados aparecen en `campo_cnn_app/salida_docker/`, cada APK con su `.sha256`.

## Comandos

| Comando | Qué hace |
|---|---|
| `analizar` | `flutter analyze` |
| `probar` | `flutter test`. La prueba de inferencia real se omite porque no hay biblioteca TFLite de escritorio; se cubre en Android. |
| `verificar-cp04` | Con las 629 referencias montadas: genera el RGB de Pillow de cada foto y exige que el decodificador Dart dé **exactamente** los mismos bytes; mide el tensor frente al de Colab. No calcula scores (sin TFLite). Informe en `salida_docker/cp04/`. |
| `identidad` | Huella `CP04_CODE_SHA256` del código evaluado (igual a `scripts/identidad_cp04.ps1`). |
| `apk` | APK release de la app → `Campo_CNN_release.apk` |
| `apk-debug` | APK debug de la app → `Campo_CNN_aplicacion_debug.apk` |
| `apk-cp04 originales` | Comparador CP04 desde fotografías originales (fase B), variante aislada |
| `apk-cp04 tensores <entorno>` | Comparador con tensores de Colab (fase A), p. ej. `Samsung_SM-A166M_Android15` |
| `shell` | Terminal dentro del espacio de trabajo |

Ejemplo: `docker compose run --rm campo apk-cp04 originales`

### Cómo trata el código

Tu carpeta se monta **en solo lectura**. En cada comando el contenedor copia el código a su propio espacio de trabajo (sin `build/`, `.dart_tool/`, `local.properties` ni las referencias) y trabaja ahí. Así nunca rompe una compilación hecha fuera de Docker. Los cambios que hagas en tu editor se recogen en la siguiente ejecución, sin reconstruir la imagen.

## Referencias CP04 (opcional)

`verificar-cp04` necesita `manifest.json`, `original_*.bin` y `tensor_*.bin` (629 + 629 archivos, ~1,6 GB), generados en Colab con `colab/generar_referencias_integracion.py`. No forman parte del código. Si los tienes en `integration_test/fixtures/` se montan solos; si están en otra carpeta:

```bash
CP04_FIXTURES=/ruta/a/las/referencias docker compose run --rm campo verificar-cp04
```

En PowerShell: `$env:CP04_FIXTURES='D:\referencias'; docker compose run --rm campo verificar-cp04`

## Instalar en un dispositivo (fuera de Docker)

**App normal.** Para conservar los datos del usuario, actualiza siempre sin desinstalar:

```bash
adb install -r salida_docker/Campo_CNN_release.apk
```

No uses `adb uninstall`, `pm clear` ni `flutter run`/`flutter test` contra un dispositivo con datos: borran SQLite y fotos. La versión release se firma con la clave debug; Android rechaza la actualización si el APK instalado se firmó con otra clave.

**CP04.** `apk-cp04` genera la variante aislada `com.example.campo_cnn.cp04` (nombre visible «Campo CNN CP04»). Se instala junto a la app normal y no la toca. El procedimiento completo —transferir las referencias a `/sdcard/Android/data/com.example.campo_cnn.cp04/files/cp04/entrada`, ejecutar, reanudar tras una desconexión y extraer `salidas`— está en [colab/REFERENCIAS_CP04.md](../colab/REFERENCIAS_CP04.md).

El criterio de CP04 es fijo: `|score_android − score_colab| ≤ 1e-5 + 1e-4·|score_colab|` y la misma categoría en las 629 fotografías. Un informe `comparacion_pasa` no aprueba CP04 automáticamente: requiere revisión.

## Identidad del código

El comparador CP04 registra una huella del código evaluado (preprocesamiento, decodificador JPEG, motor, comparador, dependencias, configuración Android y versiones de Flutter/engine/Dart). Si cambias cualquiera de esos archivos, la huella cambia y una ejecución nueva no reutiliza checkpoints anteriores. Con el código y la imagen sin cambios, `identidad` debe coincidir con la del informe de referencia del Samsung: `a37762478090a02833a7def451d360a6a36fbfda35f9c31b565328d2b6299a07`.

## Problemas frecuentes

- **Gradle sin memoria (`OutOfMemoryError`, daemon desaparecido).** El valor por defecto es `-Xmx2560m`. Asigna más RAM a Docker o ajusta: `GRADLE_JVMARGS="-Xmx2g -XX:MaxMetaspaceSize=512m" docker compose run --rm campo apk`.
- **Pruebas SQLite que superan 30 s.** `/tmp` se monta en memoria (`tmpfs` en `docker-compose.yml`) porque SQLite hace `fsync` en cada transacción y, sobre el disco superpuesto de Docker Desktop, cada prueba tardaba más de 30 s. Si ejecutas la imagen sin Compose, añade `--tmpfs /tmp:exec`.
- **`sdkmanager` o `git clone` fallan al construir.** Requieren Internet. Si Google retiró ese paquete de command-line tools, cambia `ANDROID_CMDLINE_TOOLS` en `docker/Dockerfile`; no afecta a la identidad CP04.
- **Archivos de `salida_docker` propiedad de root (Linux).** Ejecuta con `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose run --rm campo ...`.
- **Empezar de cero.** `docker compose down -v` borra el espacio de trabajo y las cachés del contenedor (no toca tu carpeta ni `salida_docker`).
