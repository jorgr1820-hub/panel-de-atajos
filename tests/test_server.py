"""Pruebas unitarias de la lógica de seguridad de panel/server.py.

No arrancan servidores ni ejecutan acciones: prueban las funciones puras
(filtros, retos, bloqueos, firmas). Se ejecutan con:
    /usr/bin/python3 -m unittest discover -s tests -v
"""

import hashlib
import hmac
import importlib.util
import io
import pathlib
import sys
import time
import unittest

RAIZ = pathlib.Path(__file__).resolve().parent.parent


def cargar_servidor():
    sys.stdin = io.StringIO("")  # sin secretos: el módulo arranca sin TLS ni dispositivos
    spec = importlib.util.spec_from_file_location("server", RAIZ / "panel" / "server.py")
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    return modulo


srv = cargar_servidor()

CLAVE_IPAD = "ABCDE-FGHJK-MNPQR-STUVW"
CLAVE_OTRO = "WXYZ2-34567-89ABC-DEFGH"


def firmar(clave, reto, accion):
    return hmac.new(srv.normalizar(clave), f"{reto}:{accion}".encode(), hashlib.sha256).hexdigest()


class EstadoLimpio(unittest.TestCase):
    def setUp(self):
        with srv.lock:
            srv.retos.clear()
            srv.fallos.clear()
            srv.fallos_total.clear()
            srv.vistos.clear()
        srv.fijar_dispositivos([
            {"id": "ipad", "nombre": "iPad", "clave": CLAVE_IPAD},
            {"id": "otro", "nombre": "Otro", "clave": CLAVE_OTRO},
        ])


class TestSuperficie(unittest.TestCase):
    """Cambios en lo que el servidor expone deben ser deliberados."""

    def test_acciones_permitidas(self):
        self.assertEqual(set(srv.ACTIONS), {"copiar", "pegar", "seleccionar", "enter", "notas",
                                            "musica", "playpausa", "siguiente", "anterior"})

    def test_archivos_publicos(self):
        self.assertEqual(set(srv.STATIC), {"/", "/app.js", "/firma.js"})

    def test_cabeceras_de_seguridad(self):
        for cabecera in ("Content-Security-Policy", "X-Frame-Options", "X-Content-Type-Options",
                         "Referrer-Policy", "Cache-Control"):
            self.assertIn(cabecera, srv.SECURITY_HEADERS)
        self.assertIn("frame-ancestors 'none'", srv.SECURITY_HEADERS["Content-Security-Policy"])


class TestFiltrosDeRed(unittest.TestCase):
    def test_ip_permitida(self):
        for ip in ("192.168.1.10", "10.0.0.5", "172.16.3.4", "127.0.0.1"):
            self.assertTrue(srv.ip_permitida(ip), ip)
        for ip in ("8.8.8.8", "1.1.1.1", "169.254.10.10", "no-es-ip", "100.64.0.1"):
            self.assertFalse(srv.ip_permitida(ip), ip)

    def test_host_permitido(self):
        for host in ("192.168.1.10:8787", "localhost", "mac.local:8787", "127.0.0.1:8787"):
            self.assertTrue(srv.host_permitido(host), host)
        for host in ("", "evil.example.com", "evil.example.com:8787", "8.8.8.8:8787", "mac.local.evil.com"):
            self.assertFalse(srv.host_permitido(host), host)


class TestClaves(EstadoLimpio):
    def test_normalizar(self):
        self.assertEqual(srv.normalizar("abcde-fghjk mnpqr"), b"ABCDEFGHJKMNPQR")

    def test_rechaza_claves_cortas(self):
        srv.fijar_dispositivos([{"id": "x", "nombre": "x", "clave": "CORTA"}])
        self.assertEqual(srv.dispositivos, [])

    def test_firma_identifica_al_dispositivo(self):
        d = srv.verificar_firma("reto:copiar", firmar(CLAVE_OTRO, "reto", "copiar"))
        self.assertEqual(d["id"], "otro")

    def test_firma_con_clave_desconocida(self):
        self.assertIsNone(srv.verificar_firma("reto:copiar", firmar("ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ", "reto", "copiar")))

    def test_firma_ligada_a_la_accion(self):
        firma_estado = firmar(CLAVE_IPAD, "reto", "estado")
        self.assertIsNone(srv.verificar_firma("reto:copiar", firma_estado))

    def test_revocar_invalida_la_clave(self):
        firma = firmar(CLAVE_IPAD, "reto", "copiar")
        srv.fijar_dispositivos([{"id": "otro", "nombre": "Otro", "clave": CLAVE_OTRO}])
        self.assertIsNone(srv.verificar_firma("reto:copiar", firma))


class TestRetos(EstadoLimpio):
    def test_un_solo_uso(self):
        r = srv.emitir_reto("192.168.1.10")
        self.assertTrue(srv.consumir_reto(r, "192.168.1.10"))
        self.assertFalse(srv.consumir_reto(r, "192.168.1.10"))

    def test_ligado_a_la_ip(self):
        r = srv.emitir_reto("192.168.1.10")
        self.assertFalse(srv.consumir_reto(r, "192.168.1.99"))

    def test_caduca(self):
        r = srv.emitir_reto("192.168.1.10")
        with srv.lock:
            srv.retos[r] = (time.time() - 1, "192.168.1.10")
        self.assertFalse(srv.consumir_reto(r, "192.168.1.10"))

    def test_reto_inventado(self):
        self.assertFalse(srv.consumir_reto("00", "192.168.1.10"))

    def test_limite_por_ip(self):
        for _ in range(srv.RETOS_POR_IP + 5):
            srv.emitir_reto("192.168.1.10")
        mios = [r for r, (_, ip) in srv.retos.items() if ip == "192.168.1.10"]
        self.assertLessEqual(len(mios), srv.RETOS_POR_IP)

    def test_un_equipo_no_desplaza_a_otro(self):
        r = srv.emitir_reto("192.168.1.20")
        for _ in range(srv.RETOS_POR_IP * 3):
            srv.emitir_reto("192.168.1.10")
        self.assertTrue(srv.consumir_reto(r, "192.168.1.20"))

    def test_retos_aleatorios(self):
        self.assertEqual(len({srv.emitir_reto(f"10.0.0.{i}") for i in range(50)}), 50)


class TestBloqueos(EstadoLimpio):
    def test_bloqueo_por_ip(self):
        for _ in range(srv.FALLOS_IP):
            srv.registrar_fallo("192.168.1.66")
        self.assertTrue(srv.bloqueado("192.168.1.66"))
        self.assertFalse(srv.bloqueado("192.168.1.10"))

    def test_bloqueo_expira(self):
        with srv.lock:
            srv.fallos["192.168.1.66"] = [time.time() - srv.BLOQUEO - 1] * srv.FALLOS_IP
        self.assertFalse(srv.bloqueado("192.168.1.66"))

    def test_bloqueo_global(self):
        for i in range(srv.FALLOS_TOTAL):
            srv.registrar_fallo(f"192.168.1.{i}")
        self.assertTrue(srv.bloqueado("192.168.1.250"))


if __name__ == "__main__":
    unittest.main()
