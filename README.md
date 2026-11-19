# Campo CNN

Aplicación Android (Flutter) para el diagnóstico en campo de **piricularia en arroz** y **roya en caña de azúcar** con dos redes neuronales convolucionales que se ejecutan en el teléfono, sin conexión. Incluye un agente de seguimiento que abre casos ante resultados positivos, programa revisiones (72 h en arroz, 7 días en caña) y envía avisos locales.

## Estado

| Verificación | Resultado |
|---|---|
| Análisis estático y pruebas automatizadas | Sin incidencias; 69 pruebas aprobadas y 1 omitida (requiere TFLite en Android) |
| **CP04 — concordancia Android ↔ Colab** | **629/629 fotografías dentro de tolerancia** en Samsung SM-A166M (Android 15): 0 scores fuera de tolerancia y 0 categorías distintas. Pendiente de revisión para su aprobación formal. [Informe](evidencia/cp04_4_samsung_pasa/INFORME_CP04_SAMSUNG.md) |
| CP01–CP03, CP05–CP18 | Implementados y probados con dobles de Android; falta la observación en el teléfono. [Matriz de trazabilidad](docs/trazabilidad_cp.md) |

## Estructura

```
├── campo_cnn_app/     Aplicación Flutter: código, pruebas y modelos TFLite
│   ├── docker/        entorno Docker reproducible
│   ├── colab/         generación de referencias en Colab
│   └── scripts/       utilidades de verificación y respaldo
├── docs/              Especificación del agente, trazabilidad CP, hallazgos y bitácora
└── evidencia/         Registros de cada ejecución CP04 y de la app
```

| Documento | Contenido |
|---|---|
| [campo_cnn_app/README.md](campo_cnn_app/README.md) | Cómo compilar e instalar la app |
| [docs/agente_seguimiento.md](docs/agente_seguimiento.md) | Especificación del agente de seguimiento |
| [docs/trazabilidad_cp.md](docs/trazabilidad_cp.md) | Matriz CP01–CP18: implementación, prueba y evidencia |
| [docs/resultados_agente.md](docs/resultados_agente.md) | Borrador de resultados para la tesis |
| [docs/hallazgos.md](docs/hallazgos.md) | Problemas detectados, cómo se reprodujeron y cómo se corrigieron |
| [docs/bitacora_avance.md](docs/bitacora_avance.md) | Bitácora cronológica completa |
| [evidencia/README.md](evidencia/README.md) | Índice de la evidencia CP04 |
| [campo_cnn_app/colab/REFERENCIAS_CP04.md](campo_cnn_app/colab/REFERENCIAS_CP04.md) | Procedimiento para ejecutar CP04 en un dispositivo |

## Primeros pasos

Con Flutter 3.44.6 instalado, desde `campo_cnn_app/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Sin instalar Flutter, con Docker: `docker compose run --rm campo todo` (ver [docker/LEEME_DOCKER.md](campo_cnn_app/docker/LEEME_DOCKER.md)).

## No incluido

- Las 629 fotografías y tensores de validación de CP04 (~1,6 GB), generados en Colab; se colocan en `campo_cnn_app/integration_test/fixtures/` para verificar CP04.
- APK compilados y respaldos binarios del espacio privado de la app.

Los archivos se guardan sin conversión de finales de línea (`.gitattributes`): la identidad de código de CP04 se calcula sobre sus bytes exactos.
