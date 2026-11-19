import json
import math
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

import generar_referencias_integracion as generador


class SeleccionTest(unittest.TestCase):
    def test_subcarpetas_duplicados_y_ausencias_son_explicitos(self):
        with tempfile.TemporaryDirectory() as temporal:
            raiz = Path(temporal)
            (raiz / "arroz" / "validacion").mkdir(parents=True)
            (raiz / "arroz" / "validacion" / "a.png").write_bytes(b"prueba")
            csv = raiz / "seleccion.csv"
            csv.write_text(
                "ruta_relativa,cultivo,particion\n"
                "arroz/validacion/a.png,arroz,validacion\n"
                "arroz/validacion/a.png,arroz,validacion\n"
                "arroz/validacion/falta.png,arroz,validacion\n"
                "../fuera.png,arroz,validacion\n", encoding="utf-8")
            filas, errores = generador.seleccion(csv, raiz)
            self.assertEqual(len(filas), 1)
            self.assertEqual(filas[0]["ruta_relativa"], "arroz/validacion/a.png")
            self.assertEqual(len(errores), 3)
            self.assertIn("Entrada duplicada.", [e["error"] for e in errores])
            self.assertIn("Imagen no encontrada.", [e["error"] for e in errores])

    def test_conteo_vacio_y_conteo_distinto_fallan(self):
        with tempfile.TemporaryDirectory() as temporal:
            archivo = Path(temporal) / "conteos.json"
            archivo.write_text(json.dumps({"arroz/validacion": 0}), encoding="utf-8")
            _, errores = generador.conteos(archivo, [])
            self.assertTrue(errores)
            archivo.write_text(json.dumps({"arroz/validacion": 2}), encoding="utf-8")
            _, errores = generador.conteos(archivo, [
                {"cultivo": "arroz", "particion": "validacion"}])
            self.assertEqual(errores[0]["seleccionado"], 1)

    def test_modelo_alterado_se_rechaza_antes_de_inferir(self):
        with tempfile.TemporaryDirectory() as temporal:
            raiz = Path(temporal)
            arroz, cana = raiz / "arroz.tflite", raiz / "cana.tflite"
            arroz.write_bytes(b"modelo falso")
            cana.write_bytes(b"modelo falso")
            _, errores = generador.modelos({"arroz": arroz, "cana": cana})
            self.assertEqual(len(errores), 2)
            self.assertTrue(all(e["error"] == "SHA-256 de modelo distinto." for e in errores))

    def test_generacion_completa_crea_salida_inexistente(self):
        # Backend controlado: verifica archivos, trazabilidad y estado del
        # recorrido completo, sin afirmar equivalencia numérica con TensorFlow.
        class TensorFalso:
            def tobytes(self):
                return b"tensor-float32-controlado"

        class SalidaFalsa:
            def __getitem__(self, indices):
                return 0.8

        class MotorFalso:
            def set_tensor(self, indice, tensor):
                pass

            def invoke(self):
                pass

            def get_tensor(self, indice):
                return SalidaFalsa()

        np = types.ModuleType("numpy")
        np.__version__ = "prueba-np"
        np.isfinite = math.isfinite
        pil = types.ModuleType("PIL")
        pil.__version__ = "prueba-pillow"
        pil.Image = types.ModuleType("PIL.Image")
        pil.ImageOps = types.ModuleType("PIL.ImageOps")
        tf = types.ModuleType("tensorflow")
        tf.__version__ = "prueba-tf"
        proyecto = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as temporal:
            raiz = Path(temporal)
            imagen = raiz / "imagenes" / "arroz" / "validacion" / "a.jpg"
            imagen.parent.mkdir(parents=True)
            original = b"fotografia-original-controlada"
            imagen.write_bytes(original)
            seleccion = raiz / "seleccion.csv"
            seleccion.write_text(
                "ruta_relativa,cultivo,particion\n"
                "arroz/validacion/a.jpg,arroz,validacion\n", encoding="utf-8")
            conteos = raiz / "conteos.json"
            conteos.write_text('{"arroz/validacion":1}', encoding="utf-8")
            salida = raiz / "salida-nueva"
            self.assertFalse(salida.exists())
            argv = ["generar_referencias_integracion.py",
                    "--imagenes", str(raiz / "imagenes"),
                    "--seleccion", str(seleccion), "--conteos", str(conteos),
                    "--particion", "validacion",
                    "--arroz", str(proyecto / "assets" / "arroz.tflite"),
                    "--cana", str(proyecto / "assets" / "cana.tflite"),
                    "--tensorflow-esperado", "prueba-tf",
                    "--pillow-esperado", "prueba-pillow",
                    "--salida", str(salida)]
            with mock.patch.object(sys, "argv", argv), \
                    mock.patch.dict(sys.modules, {"numpy": np, "PIL": pil, "tensorflow": tf}), \
                    mock.patch.object(generador, "motor", return_value=(MotorFalso(), 0, 0)), \
                    mock.patch.object(generador, "tensor_original", return_value=TensorFalso()):
                self.assertEqual(generador.main(), 0)
            manifiesto = json.loads((salida / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifiesto["estado"], "listo")
            self.assertEqual(manifiesto["procesadas"], 1)
            self.assertEqual(manifiesto["errores"], [])
            registro = manifiesto["registros"][0]
            self.assertEqual(registro["ruta_relativa"], "arroz/validacion/a.jpg")
            self.assertEqual((salida / registro["original"]).read_bytes(), original)
            self.assertEqual((salida / registro["tensor"]).read_bytes(),
                             b"tensor-float32-controlado")


if __name__ == "__main__":
    unittest.main()
