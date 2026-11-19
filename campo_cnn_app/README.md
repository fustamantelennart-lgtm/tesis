# Campo CNN · prototipo Android

> Estado de la versión actual: ver [bitacora_avance.md](../docs/bitacora_avance.md). Este README describe el prototipo de medición original; algunas instrucciones y límites que siguen corresponden a esa versión anterior.

Aplicación Flutter para dos CNN ya entrenadas: arroz (piricularia) y caña de azúcar (roya). Los modelos TFLite Float32 están incluidos en `assets/`; se verifica su SHA-256 antes de cada uso. No modifica las arquitecturas ni vuelve a entrenar.

## Qué incluye

- Inicio con selección de cultivo y ficha del modelo.
- Diagnóstico con cámara o galería, inferencia local y umbral fijado en validación. **Exploratorio:** su interpolación móvil requiere prueba formal de concordancia antes de presentar resultados clínicos/agronómicos o métricas de tesis.
- Medición reproducible sobre las **219 imágenes de test de arroz** o las **412 de caña**, con tensores generados por el preprocesamiento original en Colab. El modelo corre en CPU, un hilo; primero hay 20 calentamientos y después una inferencia cronometrada por fotografía. La lectura, comprobación SHA, generación de tensor, pantalla y guardado quedan fuera del cronómetro.
- Validación de SHA del modelo y de cada tensor, cotejo de puntuación TFLite Colab ↔ Android (tolerancia 0,0001 y misma clase). Un fallo cancela la serie sin guardar un resultado parcial.
- Historial local y exportación de JSON completo + CSV individual. Se registran dispositivo, Android, modo profile/release, cantidad, tamaño, hashes y estadísticos. No se suben imágenes ni resultados a servidores.

## Preparar el proyecto

Instala Flutter y Android Studio/SDK en tu computadora. Este paquete lleva todo el código Dart y los modelos, pero no el andamiaje generado del SDK Flutter. En una carpeta nueva:

```bash
flutter create --platforms=android --project-name campo_cnn campo_cnn
```

Copia sobre esa carpeta los archivos `pubspec.yaml`, `lib/` y `assets/` de este paquete. Luego:

```bash
cd campo_cnn
flutter pub get
flutter analyze
flutter build apk --profile
flutter install --profile
```

En `android/app/build.gradle.kts`, configura `minSdk = 26` si la plantilla genera un valor menor. Usa teléfono **físico**. Para medir cifras finales, conviene una compilación release (`flutter build apk --release`, `flutter install --release`). Si el paquete `tflite_flutter` advierte sobre compresión de activos `.tflite`, agrega la configuración `noCompress += "tflite"` al bloque `androidResources` de `android/app/build.gradle.kts` y recompila.

## Preparar los paquetes de test

Abre `colab/02_Preparar_paquetes_medicion.ipynb` en Colab. Monta Drive, confirma las rutas de las carpetas **ya reconstruidas** `manifest.csv` + `test/` y de los experimentos terminados, y ejecuta las celdas. El cuaderno genera `arroz_test.cbm` y `cana_test.cbm` en Drive. Cada paquete contiene los tensores Float32 exactos de test y el score de referencia calculado con ese mismo TFLite en Colab. No crea una partición nueva ni consulta val para ajustar el modelo. Se necesitan las fotografías originales, que no están dentro de este proyecto.

Los paquetes sin compresión ocupan aproximadamente 132 MB (arroz) y 248 MB (caña); reserva espacio en Drive y en el teléfono. Copia cada `.cbm` al teléfono mediante USB o Drive, impórtalo en **Medición** y ejecuta los cultivos por separado en el mismo dispositivo.

## Protocolo de la tesis

Usa el mismo teléfono, versión de app, carga y condiciones prácticas para ambos cultivos. Documenta el modelo de teléfono, versión de Android, modo, temperatura/estado de batería si influyen, y no uses el móvil mientras mide. Repite series completas si tu metodología lo exige, sin mezclar las observaciones entre series. Reporta media, desviación estándar muestral y mediana por modelo, además del tamaño de archivo. El archivo JSON/CSV constituye el registro por foto.

La discrepancia entre fecha de captura y clase, así como la independencia no verificada por hoja/planta, siguen siendo limitaciones de la exactitud de clasificación. La medición Android evalúa **latencia de inferencia**; no certifica generalización ni mide la interacción completa con cámara. El conteo de parámetros de cada arquitectura se conserva en los registros de entrenamiento (105 761), no se infiere a partir del tamaño del archivo.

## Límites de esta entrega

No había imágenes de test ni teléfono Android en el entorno de creación. Por eso los paquetes `.cbm` y las cifras de latencia todavía deben generarse/medirse en tu Colab y en tu teléfono. Tampoco había Flutter/Android SDK aquí, por lo que falta ejecutar `flutter analyze`, compilar, instalar y validar visualmente la interfaz en el dispositivo. No escribas tiempos Android en la tesis antes de completar esas comprobaciones.

## Estado vigente de la revisión: agente y CP04 externo

La aplicación actual conserva consultas, casos, revisiones y avisos del agente. Véanse [agente_seguimiento.md](../docs/agente_seguimiento.md), [bitacora_avance.md](../docs/bitacora_avance.md), [trazabilidad_cp.md](../docs/trazabilidad_cp.md) y [resultados_agente.md](../docs/resultados_agente.md). Los apartados anteriores de este README describen el prototipo histórico y pueden contener límites ya superados.

`flutter build apk --release` construye la aplicación sin fotografías de validación empaquetadas. Para CP04 se transfieren `manifest.json`, 629 originales y 629 tensores al directorio externo propio de la app. El procedimiento de compilación, actualización con `adb install -r`, ejecución, reanudación y extracción sin desinstalar está en [colab/REFERENCIAS_CP04.md](colab/REFERENCIAS_CP04.md). La ejecución completa en LDPlayer produjo `comparacion_falla`; [informe y fotografías afectadas](../evidencia/cp04_1_ldplayer_falla/INFORME_CP04_LDPLAYER.md). CP04 no está aprobado; la ejecución en Samsung y la recepción real de avisos siguen pendientes.

## APK para abrir Campo CNN

Para usar la aplicación, compilar con `flutter build apk --debug -t lib/main.dart` o usar el APK release. El archivo `app-debug.apk` se sobrescribe también al compilar `integration_test/concordancia_test.dart`: ese APK ejecuta CP04 y no abre la interfaz normal. Antes de distribuir o instalar, conservar una copia con nombre explícito. El APK debug normal instalado en LDPlayer es `build/app/outputs/flutter-apk/Campo_CNN_aplicacion_LDPlayer_debug.apk`.

