"""Referencias CP04 desde los bytes originales, en el entorno efectivo de Colab.

seleccion.csv: ruta_relativa,cultivo,particion[,sha256_original]
conteos.json: {"arroz/validacion": N, "cana/validacion": M}
La salida plana se copia a integration_test/fixtures y se empaqueta como assets.
"""

import argparse
import csv
import hashlib
import io
import json
import re
import sys
from collections import Counter
from pathlib import Path, PurePosixPath

MODELOS = {
    "arroz": ("0728e2ddedc0db0959870ef420c204df3094fd780ef520c0d3fb2b10a9090040", 0.6501769423484802),
    "cana": ("9042f0dffc63a6c143fd64a8d36a34ab25bc96cb74b21e51df35d7e88a368bec", 0.6862450242042542),
}
COLUMNAS = {"ruta_relativa", "cultivo", "particion"}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def seleccion(archivo, raiz):
    filas, errores, vistas = [], [], set()
    if not archivo.is_file() or not raiz.is_dir():
        return filas, [{"error": "Falta selección CSV o raíz de imágenes."}]
    with archivo.open(newline="", encoding="utf-8-sig") as stream:
        lector = csv.DictReader(stream)
        if not COLUMNAS.issubset(set(lector.fieldnames or [])):
            return filas, [{"error": f"Columnas obligatorias: {sorted(COLUMNAS)}"}]
        for numero, row in enumerate(lector, 2):
            ruta = (row.get("ruta_relativa") or "").replace("\\", "/").strip()
            cultivo = (row.get("cultivo") or "").strip().lower()
            particion = (row.get("particion") or "").strip().lower()
            partes = PurePosixPath(ruta).parts
            if not ruta or ruta.startswith("/") or ":" in ruta or any(p in (".", "..") for p in partes):
                errores.append({"fila": numero, "ruta_relativa": ruta, "error": "Ruta relativa inválida."})
                continue
            if cultivo not in MODELOS or not particion:
                errores.append({"fila": numero, "ruta_relativa": ruta, "error": "Cultivo o partición inválidos."})
                continue
            clave = ruta.casefold()
            if clave in vistas:
                errores.append({"fila": numero, "ruta_relativa": ruta, "error": "Entrada duplicada."})
                continue
            vistas.add(clave)
            imagen = (raiz / Path(*partes)).resolve()
            if not imagen.is_relative_to(raiz.resolve()):
                errores.append({"fila": numero, "ruta_relativa": ruta, "error": "Ruta fuera de la raíz."})
                continue
            if not imagen.is_file():
                errores.append({"fila": numero, "ruta_relativa": ruta, "error": "Imagen no encontrada."})
                continue
            declarado = (row.get("sha256_original") or "").strip().lower()
            if declarado and not re.fullmatch(r"[a-f0-9]{64}", declarado):
                errores.append({"fila": numero, "ruta_relativa": ruta,
                                "error": "SHA-256 declarado inválido."})
                continue
            filas.append({"fila": numero, "ruta_relativa": ruta, "cultivo": cultivo,
                          "particion": particion, "imagen": imagen,
                          "sha256_declarado": declarado})
    return filas, errores


def conteos(archivo, filas):
    try:
        esperados = json.loads(archivo.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return {}, [{"error": f"No se pudieron leer conteos: {error}"}]
    if (not isinstance(esperados, dict) or not esperados or
            any(not isinstance(v, int) or isinstance(v, bool) or v < 0 for v in esperados.values())):
        return {}, [{"error": "Conteos deben ser un objeto no vacío de enteros no negativos."}]
    observados = Counter(f"{r['cultivo']}/{r['particion']}" for r in filas)
    errores = [{"grupo": k, "esperado": esperados.get(k, 0), "seleccionado": observados[k],
                "error": "Conteo distinto."}
               for k in sorted(set(esperados) | set(observados))
               if observados[k] != esperados.get(k, 0)]
    if sum(esperados.values()) == 0:
        errores.append({"error": "Se exige al menos una imagen esperada."})
    return esperados, errores


def modelos(rutas):
    hashes, errores = {}, []
    for cultivo, ruta in rutas.items():
        try:
            obtenido = sha(ruta.read_bytes())
        except OSError as error:
            errores.append({"modelo": cultivo, "error": str(error)})
            continue
        hashes[cultivo] = obtenido
        if obtenido != MODELOS[cultivo][0]:
            errores.append({"modelo": cultivo, "esperado": MODELOS[cultivo][0],
                            "obtenido": obtenido, "error": "SHA-256 de modelo distinto."})
    return hashes, errores


def tensor_original(original, np, Image, ImageOps, tf):
    with Image.open(io.BytesIO(original)) as image:
        rgb = np.asarray(ImageOps.exif_transpose(image).convert("RGB"))
    tensor = tf.image.resize_with_pad(tf.cast(rgb, tf.float32), 224, 224,
                                      method="bilinear", antialias=True) / tf.constant(255.0, tf.float32)
    return np.ascontiguousarray(tensor.numpy()[None, ...], dtype="<f4")


def motor(ruta, np, tf):
    interpreter = tf.lite.Interpreter(model_path=str(ruta), num_threads=1)
    interpreter.allocate_tensors()
    entrada, salida = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    if (list(entrada["shape"]) != [1, 224, 224, 3] or entrada["dtype"] != np.float32 or
            list(salida["shape"]) != [1, 1] or salida["dtype"] != np.float32):
        raise ValueError(f"Forma o tipo incompatible: {ruta}")
    return interpreter, entrada["index"], salida["index"]


def escribir(salida, informe):
    salida.mkdir(parents=True, exist_ok=True)
    (salida / "manifest.json").write_text(json.dumps(informe, ensure_ascii=False, indent=2),
                                           encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    for name in ("imagenes", "seleccion", "conteos", "arroz", "cana", "salida"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--tensorflow-esperado", required=True)
    parser.add_argument("--pillow-esperado", required=True)
    parser.add_argument("--particion", required=True,
                        help="Nombre exacto de la partición de validación del experimento")
    args = parser.parse_args()
    rutas = {"arroz": args.arroz, "cana": args.cana}
    filas, errores = seleccion(args.seleccion, args.imagenes)
    for row in filas:
        if row["particion"] != args.particion.lower():
            errores.append({"fila": row["fila"], "ruta_relativa": row["ruta_relativa"],
                            "error": "Partición distinta de la validación declarada."})
    esperados, errores_conteo = conteos(args.conteos, filas)
    hashes, errores_modelo = modelos(rutas)
    errores += errores_conteo + errores_modelo
    if not filas:
        errores.append({"error": "No hay imágenes seleccionadas."})
    informe = {"esquema": 2, "estado": "error", "particion_objetivo": args.particion.lower(),
               "preprocesamiento": "exif_transpose_rgb_tf_resize_with_pad_224_bilinear_antialias_div255",
               "tensor_shape": [1, 224, 224, 3], "tensor_dtype": "float32_le",
               "tensorflow_esperado": args.tensorflow_esperado,
               "pillow_esperado": args.pillow_esperado, "modelos_sha256": hashes,
               "conteos_esperados": esperados, "seleccionadas": len(filas),
               "procesadas": 0, "registros": [], "errores": errores}
    if errores:
        escribir(args.salida, informe)
        print(json.dumps(errores, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1
    try:
        import numpy as np
        import PIL
        from PIL import Image, ImageOps
        import tensorflow as tf
        informe.update(tensorflow=tf.__version__, pillow=PIL.__version__,
                       numpy=np.__version__, python=sys.version.split()[0])
        if tf.__version__ != args.tensorflow_esperado or PIL.__version__ != args.pillow_esperado:
            raise ValueError("Versiones efectivas distintas de las declaradas en los experimentos.")
        motores = {c: motor(r, np, tf) for c, r in rutas.items()}
    except (ImportError, OSError, ValueError) as error:
        errores.append({"error": f"Entorno inválido: {error}"})
        escribir(args.salida, informe)
        print(errores[-1]["error"], file=sys.stderr)
        return 1
    # Las referencias binarias se escriben antes que el manifiesto final.
    args.salida.mkdir(parents=True, exist_ok=True)
    for row in filas:
        try:
            original = row["imagen"].read_bytes()
            huella = sha(original)
            if row["sha256_declarado"] and huella != row["sha256_declarado"]:
                raise ValueError("SHA-256 original distinto del declarado.")
            tensor = tensor_original(original, np, Image, ImageOps, tf)
            interpreter, entrada, salida = motores[row["cultivo"]]
            interpreter.set_tensor(entrada, tensor)
            interpreter.invoke()
            score = float(interpreter.get_tensor(salida)[0, 0])
            if not np.isfinite(score) or not 0 <= score <= 1:
                raise ValueError("Score fuera de [0,1].")
            nombre_original, nombre_tensor = f"original_{huella}.bin", f"tensor_{huella}.bin"
            (args.salida / nombre_original).write_bytes(original)
            (args.salida / nombre_tensor).write_bytes(tensor.tobytes())
            umbral = MODELOS[row["cultivo"]][1]
            informe["registros"].append({
                "ruta_relativa": row["ruta_relativa"], "cultivo": row["cultivo"],
                "particion": row["particion"], "sha256_original": huella,
                "original": nombre_original, "tensor": nombre_tensor,
                "sha256_tensor": sha(tensor.tobytes()), "score_referencia": score,
                "categoria_referencia": int(score >= umbral), "umbral": umbral})
        except Exception as error:
            errores.append({"fila": row["fila"], "ruta_relativa": row["ruta_relativa"],
                            "cultivo": row["cultivo"], "particion": row["particion"],
                            "error": f"{type(error).__name__}: {error}"})
    informe["procesadas"] = len(informe["registros"])
    if informe["procesadas"] != sum(esperados.values()):
        errores.append({"esperadas": sum(esperados.values()), "procesadas": informe["procesadas"],
                        "error": "No se procesaron todas las imágenes esperadas."})
    informe["estado"] = "listo" if not errores else "error"
    escribir(args.salida, informe)
    if errores:
        print(json.dumps(errores, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1
    print(f"Referencias listas: {informe['procesadas']} imágenes; {args.salida}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
