"""Verifica que la implementación HMAC-SHA256 en JavaScript (panel/firma.js)
produce exactamente lo mismo que la de Python, que es la que usa el servidor.

Ejecuta firma.js con Node.js si está instalado; si no, con JavaScriptCore de
macOS (osascript -l JavaScript). Se omite si no hay ninguno.
"""

import hashlib
import hmac
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

RAIZ = pathlib.Path(__file__).resolve().parent.parent
FIRMA_JS = (RAIZ / "panel" / "firma.js").read_text(encoding="utf-8")

CASOS = [
    ("", ""),
    ("ABCDE", "abc"),
    ("ABCDEFGHJKMNPQRSTUVW", "0123456789abcdef0123456789abcdef:copiar"),
    ("K" * 79, "bloque mayor que 64 bytes " * 10),  # clave más larga que un bloque
    ("CLAVE", "acentos ñ á é 🎉"),                    # UTF-8 multibyte
    ("X" * 64, "m" * 55),                            # rellenos en el límite de bloque
    ("X" * 64, "m" * 56),
]


def motor_js():
    if shutil.which("node"):
        return ["node"], "console.log(JSON.stringify(salida));"
    if shutil.which("osascript"):
        return ["osascript", "-l", "JavaScript"], "JSON.stringify(salida);"
    return None, None


class TestFirmaJS(unittest.TestCase):
    def test_coincide_con_python(self):
        comando, imprimir = motor_js()
        if not comando:
            self.skipTest("no hay motor de JavaScript disponible")
        script = (FIRMA_JS + "\nvar casos = " + json.dumps(CASOS) + ";\n"
                  "var salida = casos.map(function (c) { return Firma.hmac(c[0], c[1]); });\n"
                  + imprimir)
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
            f.write(script)
        r = subprocess.run(comando + [f.name], capture_output=True, text=True, timeout=60,
                           stdin=subprocess.DEVNULL)
        pathlib.Path(f.name).unlink()
        self.assertEqual(r.returncode, 0, r.stderr)
        js = json.loads(r.stdout.strip())
        esperado = [hmac.new(k.encode(), m.encode(), hashlib.sha256).hexdigest() for k, m in CASOS]
        self.assertEqual(js, esperado)


if __name__ == "__main__":
    unittest.main()
