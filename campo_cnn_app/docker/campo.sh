#!/usr/bin/env bash
# Punto de entrada del contenedor Campo CNN. Ver docker/LEEME_DOCKER.md.
set -euo pipefail

SRC=/src
WORK=/work/campo_cnn_app
SALIDA=/salida
FIXTURES="$WORK/integration_test/fixtures"

ayuda() {
  cat <<'EOF'
Uso: docker compose run --rm campo <comando> [argumentos]

  analizar                 flutter analyze
  probar                   flutter test (pruebas unitarias y de widgets)
  verificar-cp04           RGB identico a Pillow y tensor frente a Colab, 629 originales
                           (requiere las referencias montadas; sin TFLite, sin scores)
  identidad                huella CP04_CODE_SHA256 del codigo evaluado
  apk                      APK release de la aplicacion        -> salida_docker/
  apk-debug                APK debug de la aplicacion          -> salida_docker/
  apk-cp04 <fase> [entorno]
                           APK CP04 aislado (com.example.campo_cnn.cp04)
                           fase: originales | tensores ; tensores exige entorno,
                           p. ej. Samsung_SM-A166M_Android15
  todo                     analizar + probar + apk
  shell                    bash dentro del espacio de trabajo
EOF
}

sincronizar() {
  # Copia del codigo montado en solo lectura. Asi Flutter/Gradle no reescriben
  # local.properties, .dart_tool ni build/ de la carpeta del equipo anfitrion.
  mkdir -p "$WORK" "$SALIDA"
  rsync -a --delete \
    --exclude '/build/' --exclude '/.dart_tool/' --exclude '/.flutter-plugins-dependencies' \
    --exclude '/android/.gradle/' --exclude '/android/local.properties' \
    --exclude '/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java' \
    --exclude '/integration_test/fixtures/' --exclude '/salida_docker/' \
    --exclude '/.idea/' --exclude '*.iml' --exclude '*.apk' --exclude '*.log' \
    "$SRC/" "$WORK/"
  chmod +x "$WORK/android/gradlew" 2>/dev/null || true
  mkdir -p /root/.gradle
  echo "org.gradle.jvmargs=${GRADLE_JVMARGS:--Xmx2560m -XX:MaxMetaspaceSize=768m}" \
    > /root/.gradle/gradle.properties
  cd "$WORK"
  flutter pub get --enforce-lockfile
}

entregar() {
  # entregar <origen> <nombre>: copia a salida_docker con su SHA-256.
  cp "$1" "$SALIDA/$2"
  (cd "$SALIDA" && sha256sum "$2" > "$2.sha256")
  echo "Generado: salida_docker/$2"
}

propietario() {
  # En Linux, devuelve la salida al usuario anfitrion si se indico.
  if [[ -n "${HOST_UID:-}" ]]; then
    chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$SALIDA" || true
  fi
}
trap propietario EXIT

analizar() { flutter analyze --no-pub; }
probar() { flutter test --no-pub; }

apk_release() {
  flutter build apk --release --no-pub
  entregar build/app/outputs/flutter-apk/app-release.apk Campo_CNN_release.apk
}

comando="${1:-ayuda}"
shift || true
case "$comando" in
  analizar) sincronizar; analizar ;;
  probar) sincronizar; probar ;;
  todo) sincronizar; analizar; probar; apk_release ;;
  apk) sincronizar; apk_release ;;
  apk-debug)
    sincronizar
    flutter build apk --debug --no-pub -t lib/main.dart
    entregar build/app/outputs/flutter-apk/app-debug.apk Campo_CNN_aplicacion_debug.apk ;;
  identidad) sincronizar; python3 scripts/identidad_cp04.py . ;;
  verificar-cp04)
    sincronizar
    if [[ ! -f "$FIXTURES/manifest.json" ]]; then
      echo "Faltan las referencias CP04 en integration_test/fixtures (ver LEEME_DOCKER.md)." >&2
      exit 2
    fi
    mkdir -p "$SALIDA/cp04"
    python3 -I scripts/referencias_rgb_pillow_cp04.py --manifest "$FIXTURES/manifest.json" \
      --originales "$FIXTURES" --salida "$SALIDA/cp04/rgb_pillow_629.json"
    CP04_INVESTIGACION="$SALIDA/cp04" flutter test --no-pub tool/cp04_decodificador_test.dart \
      --reporter expanded ;;
  apk-cp04)
    fase="${1:-}"
    entorno="${2:-}"
    case "$fase" in
      originales) objetivo=integration_test/concordancia_test.dart ;;
      tensores)
        objetivo=integration_test/cp04_tensores_test.dart
        [[ -n "$entorno" ]] || { echo "La fase tensores exige un entorno." >&2; exit 2; } ;;
      *) echo "Fase invalida: usa originales o tensores." >&2; exit 2 ;;
    esac
    sincronizar
    codigo="$(python3 scripts/identidad_cp04.py .)"
    defines=(--dart-define="CP04_CODE_SHA256=$codigo")
    [[ -n "$entorno" ]] && defines+=(--dart-define="CP04_ENTORNO=$entorno")
    flutter build apk --debug --no-pub -P cp04Aislado=true -t "$objetivo" "${defines[@]}"
    nombre="Campo_CNN_CP04_${fase}_aislado_${codigo:0:12}_debug.apk"
    entregar build/app/outputs/flutter-apk/app-debug.apk "$nombre"
    echo "$codigo" > "$SALIDA/${nombre%.apk}.codigo_sha256.txt"
    echo "Paquete: com.example.campo_cnn.cp04 ; CP04_CODE_SHA256=$codigo" ;;
  shell) sincronizar; exec bash ;;
  ayuda|-h|--help) ayuda ;;
  *) echo "Comando desconocido: $comando" >&2; ayuda; exit 2 ;;
esac
