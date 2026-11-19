"""Exporta RGB orientado por Pillow para muestras CP04, sin modificar originales."""

import argparse
import hashlib
import io
import json
from pathlib import Path

import PIL
from PIL import Image, ImageOps


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--originales", type=Path, required=True)
    parser.add_argument("--indices", required=True)
    parser.add_argument("--salida", type=Path, required=True)
    args = parser.parse_args()
    if PIL.__version__ != "11.3.0":
        raise RuntimeError(f"Pillow efectivo distinto: {PIL.__version__}")
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    indices = [int(item) for item in args.indices.split(",")]
    args.salida.mkdir(parents=True, exist_ok=True)
    rows = []
    for index in indices:
        record = manifest["registros"][index]
        original = (args.originales / record["original"]).read_bytes()
        if hashlib.sha256(original).hexdigest() != record["sha256_original"]:
            raise ValueError(f"Original alterado en {index}")
        with Image.open(io.BytesIO(original)) as image:
            format_name = image.format
            orientation = image.getexif().get(274)
            raw_size = list(image.size)
            rgb = ImageOps.exif_transpose(image).convert("RGB")
        png_path = args.salida / f"pillow_rgb_{index:04d}.png"
        rgb.save(png_path, compress_level=1)
        rows.append({
            "indice": index,
            "ruta_relativa": record["ruta_relativa"],
            "formato_real": format_name,
            "orientacion_exif": orientation,
            "dimensiones_sin_orientar": raw_size,
            "dimensiones_pillow_rgb": list(rgb.size),
            "sha256_rgb_pillow": hashlib.sha256(rgb.tobytes()).hexdigest(),
            "png": png_path.name,
        })
    (args.salida / "etapas_pillow.json").write_text(
        json.dumps({"pillow": PIL.__version__, "casos": rows}, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(rows, indent=2))


if __name__ == "__main__":
    main()
