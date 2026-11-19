# CP04: referencias externas y comparación Android

> **Ejecución corregida en Samsung físico, 18–19-11-2026:** fase A y fase B completas sobre 629 referencias (217 arroz, 412 caña). Ambos motores pasaron con los tensores de Colab; el recorrido desde originales verificó 629 entradas y obtuvo 0 errores, 0 scores fuera de tolerancia y 0 categorías distintas. Hubo 394 checkpoints reutilizados al reanudar tras una desconexión USB. Los 629 tensores difieren numéricamente y se informan por separado, sin nuevo límite obligatorio. El estado del informe es `comparacion_pasa`, con aprobación automática desactivada. [Informe Samsung](../../evidencia/cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md).

> **Ejecución histórica en LDPlayer, 18-11-2026, antes de la corrección:** las 629 entradas se verificaron y compararon. El informe resultó `comparacion_falla`: 387 scores fuera de tolerancia y 194 categorías distintas, sin errores de ejecución. Sus informes y fotos afectadas siguen en [INFORME_CP04_LDPLAYER.md](../../evidencia/cp04_1_ldplayer_falla/INFORME_CP04_LDPLAYER.md). LDPlayer no representa al Samsung físico ni sus tiempos.

## Evidencia disponible y criterio

`integration_test/fixtures/manifest.json` está `listo`: contiene 629 fotografías de la partición `val` (217 arroz, 412 caña), sus 629 originales `original_*.bin` y 629 tensores `tensor_*.bin`. El generador se documenta en `colab/generar_referencias_integracion.py`; no se regeneran ni se reducen esas entradas para facilitar una prueba. El manifiesto declara las versiones efectivas de TensorFlow y Pillow y los SHA-256 de los modelos. La prueba verifica esos datos, el SHA de cada archivo externo y el umbral de cada fila.

El criterio metodológico de puntuación sigue siendo `abs(android-colab) <= 1e-5 + 1e-4*abs(colab)` y categoría idéntica. Las diferencias del tensor se exportan como diagnóstico; `TENSOR_MAX_ABS` es opcional y no se convierte en requisito de aprobación. CP04 no se aprueba automáticamente por un informe `comparacion_pasa`.

## Procedimiento Windows/PowerShell sin desinstalación

**Samsung con aplicación habitual no depurable.** La instalación observada de `com.example.campo_cnn` no permitía `run-as`, por lo que no se sustituyó. Se usó la variante debug aislada `com.example.campo_cnn.cp04`, habilitada por `cp04Aislado=true` en Gradle; el APK se inspeccionó para confirmar ese identificador antes de instalarlo. El nombre visible de esa variante es «Campo CNN CP04». Se construyeron dos APK aislados con el mismo `CP04_CODE_SHA256`: uno con `target=integration_test/cp04_tensores_test.dart` y `CP04_ENTORNO=Samsung_SM-A166M_Android15`, otro con `target=integration_test/concordancia_test.dart`. Para cada construcción se añadieron temporalmente `cp04Aislado=true`, `target=...` y `dart-defines=...` (valores base64 UTF-8 separados por comas) a `android/gradle.properties`, se ejecutó `android/gradlew.bat :app:assembleDebug`, se copió el APK generado y se restauró el `gradle.properties` original. Un `flutter build apk` sin esa propiedad genera el paquete habitual y **no debe instalarse como CP04 aislado**. Los APK finales observados son `Campo_CNN_CP04_Samsung_tensores_aislado_debug.apk` y `Campo_CNN_CP04_Samsung_originales_aislado_debug.apk`.

En la variante aislada, la ruta de entrada fue `/sdcard/Android/data/com.example.campo_cnn.cp04/files/cp04/entrada` y la de salida `/sdcard/Android/data/com.example.campo_cnn.cp04/files/cp04/salidas`. La primera apertura del APK de originales creó ambas carpetas con permisos de la app. Se transfirió `integration_test/fixtures/.` con `adb push` y se contrastaron los SHA-256 de los 1.260 archivos con el manifiesto y los archivos locales. Se ejecutó la fase A y se extrajo `salidas` antes de actualizar solo la app CP04 aislada a la fase B con `adb install -r`. La fase B se inició con `adb shell am start`; tras la desconexión USB, la misma instalación reanudó el mismo ID y verificó 394 checkpoints. Se extrajo `salidas` completa al equipo, se restauró `stay_on_while_plugged_in` a su valor previo `0`, se detuvo la app CP04 y se abrió `com.example.campo_cnn/.MainActivity`. No se usaron `pm clear` ni desinstalaciones. Los comandos, registros e informes de esta ejecución están en [la carpeta de evidencia Samsung](../../evidencia/cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md).

El procedimiento siguiente describe instalaciones de prueba actualizables **del mismo paquete**. Si hay datos privados de una instalación no depurable y no se puede obtener un respaldo verificable, usar la variante aislada anterior para conservar la aplicación habitual.

Ejecutar desde `campo_cnn_app`. Identificar el destino con `flutter devices` y `adb devices -l`; registrar si es emulador o teléfono físico. Sustituir el ID de ejemplo por el dispositivo observado. La ruta pertenece al directorio externo **propio de la app**. No crearla con `adb shell mkdir`: en Android 14 quedaría bajo el usuario `shell` y la app no podría escribir sus informes. La propia prueba crea las carpetas antes de pedir el manifiesto.

```powershell
$id = 'emulator-5554'
$remoto = '/sdcard/Android/data/com.example.campo_cnn/files/cp04'
$respaldo = Join-Path (Resolve-Path '..\evidencia').Path ('cp04_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $respaldo | Out-Null
adb -s $id shell pm path com.example.campo_cnn
```

Si ya hay una instalación, **antes de actualizarla** respaldar el espacio privado. En una instalación depurable, el script siguiente extrae un `.tgz` binario directamente al equipo, sin pasar por redirección de texto de PowerShell. Comprobar que termina sin error y que el archivo se puede listar:

```powershell
$privado = (powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\resguardar_android_cp04.ps1 -Dispositivo $id).Trim()
tar -tzf $privado | Select-Object -First 10
adb -s $id pull "$remoto/salidas" (Join-Path $respaldo 'salidas_antes')
```

El `pull` puede indicar que no existen informes todavía. Si `run-as` no funciona y la instalación contiene datos, detenerse hasta obtener un respaldo verificable por el mecanismo disponible para esa instalación. No usar `pm clear`, `adb uninstall` ni `flutter test` para este recorrido. El comando `flutter test` puede desinstalar al terminar y la herramienta de instalación puede intentar desinstalar después de un fallo. Se compila sin tocar el dispositivo y se instala solo con `adb install -r`; si falla, detenerse sin hacer rescates destructivos.

```powershell
$codigo = (powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\identidad_cp04.ps1).Trim()
flutter build apk --debug -t integration_test/concordancia_test.dart --dart-define=CP04_CODE_SHA256=$codigo
Copy-Item 'build/app/outputs/flutter-apk/app-debug.apk' 'build/app/outputs/flutter-apk/Campo_CNN_CP04_prueba_debug.apk'
adb -s $id install -r 'build/app/outputs/flutter-apk/Campo_CNN_CP04_prueba_debug.apk'
adb -s $id shell am start -n com.example.campo_cnn/.MainActivity
```

La **primera apertura** sin manifiesto crea `$remoto/entrada` y `$remoto/salidas` con permisos de la app y termina con el mensaje de entrada faltante. Entonces transferir las referencias y volver a iniciar. `am force-stop` solo detiene el proceso, no borra datos:

```powershell
adb -s $id shell am force-stop com.example.campo_cnn
adb -s $id push 'integration_test/fixtures/.' "$remoto/entrada/"
adb -s $id shell am start -n com.example.campo_cnn/.MainActivity
adb -s $id logcat -v time -s flutter:I
```

Antes de considerar la ejecución terminada, extraer `salidas` al equipo. Para reanudar tras una interrupción, usar `am force-stop` y `am start` con la misma instalación y entradas; no volver a instalar ni borrar checkpoints. Si cambia código, manifiesto, modelo, criterio o entorno, volver a calcular `$codigo`, construir otra vez y actualizar solo con `adb install -r` tras respaldar los datos.

La compilación normal `flutter build apk --release` solo empaqueta los dos modelos, no las referencias. `scripts/identidad_cp04.ps1` calcula la identidad de los archivos de comparación, preparación, motor, paquete de dependencias y versión Flutter. Se exige esa huella de 64 caracteres al ejecutar. Para un criterio técnico opcional de tensor, añadir el mismo `--dart-define=TENSOR_MAX_ABS=VALOR` documentado al construir; cambiarlo inicia otra ejecución, sin alterar el criterio metodológico de score y categoría.

La prueba procesa las 629 filas **en orden y una por vez**. En `$remoto/salidas` guarda `ejecucion_<id>.json` y un `fila_<id>_<indice>.json` por fotografía terminada. Cada fila se escribe con archivo temporal y se valida de nuevo contra los bytes externos al reanudar. Una ejecución interrumpida se recupera al relanzar la app con idénticos manifiesto, archivos, modelos, criterios, código y entorno; si algo cambia, empieza un ID nuevo. Los errores de lectura o inferencia quedan registrados y se vuelven a intentar. Los informes `comparacion_<id>_<instante>.json/.csv` tienen nombres únicos y no sobrescriben informes anteriores. Solo se declara comparación completa tras verificar originales y tensores, comparar las 629 filas y confirmar los conteos por cultivo.

Para extraer resultados, detener `logcat` con Ctrl+C y copiar la carpeta completa, sin borrar nada del dispositivo:

```powershell
adb -s $id pull "$remoto/salidas" (Join-Path $respaldo 'salidas_despues')
```

Abrir el JSON más reciente y comprobar `total_esperado=629`, `entradas_verificadas=629`, `comparadas=629`, los conteos `arroz/val=217` y `cana/val=412`, `fallos_puntuacion_categoria`, el entorno y la huella de ejecución. Revisar también el CSV por fotografía. Un emulador acredita únicamente ese entorno; para el Samsung físico se necesita su propia ejecución y observación. La recepción de avisos es una verificación distinta.

