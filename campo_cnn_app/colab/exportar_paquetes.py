"""Exporta tensores EXACTOS de test a un paquete CBENCH1, sin reentrenar.

Uso desde Colab: ejecutar la celda de configuración del cuaderno adjunto.
Requiere la carpeta de la partición reconstruida y el experimento final.
"""
from __future__ import annotations

import csv
import hashlib
import json
import shutil
import struct
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
import tensorflow as tf

MODELOS = {
    'arroz': ('0728e2ddedc0db0959870ef420c204df3094fd780ef520c0d3fb2b10a9090040',
              0.6501769423484802, 219, {'sano': 0, 'piricularia': 1}),
    'cana': ('9042f0dffc63a6c143fd64a8d36a34ab25bc96cb74b21e51df35d7e88a368bec',
             0.6862450242042542, 412, {'sano': 0, 'roya': 1}),
}
PREPROCESAMIENTO = 'rgb_exif_tf_bilinear_pad_224_div255_v1'
TENSOR_BYTES = 224 * 224 * 3 * 4


def sha_archivo(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for bloque in iter(lambda: f.read(1024 * 1024), b''):
            h.update(bloque)
    return h.hexdigest()


def preparar(path):
    # Mismo orden y mismas funciones que en 01_Entrenamiento_CNN.ipynb.
    with Image.open(path) as foto:
        rgb = np.asarray(ImageOps.exif_transpose(foto).convert('RGB'), dtype=np.uint8)
    tensor = tf.image.resize_with_pad(tf.cast(rgb, tf.float32), 224, 224,
                                       method='bilinear', antialias=True) / 255.0
    result = np.asarray(tensor.numpy(), dtype='<f4')
    assert result.shape == (224, 224, 3) and result.nbytes == TENSOR_BYTES
    return result


def exportar(cultivo, raiz_datos, experimento, destino):
    if cultivo not in MODELOS:
        raise ValueError('Cultivo no reconocido.')
    sha_esperado, umbral, cantidad, clases = MODELOS[cultivo]
    raiz_datos, experimento, destino = map(Path, (raiz_datos, experimento, destino))
    modelo = experimento / 'modelo_float32.tflite'
    meta = json.loads((experimento / 'metadatos_modelo.json').read_text(encoding='utf-8'))
    fin = json.loads((experimento / 'test_final.json').read_text(encoding='utf-8'))
    manifest = raiz_datos / 'manifest.csv'
    if sha_archivo(modelo) != sha_esperado or meta['sha256_tflite'] != sha_esperado:
        raise ValueError('El modelo no coincide con los pesos fijos de este prototipo.')
    if meta['umbral_positivo_inclusivo'] != umbral or meta['preprocesamiento']['version'] != PREPROCESAMIENTO:
        raise ValueError('Metadatos de umbral o preprocesamiento incompatibles.')
    if fin['modelo_sha256'] != sha_esperado or fin['manifest_sha256'] != sha_archivo(manifest):
        raise ValueError('El test final corresponde a otra versión del modelo o inventario.')
    with manifest.open(encoding='utf-8-sig', newline='') as f:
        filas = [r for r in csv.DictReader(f, delimiter=';') if r['particion'] == 'test']
    if len(filas) != cantidad or len({r['archivo'] for r in filas}) != cantidad:
        raise ValueError('Falta alguna foto de test o hay duplicados.')
    if {r['etiqueta'] for r in filas} != {'0', '1'}:
        raise ValueError('El test debe contener ambas clases.')

    interprete = tf.lite.Interpreter(model_path=str(modelo), num_threads=1)
    interprete.allocate_tensors()
    entrada = interprete.get_input_details()[0]
    salida = interprete.get_output_details()[0]
    if tuple(entrada['shape']) != (1, 224, 224, 3) or entrada['dtype'] != np.float32:
        raise ValueError('Tensor de entrada incompatible.')
    if tuple(salida['shape']) != (1, 1) or salida['dtype'] != np.float32:
        raise ValueError('Tensor de salida incompatible.')

    destino.parent.mkdir(parents=True, exist_ok=True)
    temporal = Path(tempfile.mkdtemp(prefix='cbench_', dir=str(destino.parent)))
    datos = temporal / 'tensores.bin'
    try:
        items = []
        with datos.open('wb') as out:
            for i, fila in enumerate(filas, 1):
                relativo = Path(fila['archivo'])
                if (relativo.is_absolute() or '..' in relativo.parts or
                    not fila['archivo'].startswith(f"test/{fila['clase']}/") or
                    fila['clase'] not in clases or int(fila['etiqueta']) != clases[fila['clase']]):
                    raise ValueError(f'Ruta o etiqueta inválida: {relativo}')
                original = (raiz_datos / relativo).resolve()
                if not original.is_relative_to(raiz_datos.resolve()) or not original.is_file():
                    raise FileNotFoundError(original)
                if sha_archivo(original) != fila['sha256_archivo']:
                    raise ValueError(f'La imagen no coincide con el inventario: {relativo}')
                tensor = preparar(original)
                interprete.set_tensor(entrada['index'], tensor[None, ...])
                interprete.invoke()
                score = float(interprete.get_tensor(salida['index'])[0][0])
                bruto = tensor.tobytes(order='C')
                out.write(bruto)
                items.append({'archivo': fila['archivo'], 'etiqueta': int(fila['etiqueta']),
                              'sha256_tensor': hashlib.sha256(bruto).hexdigest(),
                              'score_referencia': score})
                if i % 50 == 0: print(f'{cultivo}: {i}/{cantidad}')
        cabecera = json.dumps({
            'schema': 1, 'cultivo': cultivo, 'particion': 'test',
            'modelo_sha256': sha_esperado, 'manifest_sha256': sha_archivo(manifest),
            'preprocesamiento': PREPROCESAMIENTO, 'umbral': umbral,
            'tensor_bytes': TENSOR_BYTES, 'items': items,
        }, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode('utf-8')
        if len(cabecera) > 1000000:
            raise ValueError('Cabecera demasiado grande.')
        tmp = destino.with_suffix(destino.suffix + '.part')
        with tmp.open('wb') as out, datos.open('rb') as src:
            out.write(b'CBENCH1\n')
            out.write(struct.pack('<I', len(cabecera)))
            out.write(cabecera)
            shutil.copyfileobj(src, out, length=1024 * 1024)
        tmp.replace(destino)
        print(f'Paquete verificado: {destino} ({destino.stat().st_size:,} bytes)')
        return destino
    finally:
        shutil.rmtree(temporal)
