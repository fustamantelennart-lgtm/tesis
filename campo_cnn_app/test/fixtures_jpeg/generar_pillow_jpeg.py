"""JPEG sinteticos y RGB de referencia decodificados por Pillow 11.3.0.

Cubre las variantes de codificacion que la app puede recibir. La referencia es
`Image.open(...).convert("RGB")` de Pillow (libjpeg-turbo), independiente del
codigo Dart. Uso: py -3.13 -I test/fixtures_jpeg/generar_pillow_jpeg.py
"""

import hashlib
import json
import random
from pathlib import Path

import PIL
from PIL import Image, features


def patron(ancho, alto, semilla):
    rnd = random.Random(semilla)
    imagen = Image.new("RGB", (ancho, alto))
    for y in range(alto):
        for x in range(ancho):
            # Gradientes asimetricos, bordes duros y ruido: coeficientes AC de
            # ambos signos y croma distinta en cada esquina.
            r = (x * 255) // max(1, ancho - 1)
            g = (y * 255) // max(1, alto - 1)
            b = 230 if (x < ancho // 3 and y > alto // 2) else 25
            n = rnd.randint(-40, 40)
            imagen.putpixel((x, y), tuple(max(0, min(255, c + n)) for c in (r, g, b)))
    return imagen


CASOS = [
    ("base_420", (61, 45), {"quality": 90, "subsampling": 2}),
    ("base_422", (61, 45), {"quality": 90, "subsampling": 1}),
    ("base_444", (61, 45), {"quality": 90, "subsampling": 0}),
    ("prog_420", (61, 45), {"quality": 85, "subsampling": 2, "progressive": True}),
    ("prog_444", (61, 45), {"quality": 97, "subsampling": 0, "progressive": True}),
    ("reinicio_420", (61, 45), {"quality": 80, "subsampling": 2, "restart_marker_blocks": 3}),
    ("rgb_adobe", (61, 45), {"quality": 90, "keep_rgb": True, "subsampling": 0}),
    ("gris", (61, 45), {"quality": 90, "modo": "L"}),
    ("prog_gris", (61, 45), {"quality": 90, "modo": "L", "progressive": True}),
    ("estrecha_420", (3, 17), {"quality": 90, "subsampling": 2}),
    ("diminuta_422", (2, 3), {"quality": 90, "subsampling": 1}),
    ("alta_420", (17, 64), {"quality": 60, "subsampling": 2}),
]


def main():
    if PIL.__version__ != "11.3.0":
        raise RuntimeError(f"Se requiere Pillow 11.3.0; actual: {PIL.__version__}")
    raiz = Path(__file__).resolve().parent
    filas = []
    for semilla, (nombre, tam, opciones) in enumerate(CASOS):
        opciones = dict(opciones)
        modo = opciones.pop("modo", "RGB")
        fuente = patron(*tam, semilla)
        if modo != "RGB":
            fuente = fuente.convert(modo)
        ruta = raiz / f"{nombre}.jpg"
        fuente.save(ruta, format="JPEG", **opciones)
        with Image.open(ruta) as cargada:
            rgb = cargada.convert("RGB")
            progresivo = bool(cargada.info.get("progressive"))
        referencia = raiz / f"{nombre}_pillow.png"
        rgb.save(referencia)
        filas.append({
            "nombre": nombre, "jpeg": ruta.name, "png": referencia.name,
            "sha256_jpeg": hashlib.sha256(ruta.read_bytes()).hexdigest(),
            "sha256_rgb": hashlib.sha256(rgb.tobytes()).hexdigest(),
            "ancho": rgb.width, "alto": rgb.height, "progresivo": progresivo,
            "opciones": {**opciones, "modo": modo},
        })
    (raiz / "referencias_pillow_jpeg.json").write_text(json.dumps({
        "pillow": PIL.__version__,
        "libjpeg_turbo": features.version("libjpeg_turbo"),
        "casos": filas,
    }, indent=2), encoding="utf-8")
    print(f"{len(filas)} casos en {raiz}")


if __name__ == "__main__":
    main()
