"""Cruza EXIF de los originales CP04 con un informe Android conservado."""

import argparse
import csv
import io
import json
from collections import defaultdict
from pathlib import Path

from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--originales", type=Path, required=True)
    parser.add_argument("--informe", type=Path, required=True)
    parser.add_argument("--salida", type=Path, required=True)
    args = parser.parse_args()
    args.salida.mkdir(parents=True, exist_ok=True)

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    report = json.loads(args.informe.read_text(encoding="utf-8"))
    results = {r["ruta_relativa"]: r for r in report["resultados"]}
    rows = []
    for record in manifest["registros"]:
        result = results[record["ruta_relativa"]]
        data = (args.originales / record["original"]).read_bytes()
        with Image.open(io.BytesIO(data)) as image:
            orientation = image.getexif().get(274)
            width, height = image.size
            format_name = image.format
        if orientation is not None and orientation not in range(1, 9):
            raise ValueError(f"Orientacion EXIF no valida: {record['ruta_relativa']}: {orientation}")
        oriented_width, oriented_height = (
            (height, width) if orientation in (5, 6, 7, 8) else (width, height)
        )
        rows.append({
            "cultivo": record["cultivo"],
            "ruta_relativa": record["ruta_relativa"],
            "sha256_original": record["sha256_original"],
            "formato_real": format_name,
            "orientacion_exif": orientation if orientation is not None else "ausente",
            "ancho_jpeg": width,
            "alto_jpeg": height,
            "ancho_orientado": oriented_width,
            "alto_orientado": oriented_height,
            "score_cumple": result.get("score_cumple"),
            "categoria_coincide": result.get("categoria_coincide"),
            "score_error_abs": result.get("score_error_abs"),
            "tensor_max_abs": (result.get("tensor") or {}).get("max_abs"),
        })
    if len(rows) != 629 or len(results) != 629:
        raise ValueError("Se requieren 629 originales y 629 resultados")
    with (args.salida / "exif_por_fotografia.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    groups = defaultdict(list)
    for row in rows:
        groups[(row["cultivo"], str(row["orientacion_exif"]))].append(row)
    summary = []
    for (crop, orientation), group in sorted(groups.items()):
        summary.append({
            "cultivo": crop,
            "orientacion_exif": orientation,
            "fotografias": len(group),
            "score_fuera_tolerancia": sum(r["score_cumple"] is False for r in group),
            "categoria_diferente": sum(r["categoria_coincide"] is False for r in group),
            "tensor_max_abs_promedio": sum(r["tensor_max_abs"] for r in group) / len(group),
            "tensor_max_abs_max": max(r["tensor_max_abs"] for r in group),
        })
    with (args.salida / "exif_distribucion.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(summary[0]))
        writer.writeheader()
        writer.writerows(summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
