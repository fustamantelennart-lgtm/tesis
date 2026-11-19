# Entorno reproducible de Campo CNN: compilar, analizar, probar y verificar CP04.
# No ejecuta la app ni CP04 en Android: eso requiere un dispositivo (ver LEEME_DOCKER.md).
FROM ubuntu:24.04

# Versiones del entorno con el que se obtuvo CP04 en el Samsung (19-11-2026).
# La identidad CP04 incluye las revisiones de Flutter, engine y Dart.
ARG FLUTTER_VERSION=3.44.6
ARG FLUTTER_REVISION=ee80f08bbf97172ec030b8751ceab557177a34a6
# No llamar FLUTTER_ENGINE: Flutter lee esa variable como ruta de un engine local.
ARG FLUTTER_ENGINE_REVISION=83675ed27633283e7fc296c8bca22e841224c096
ARG DART_VERSION=3.12.2
ARG ANDROID_CMDLINE_TOOLS=13114758
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG ANDROID_NDK=28.2.13676358
ARG PILLOW_VERSION=11.3.0
ARG LIBJPEG_TURBO_VERSION=3.1.1

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/root/.pub-cache \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    PATH=/opt/venv/bin:/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip rsync \
      openjdk-21-jdk-headless python3 python3-venv libsqlite3-dev libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Android SDK: plataforma, build-tools y NDK que usan AGP 9.0.1 y Flutter 3.44.6.
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
       "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && (yes | sdkmanager --licenses > /dev/null) \
    && sdkmanager --install "platform-tools" "platforms;${ANDROID_PLATFORM}" \
       "build-tools;${ANDROID_BUILD_TOOLS}" "ndk;${ANDROID_NDK}" > /dev/null

# Flutter en la revision exacta; falla si la etiqueta apunta a otro commit.
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
    && test "$(git -C "$FLUTTER_HOME" rev-parse HEAD)" = "${FLUTTER_REVISION}" \
    && git config --global --add safe.directory "$FLUTTER_HOME" \
    && flutter config --no-analytics --android-sdk "$ANDROID_HOME" --jdk-dir "$JAVA_HOME" \
    && dart --disable-analytics \
    && flutter precache --android --no-web --no-linux \
    && flutter --version --machine > /opt/flutter-version.json \
    && python3 -c "import json; t=open('/opt/flutter-version.json').read(); \
v=json.loads(t[t.index('{'):t.rindex('}')+1]); \
assert v['frameworkRevision']=='${FLUTTER_REVISION}', v; \
assert v['engineRevision']=='${FLUTTER_ENGINE_REVISION}', v; \
assert v['dartSdkVersion']=='${DART_VERSION}', v; print('Flutter', v['frameworkVersion'], 'verificado')"

# Pillow con el libjpeg-turbo que usaron las referencias de Colab.
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir "pillow==${PILLOW_VERSION}" \
    && /opt/venv/bin/python -c "import PIL; from PIL import features; \
assert PIL.__version__=='${PILLOW_VERSION}', PIL.__version__; \
assert features.version('libjpeg_turbo')=='${LIBJPEG_TURBO_VERSION}', features.version('libjpeg_turbo'); \
print('Pillow', PIL.__version__, 'libjpeg-turbo', features.version('libjpeg_turbo'))"

COPY campo.sh /usr/local/bin/campo
RUN sed -i 's/\r$//' /usr/local/bin/campo && chmod +x /usr/local/bin/campo

WORKDIR /work/campo_cnn_app
ENTRYPOINT ["campo"]
CMD ["ayuda"]
