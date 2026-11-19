"""Huella RGB de Pillow (exif_transpose + RGB) para las 629 fotografias CP04.

Tambien registra la estructura JPEG (SOF, muestreo, JFIF/Adobe, orientacion)
para contrastar el decodificador Dart. No modifica originales ni referencias.
Uso: py -3.13 -I scripts/referencias_rgb_pillow_cp04.py --manifest M --originales DIR --salida JSON
"""

import argparse
import hashlib
import io
import json
import struct
from pathlib import Path

import PIL
from PIL import Image, ImageOps, features


def estructura(data):
    """Recorre marcadores hasta el primer SOS del primer frame."""
    info = {"sof": None, "muestreo": [], "ids": [], "jfif": False, "adobe": None,
            "dri": None, "precision": None}
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xFF, 0x00) or 0xD0 <= marker <= 0xD7 or marker == 0x01:
            i += 1 if marker == 0xFF else 2
            continue
        length = struct.unpack(">H", data[i + 2:i + 4])[0]
        body = data[i + 4:i + 2 + length]
        if marker == 0xE0 and len(body) >= 14 and body[:5] == b"JFIF\0":
            info["jfif"] = True
        elif marker == 0xEE and len(body) >= 12 and body[:5] == b"Adobe":
            info["adobe"] = body[11]
        elif marker == 0xDD:
            info["dri"] = struct.unpack(">H", body[:2])[0]
        elif 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            info["sof"] = f"0x{marker:02X}"
            info["precision"] = body[0]
            n = body[5]
            for k in range(n):
                cid, hv = body[6 + 3 * k], body[7 + 3 * k]
                info["ids"].append(cid)
                info["muestreo"].append([hv >> 4, hv & 15])
        elif marker == 0xDA:
            break
        i += 2 + length
    return info


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--originales", type=Path, required=True)
    parser.add_argument("--salida", type=Path, required=True)
    args = parser.parse_args()
    if PIL.__version__ != "11.3.0":
        raise RuntimeError(f"Pillow efectivo distinto: {PIL.__version__}")
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if manifest.get("pillow") != PIL.__version__:
        raise RuntimeError("El manifiesto declara otra version de Pillow.")
    filas = []
    for indice, record in enumerate(manifest["registros"]):
        data = (args.originales / record["original"]).read_bytes()
        if hashlib.sha256(data).hexdigest() != record["sha256_original"]:
            raise ValueError(f"Original alterado en {indice}")
        with Image.open(io.BytesIO(data)) as image:
            formato = image.format
            orientacion = image.getexif().get(274)
            rgb = ImageOps.exif_transpose(image).convert("RGB")
        filas.append({
            "indice": indice,
            "ruta_relativa": record["ruta_relativa"],
            "cultivo": record["cultivo"],
            "formato": formato,
            "orientacion_exif": orientacion,
            **estructura(data),
            "ancho": rgb.width,
            "alto": rgb.height,
            "sha256_rgb": hashlib.sha256(rgb.tobytes()).hexdigest(),
        })
    args.salida.parent.mkdir(parents=True, exist_ok=True)
    args.salida.write_text(json.dumps({
        "pillow": PIL.__version__,
        "libjpeg_turbo": features.version("libjpeg_turbo"),
        "manifest_sha256": hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
        "casos": filas,
    }, indent=1), encoding="utf-8")
    print(f"{len(filas)} referencias RGB en {args.salida}")


if __name__ == "__main__":
    main()
