"""Genera JPEG EXIF 1..8 y referencias independientes con Pillow 11.3.0."""

import hashlib
import json
from pathlib import Path

import PIL
from PIL import Image, ImageOps


def main():
    if PIL.__version__ != "11.3.0":
        raise RuntimeError(f"Se requiere Pillow 11.3.0; actual: {PIL.__version__}")
    root = Path(__file__).resolve().parent
    source = Image.new("RGB", (224, 112))
    colors = ((240, 20, 30), (20, 220, 40), (30, 60, 230), (240, 220, 20))
    for y in range(source.height):
        for x in range(source.width):
            source.putpixel((x, y), colors[(y >= 56) * 2 + (x >= 112)])

    rows = []
    for orientation in range(1, 9):
        path = root / f"exif_{orientation}.jpg"
        exif = Image.Exif()
        exif[274] = orientation
        source.save(path, format="JPEG", quality=100, subsampling=0, exif=exif)
        with Image.open(path) as loaded:
            if loaded.getexif().get(274) != orientation:
                raise RuntimeError(f"EXIF perdido en {path}")
            upright = ImageOps.exif_transpose(loaded).convert("RGB")
        upright.save(root / f"pillow_orientada_{orientation}.png")
        points = []
        for name, x, y in (
            ("superior_izquierda", upright.width // 4, upright.height // 4),
            ("superior_derecha", 3 * upright.width // 4, upright.height // 4),
            ("inferior_izquierda", upright.width // 4, 3 * upright.height // 4),
            ("inferior_derecha", 3 * upright.width // 4, 3 * upright.height // 4),
        ):
            points.append({
                "nombre": name,
                "x_orientado": x,
                "y_orientado": y,
                "x_tensor": x + (224 - upright.width) // 2,
                "y_tensor": y + (224 - upright.height) // 2,
                "rgb": list(upright.getpixel((x, y))),
            })
        rows.append({
            "orientacion": orientation,
            "original": path.name,
            "sha256_original": hashlib.sha256(path.read_bytes()).hexdigest(),
            "ancho_original": source.width,
            "alto_original": source.height,
            "ancho_pillow": upright.width,
            "alto_pillow": upright.height,
            "puntos": points,
        })
    (root / "referencias_pillow.json").write_text(
        json.dumps({"pillow": PIL.__version__, "casos": rows}, indent=2),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
