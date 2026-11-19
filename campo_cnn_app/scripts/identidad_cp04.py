"""Identidad CP04 equivalente a scripts/identidad_cp04.ps1 (Linux/Docker).

La lista de archivos se lee del propio .ps1 para que ambas versiones no
diverjan. Produce el mismo SHA-256 con los mismos archivos y la misma
revision de Flutter, engine y Dart.
Uso: python3 scripts/identidad_cp04.py [carpeta_del_proyecto]
"""

import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


def archivos(ps1):
    texto = ps1.read_text(encoding="utf-8-sig")
    bloque = re.search(r"\$archivos\s*=\s*@\((.*?)\)", texto, re.S)
    if not bloque:
        raise SystemExit(f"No se encontro la lista de archivos en {ps1}")
    lista = re.findall(r"'([^']+)'", bloque.group(1))
    if not lista:
        raise SystemExit("Lista de archivos vacia.")
    return lista


def flutter_version():
    flutter = shutil.which("flutter")
    if not flutter:
        raise SystemExit("flutter no esta en PATH.")
    salida = subprocess.run([flutter, "--version", "--machine"], capture_output=True,
                            text=True, check=True).stdout
    # Ignora avisos previos al JSON (por ejemplo, ejecucion como root).
    return json.loads(salida[salida.index("{"):salida.rindex("}") + 1])


def main():
    proyecto = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    lineas = []
    for relativo in archivos(proyecto / "scripts" / "identidad_cp04.ps1"):
        ruta = proyecto / relativo
        if not ruta.is_file():
            raise SystemExit(f"Falta {ruta}")
        lineas.append(f"{relativo} {hashlib.sha256(ruta.read_bytes()).hexdigest()}")
    version = flutter_version()
    lineas += [f"flutter {version['frameworkRevision']}",
               f"engine {version['engineRevision']}",
               f"dart {version['dartSdkVersion']}"]
    print(hashlib.sha256(("\n".join(lineas) + "\n").encode("utf-8")).hexdigest())


if __name__ == "__main__":
    main()
