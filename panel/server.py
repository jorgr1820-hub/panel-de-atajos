#!/usr/bin/env python3
"""Panel de atajos: sirve una página de botones a los dispositivos emparejados y
ejecuta acciones fijas en esta Mac.

Lo arranca "Panel de atajos.app", que le entrega los secretos por la entrada
estándar (nunca por argumentos, variables de entorno ni archivos):
    {"admin_token": "...", "dispositivos": [{"id", "nombre", "clave"}],
     "tls": {"cert_pem", "key_pem", "ca_pem"}}

Puertos:
  8787  HTTPS  panel para los dispositivos (red local)
  8788  HTTP   solo para descargar el certificado de la CA del panel (red local)
  8789  HTTP   administración para la app; escucha únicamente en 127.0.0.1

Modelo de seguridad (ver SEGURIDAD.md):
- HTTPS con una CA propia restringida a la red local: un atacante en el Wi-Fi no
  puede leer ni inyectar código en la página.
- Cada toque se firma con HMAC-SHA256 sobre un reto de un solo uso con la clave
  del dispositivo: la clave nunca viaja y una petición capturada no se repite.
- Solo existen las acciones de ACTIONS; nada de lo que llega se ejecuta tal cual.
- Bloqueos por intentos fallidos y límite de retos por equipo.
- El registro vive solo en memoria.
"""

import collections
import hashlib
import hmac
import ipaddress
import json
import os
import plistlib
import secrets
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
PUERTO, PUERTO_CERT, PUERTO_ADMIN = 8787, 8788, 8789

STATIC = {"/": ("index.html", "text/html; charset=utf-8"),
          "/firma.js": ("firma.js", "application/javascript; charset=utf-8"),
          "/app.js": ("app.js", "application/javascript; charset=utf-8")}

RETO_TTL = 30          # segundos que vale un reto
RETOS_MAX = 64         # retos pendientes en total
RETOS_POR_IP = 8       # retos pendientes por equipo (evita que uno acapare la cola)
BLOQUEO = 300          # segundos de bloqueo
FALLOS_IP = 8          # fallos por equipo antes de bloquear
FALLOS_TOTAL = 25      # fallos de todos los equipos antes de bloquear el panel
CONECTADO = 45         # segundos sin latido para considerar desconectado un dispositivo
MAX_ADMIN = 65536      # tamaño máximo de una petición de administración

SECURITY_HEADERS = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": ("default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; "
                                "connect-src 'self'; img-src 'self'; frame-ancestors 'none'; "
                                "base-uri 'none'; form-action 'none'"),
}

os.umask(0o077)
lock = threading.Lock()


def leer_secretos():
    if sys.stdin is None or sys.stdin.isatty():
        return {}
    datos = sys.stdin.read()
    return json.loads(datos) if datos.strip() else {}


SECRETOS = leer_secretos()
ADMIN_TOKEN = SECRETOS.get("admin_token", "")
TLS = SECRETOS.get("tls")
CA_DER = ssl.PEM_cert_to_DER_cert(TLS["ca_pem"]) if TLS else b""


# --- Registro en memoria ---------------------------------------------------

eventos = collections.deque(maxlen=1000)
_seq = 0


def evento(texto):
    global _seq
    with lock:
        _seq += 1
        eventos.append({"seq": _seq, "hora": time.strftime("%H:%M:%S"), "texto": texto})


# --- Dispositivos ----------------------------------------------------------

def normalizar(clave):
    return clave.replace("-", "").replace(" ", "").upper().encode()


dispositivos = []  # [{"id", "nombre", "clave": bytes}]
vistos = {}        # id -> {"ip", "visto", "conectado"}


def fijar_dispositivos(lista):
    global dispositivos
    nuevos = [{"id": str(d["id"]), "nombre": str(d["nombre"])[:40], "clave": normalizar(str(d["clave"]))}
              for d in lista if len(normalizar(str(d.get("clave", "")))) >= 16]
    with lock:
        dispositivos = nuevos
        ids = {d["id"] for d in nuevos}
        for did in [k for k in vistos if k not in ids]:
            del vistos[did]


fijar_dispositivos(SECRETOS.get("dispositivos", []))
del SECRETOS  # las claves quedan solo en `dispositivos`


def verificar_firma(mensaje, firma):
    """Devuelve el dispositivo cuya clave produce esa firma, o None."""
    encontrado = None
    with lock:
        lista = list(dispositivos)
    for d in lista:  # se comparan todas para no revelar por tiempo cuál coincide
        esperada = hmac.new(d["clave"], mensaje.encode(), hashlib.sha256).hexdigest()
        if hmac.compare_digest(firma, esperada):
            encontrado = d
    return encontrado


def marcar_visto(d, ip):
    with lock:
        v = vistos.get(d["id"])
        nuevo = v is None or not v["conectado"]
        vistos[d["id"]] = {"ip": ip, "visto": time.time(), "conectado": True}
    if nuevo:
        evento(f"{d['nombre']} conectado desde {ip}")


def vigilar_conexiones():
    while True:
        time.sleep(5)
        caidos = []
        with lock:
            nombres = {d["id"]: d["nombre"] for d in dispositivos}
            for did, v in vistos.items():
                if v["conectado"] and time.time() - v["visto"] > CONECTADO:
                    v["conectado"] = False
                    caidos.append(nombres.get(did, did))
        for n in caidos:
            evento(f"{n} desconectado")


# --- Acciones --------------------------------------------------------------

def osa(script):
    """Ejecuta AppleScript. Devuelve None si salió bien o el mensaje de error."""
    try:
        r = subprocess.run(["/usr/bin/osascript", "-e", script], check=False,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=10)
    except subprocess.TimeoutExpired:
        return "macOS está esperando un permiso: revisa la pantalla de la Mac"
    if r.returncode == 0:
        return None
    err = r.stderr.decode(errors="replace")
    if "1002" in err or "-1719" in err or "assistive" in err or "-25211" in err:
        return "Falta permiso de Accesibilidad en la Mac"
    if "-1743" in err:
        return "Falta permiso de Automatización en la Mac"
    return "Error al ejecutar la acción"


def keystroke(key, cmd=False):
    using = " using command down" if cmd else ""
    return osa(f'tell application "System Events" to keystroke "{key}"{using}')


def open_app(name):
    r = subprocess.run(["/usr/bin/open", "-a", name], check=False, stderr=subprocess.DEVNULL)
    return None if r.returncode == 0 else f"No se pudo abrir {name}"


def music_app():
    # Controla Spotify si está abierto; si no, la app Música.
    running = subprocess.run(["/usr/bin/pgrep", "-x", "Spotify"], stdout=subprocess.DEVNULL).returncode == 0
    return "Spotify" if running else "Music"


_ax = {"valor": False, "cuando": 0.0}


def accesibilidad():
    if time.time() - _ax["cuando"] > 10:  # osascript es lento; se revisa cada 10 s como máximo
        try:
            r = subprocess.run(["/usr/bin/osascript", "-e", 'tell application "System Events" to get UI elements enabled'],
                               capture_output=True, timeout=10)
            _ax["valor"] = r.stdout.strip() == b"true"
        except subprocess.TimeoutExpired:
            _ax["valor"] = False
        _ax["cuando"] = time.time()
    return _ax["valor"]


ACTIONS = {
    "copiar": lambda: keystroke("c", cmd=True),
    "pegar": lambda: keystroke("v", cmd=True),
    "seleccionar": lambda: keystroke("a", cmd=True),
    "enter": lambda: osa('tell application "System Events" to key code 36'),
    "notas": lambda: open_app("Notes"),
    "musica": lambda: open_app("Spotify"),
    "playpausa": lambda: osa(f'tell application "{music_app()}" to playpause'),
    "siguiente": lambda: osa(f'tell application "{music_app()}" to next track'),
    "anterior": lambda: osa(f'tell application "{music_app()}" to previous track'),
}


# --- Retos y bloqueos ------------------------------------------------------

retos = {}        # reto -> (caduca, ip)
fallos = {}       # ip -> [tiempos]
fallos_total = []


def emitir_reto(ip):
    ahora = time.time()
    with lock:
        for r in [r for r, (exp, _) in retos.items() if exp < ahora]:
            del retos[r]
        mios = sorted((exp, r) for r, (exp, i) in retos.items() if i == ip)
        while len(mios) >= RETOS_POR_IP:
            del retos[mios.pop(0)[1]]
        while len(retos) >= RETOS_MAX:
            del retos[min(retos, key=lambda r: retos[r][0])]
        reto = secrets.token_hex(16)
        retos[reto] = (ahora + RETO_TTL, ip)
    return reto


def consumir_reto(reto, ip):
    with lock:
        exp, dueño = retos.pop(reto, (0, None))
    return dueño == ip and exp >= time.time()  # el reto solo vale para quien lo pidió


def bloqueado(ip):
    ahora = time.time()
    with lock:
        fallos_total[:] = [t for t in fallos_total if ahora - t < BLOQUEO]
        mios = fallos.get(ip, [])
        mios[:] = [t for t in mios if ahora - t < BLOQUEO]
        return len(mios) >= FALLOS_IP or len(fallos_total) >= FALLOS_TOTAL


def registrar_fallo(ip):
    ahora = time.time()
    with lock:
        fallos.setdefault(ip, []).append(ahora)
        fallos_total.append(ahora)
        n, total = len(fallos[ip]), len(fallos_total)
    if n == FALLOS_IP:
        evento(f"⚠️ {ip} bloqueado 5 minutos por intentos fallidos")
    if total == FALLOS_TOTAL:
        evento("⚠️ Demasiados fallos en la red: panel bloqueado 5 minutos")


def ip_permitida(ip):
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return a.is_loopback or (a.is_private and not a.is_link_local)


def host_permitido(host):
    if not host:
        return False
    nombre = host.rsplit(":", 1)[0] if not host.endswith("]") else host
    nombre = nombre.strip("[]").lower()
    if nombre == "localhost" or nombre.endswith(".local"):
        return True
    return ip_permitida(nombre)


def ip_local():
    try:  # no envía nada: solo pregunta al sistema qué interfaz usaría
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("192.0.2.1", 9))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


# --- HTTP: base común ------------------------------------------------------

class Base(BaseHTTPRequestHandler):
    timeout = 10
    server_version = "Panel"
    sys_version = ""

    def _send(self, code, body, ctype="application/json; charset=utf-8", extra=None):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        for k, v in {**SECURITY_HEADERS, **(extra or {})}.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    def _error(self, code, msg):
        self._json(code, {"error": msg})

    def _filtro_red(self):
        ip = self.client_address[0]
        if not ip_permitida(ip):
            evento(f"{ip} rechazado: fuera de la red local")
            self._error(403, "solo red local")
            return False
        if not host_permitido(self.headers.get("Host", "")):
            evento(f"{ip} rechazado: host no permitido")
            self._error(403, "host no permitido")
            return False
        origin = self.headers.get("Origin")
        if origin and origin.split("://", 1)[-1] != self.headers.get("Host"):
            evento(f"{ip} rechazado: origen ajeno")
            self._error(403, "origen no permitido")
            return False
        return True

    def do_PUT(self):
        self._error(405, "método no permitido")

    do_DELETE = do_PATCH = do_OPTIONS = do_PUT

    def log_message(self, fmt, *args):
        pass  # los eventos importantes van al registro en memoria


# --- 8787: panel para los dispositivos -------------------------------------

class Panel(Base):
    def do_GET(self):
        if not self._filtro_red():
            return
        if self.path in STATIC:
            name, ctype = STATIC[self.path]
            with open(os.path.join(HERE, name), "rb") as f:
                extra = {"Strict-Transport-Security": "max-age=31536000"} if TLS else None
                return self._send(200, f.read(), ctype, extra)
        if self.path == "/reto":
            ip = self.client_address[0]
            if bloqueado(ip):
                return self._error(429, "demasiados intentos, espera 5 minutos")
            return self._json(200, {"reto": emitir_reto(ip)})
        self._error(404, "no encontrado")

    def do_POST(self):
        if not self._filtro_red():
            return
        ip = self.client_address[0]
        if int(self.headers.get("Content-Length") or 0) > 0:
            return self._error(413, "sin cuerpo")
        if bloqueado(ip):
            return self._error(429, "demasiados intentos, espera 5 minutos")

        name = self.path[len("/accion/"):] if self.path.startswith("/accion/") else ""
        if name not in ACTIONS and name != "estado":
            return self._error(404, "acción desconocida")

        reto = self.headers.get("X-Reto", "")
        firma = self.headers.get("X-Firma", "")
        d = verificar_firma(f"{reto}:{name}", firma) if consumir_reto(reto, ip) else None
        if d is None:
            registrar_fallo(ip)
            evento(f"{ip} clave incorrecta ({name})")
            return self._error(401, "clave incorrecta")
        marcar_visto(d, ip)

        if name == "estado":
            return self._json(200, {"ok": True, "accesibilidad": accesibilidad(), "nombre": d["nombre"]})

        error = ACTIONS[name]()
        evento(f"{d['nombre']}: {name}" + (f" — {error}" if error else ""))
        if error:
            return self._error(500, error)
        self._send(200, '{"ok":true}')


# --- 8788: descarga del certificado de la CA -------------------------------

PAGINA_CERT = """<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Certificado del panel</title></head>
<body style="font-family:-apple-system,Helvetica;background:#111;color:#eee;padding:24px;max-width:620px;margin:auto">
<h2>1. Instala el certificado del panel</h2>
<p><a href="/panel.mobileconfig" style="color:#6cf;font-size:22px">Instalar perfil del panel</a></p>
<p style="font-size:14px;color:#888">Si no funciona, prueba con el <a href="/panel-ca.cer" style="color:#6cf">certificado suelto</a>.</p>
<p>Huella SHA-256 (compárala con la que muestra la app en la Mac):</p>
<p style="font-family:Menlo,monospace;font-size:13px;word-break:break-all">{huella}</p>
<ol><li>Toca «Instalar perfil del panel» y luego «Permitir».</li>
<li>Ajustes → Perfil descargado → Instalar (dirá «No verificado»: es normal, lo creó tu Mac).</li>
<li>Ajustes → General → Información → Ajustes de confianza de certificados → activa «Panel de atajos CA».</li></ol>
<h2>2. Empareja</h2><p>Escanea el código QR de la app de la Mac (Nueva conexión o Mostrar código).</p>
</body></html>"""


def perfil_ios():
    """Perfil de configuración con la CA del panel. Los UUID salen de la huella de
    la CA, así reinstalarlo reemplaza al anterior en vez de duplicarlo."""
    huella = hashlib.sha256(CA_DER).hexdigest()
    perfil = {
        "PayloadType": "Configuration", "PayloadVersion": 1,
        "PayloadIdentifier": "local.jordan.panel-de-atajos",
        "PayloadUUID": str(uuid.uuid5(uuid.NAMESPACE_OID, "perfil" + huella)).upper(),
        "PayloadDisplayName": "Panel de atajos",
        "PayloadDescription": "Permite conectarse por HTTPS al Panel de atajos de tu Mac. "
                              "Solo es válido para direcciones de la red local.",
        "PayloadContent": [{
            "PayloadType": "com.apple.security.root", "PayloadVersion": 1,
            "PayloadIdentifier": "local.jordan.panel-de-atajos.ca",
            "PayloadUUID": str(uuid.uuid5(uuid.NAMESPACE_OID, "ca" + huella)).upper(),
            "PayloadDisplayName": "Panel de atajos CA",
            "PayloadCertificateFileName": "panel-ca.cer",
            "PayloadContent": CA_DER,
        }],
    }
    return plistlib.dumps(perfil)


class Certificado(Base):
    def do_GET(self):
        if not self._filtro_red():
            return
        if not TLS:
            return self._error(404, "sin certificado")
        if self.path == "/":
            huella = hashlib.sha256(CA_DER).hexdigest().upper()
            huella = ":".join(huella[i:i + 2] for i in range(0, len(huella), 2))
            return self._send(200, PAGINA_CERT.replace("{huella}", huella), "text/html; charset=utf-8")
        # Sin "Content-Disposition: attachment": Safari de iOS 12 no descarga
        # archivos, pero sí abre perfiles y certificados para instalarlos.
        if self.path == "/panel.mobileconfig":
            return self._send(200, perfil_ios(), "application/x-apple-aspen-config")
        if self.path == "/panel-ca.cer":
            return self._send(200, CA_DER, "application/x-x509-ca-cert")
        self._error(404, "no encontrado")

    def do_POST(self):
        self._error(405, "método no permitido")


# --- 8789: administración (solo 127.0.0.1) ---------------------------------

class Admin(Base):
    def _autorizado(self):
        return (ADMIN_TOKEN and self.client_address[0] == "127.0.0.1"
                and self.headers.get("Host") == f"127.0.0.1:{PUERTO_ADMIN}"
                and "Origin" not in self.headers  # un navegador siempre manda Origin en POST/fetch
                and hmac.compare_digest(self.headers.get("X-Admin", ""), ADMIN_TOKEN))

    def do_GET(self):
        if not self._autorizado():
            return self._error(403, "no autorizado")
        url = urlparse(self.path)
        if url.path == "/estado":
            ahora = time.time()
            with lock:
                lista = [{"id": d["id"], "nombre": d["nombre"],
                          "ip": vistos.get(d["id"], {}).get("ip"),
                          "visto_hace": (ahora - vistos[d["id"]]["visto"]) if d["id"] in vistos else None,
                          "conectado": vistos.get(d["id"], {}).get("conectado", False)}
                         for d in dispositivos]
            return self._json(200, {"ip": ip_local(), "puerto": PUERTO, "puerto_cert": PUERTO_CERT,
                                    "tls": bool(TLS), "accesibilidad": accesibilidad(), "dispositivos": lista})
        if url.path == "/log":
            try:
                desde = int(parse_qs(url.query).get("desde", ["0"])[0])
            except ValueError:
                desde = 0
            with lock:
                nuevos = [e for e in eventos if e["seq"] > desde]
                ultimo = _seq
            return self._json(200, {"eventos": nuevos, "ultimo": ultimo})
        self._error(404, "no encontrado")

    def do_POST(self):
        if not self._autorizado():
            return self._error(403, "no autorizado")
        if self.path != "/dispositivos":
            return self._error(404, "no encontrado")
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_ADMIN:
            return self._error(413, "demasiado grande")
        try:
            fijar_dispositivos(json.loads(self.rfile.read(n))["dispositivos"])
        except (ValueError, KeyError, TypeError):
            return self._error(400, "JSON inválido")
        self._json(200, {"ok": True})


# --- Arranque --------------------------------------------------------------

def contexto_tls():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    carpeta = tempfile.mkdtemp()  # 0700; los archivos se borran justo después de cargarlos
    cert, clave = os.path.join(carpeta, "c.pem"), os.path.join(carpeta, "k.pem")
    try:
        with open(cert, "w") as f:
            f.write(TLS["cert_pem"] + "\n" + TLS["ca_pem"])
        with open(clave, "w") as f:
            f.write(TLS["key_pem"])
        ctx.load_cert_chain(cert, clave)
    finally:
        for p in (cert, clave):
            if os.path.exists(p):
                os.remove(p)
        os.rmdir(carpeta)
    return ctx


class ServidorTLS(ThreadingHTTPServer):
    daemon_threads = True
    ctx = None

    def get_request(self):
        sock, addr = self.socket.accept()
        # El saludo TLS se hace en el hilo de la conexión, no aquí: un cliente lento
        # no puede bloquear al resto.
        return self.ctx.wrap_socket(sock, server_side=True, do_handshake_on_connect=False), addr


def vigilar_padre():
    # Si la app de la Mac se cierra de golpe, el servidor no se queda huérfano.
    padre = os.getppid()
    while True:
        if os.getppid() != padre:
            os._exit(0)
        time.sleep(2)


def iniciar(clase, direccion, puerto, ctx=None):
    if ctx:
        srv = ServidorTLS((direccion, puerto), clase)
        srv.ctx = ctx
    else:
        srv = ThreadingHTTPServer((direccion, puerto), clase)
        srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


if __name__ == "__main__":
    try:
        iniciar(Panel, "0.0.0.0", PUERTO, contexto_tls() if TLS else None)
        if TLS:
            iniciar(Certificado, "0.0.0.0", PUERTO_CERT)
        if ADMIN_TOKEN:
            iniciar(Admin, "127.0.0.1", PUERTO_ADMIN)
    except OSError as e:
        print(f"No se pudo abrir el puerto: {e}", file=sys.stderr)
        sys.exit(1)
    signal.signal(signal.SIGTERM, lambda *_: os._exit(0))
    threading.Thread(target=vigilar_conexiones, daemon=True).start()
    if ADMIN_TOKEN:
        threading.Thread(target=vigilar_padre, daemon=True).start()
    esquema = "https" if TLS else "http"
    evento(f"Panel encendido en {esquema}://{ip_local()}:{PUERTO}")
    if not TLS:
        evento("⚠️ Sin certificado: el panel funciona sin HTTPS")
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
