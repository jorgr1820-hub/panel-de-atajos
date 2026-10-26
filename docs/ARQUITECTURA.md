# Arquitectura

Este documento describe los componentes, el protocolo y la API del Panel de
atajos. Para el modelo de amenazas, ver [SEGURIDAD.md](../SEGURIDAD.md).

## Índice

1. [Componentes](#componentes)
2. [Secuencia de arranque](#secuencia-de-arranque)
3. [Red y protocolo](#red-y-protocolo)
4. [Autenticación](#autenticación)
5. [Referencia de la API](#referencia-de-la-api)
6. [Gestión de secretos y certificados](#gestión-de-secretos-y-certificados)
7. [Configuración](#configuración)
8. [Cómo extender la API](#cómo-extender-la-api)
9. [Decisiones de diseño](#decisiones-de-diseño)

## Componentes

| Componente | Archivo | Responsabilidad |
|---|---|---|
| App de control | `app/PanelApp.swift` | Interfaz SwiftUI y barra de menú; ciclo de vida del servidor; Llavero; emisión de certificados; Touch ID; verificación de integridad; arranque al iniciar sesión |
| Servidor | `panel/server.py` | Tres servidores HTTP en hilos: panel (HTTPS), descarga del certificado y administración; autenticación; límites; ejecución de acciones |
| Cliente | `panel/index.html`, `panel/app.js` | Página de botones; firma de peticiones; latido de conexión; emparejamiento por QR |
| Firma en el cliente | `panel/firma.js` | HMAC-SHA256 en ES5 (Safari de iOS 12 no expone `crypto.subtle` sin contexto seguro) |
| Compilación | `app/compilar.sh` | Copia el servidor al paquete, genera `Huellas.swift` con los SHA-256, compila y firma |

El servidor no tiene dependencias externas: usa `http.server`, `ssl`, `hmac` y
`secrets` de la biblioteca estándar.

## Secuencia de arranque

```
App macOS                                          server.py
─────────                                          ─────────
1. Verifica los SHA-256 de Resources/panel/*
   contra huellasServidor (compilados en el binario)
2. Comprueba que existe el Python de Apple
3. Lee el Llavero; emite o renueva certificados
4. Lanza  /usr/bin/python3 -I -B server.py
   con entorno limpio y escribe por stdin:  ──────▶ 5. leer_secretos(): JSON de stdin
   {admin_token, dispositivos, tls}                 6. contexto_tls(): carga cert y clave
                                                       (archivos temporales 0600, borrados al instante)
                                                    7. Abre tres servidores en hilos:
                                                         Panel        0.0.0.0:8787    HTTPS
                                                         Certificado  0.0.0.0:8788    HTTP
                                                         Admin        127.0.0.1:8789  HTTP
                                                    8. Hilos de fondo: vigilar_conexiones,
                                                       vigilar_padre (termina si la app muere)
9. Consulta /estado y /log cada 2 s
10. Revisa la red cada 30 s y el vencimiento cada 6 h;
    reinicia el servidor si hay que renovar el certificado
```

## Red y protocolo

| Capa | Tecnología |
|---|---|
| Transporte | TCP sobre IPv4 |
| Cifrado (8787) | TLS 1.2 mínimo; certificado ECDSA P-256 / SHA-256 emitido por la CA del panel |
| Aplicación | HTTP/1.0 (`http.server`) |
| Formato | JSON (UTF-8) |
| Autenticación | Reto-respuesta HMAC-SHA256 por dispositivo |

### Puertos

| Puerto | Interfaz | Protocolo | Clase | Consumidor |
|---|---|---|---|---|
| 8787 | `0.0.0.0` | HTTPS | `Panel` | Dispositivos emparejados |
| 8788 | `0.0.0.0` | HTTP | `Certificado` | Dispositivos, solo para instalar la CA |
| 8789 | `127.0.0.1` | HTTP | `Admin` | La app de control |

El 8788 no se cifra porque es el paso de arranque de la confianza: el
dispositivo aún no confía en la CA. La autenticidad se comprueba comparando a
mano la huella SHA-256.

## Autenticación

Cada dispositivo tiene una clave de 20 caracteres (alfabeto de 31 símbolos,
~99 bits) generada con `SecRandomCopyBytes` y muestreo por rechazo.

```
Dispositivo                                   Servidor
───────────                                   ────────
GET /reto                         ──────────▶ emitir_reto(ip)
                                  ◀────────── {"reto": "<32 hex>"}   (TTL 30 s, ligado a la IP)

firma = HMAC-SHA256(clave, reto + ":" + acción)

POST /accion/<acción>
  X-Reto:  <reto>
  X-Firma: <firma hex>            ──────────▶ consumir_reto(reto, ip)   (un solo uso)
                                              verificar_firma(): compara en tiempo
                                              constante contra todas las claves
                                  ◀────────── 200 {"ok": true} | 401
```

Propiedades:

- La clave nunca se transmite.
- La firma está ligada a la acción: una firma de `estado` no sirve para `copiar`.
- El reto es de un solo uso, caduca y solo vale para la IP que lo pidió.
- El cliente guarda la clave en `localStorage` del origen HTTPS. En el
  emparejamiento por QR llega en el fragmento (`#clave=…`), que el navegador no
  envía al servidor, y se borra de la URL con `history.replaceState`.

### Orden de validación (`Panel.do_POST`)

| Paso | Comprobación | Fallo |
|---|---|---|
| 1 | `_filtro_red`: IP privada, `Host` local, `Origin` coincidente | 403 |
| 2 | Sin cuerpo (`Content-Length` = 0) | 413 |
| 3 | `bloqueado(ip)`: fallos por IP y globales | 429 |
| 4 | Acción en `ACTIONS` o `estado` | 404 |
| 5 | Reto válido y firma correcta | 401 (cuenta como fallo) |
| 6 | Ejecución de la acción | 500 si falla (p. ej. falta un permiso) |

## Referencia de la API

Todas las respuestas son JSON salvo los archivos estáticos. Los errores tienen la
forma `{"error": "<mensaje>"}`. Todas las respuestas incluyen las cabeceras de
`SECURITY_HEADERS` (CSP, `X-Frame-Options: DENY`, `nosniff`, `no-store`,
`no-referrer`); el panel añade HSTS.

### Panel — `https://<ip>:8787`

| Método | Ruta | Autenticación | Respuesta |
|---|---|---|---|
| `GET` | `/`, `/app.js`, `/firma.js` | No | Archivos de la lista blanca `STATIC` |
| `GET` | `/reto` | No | `{"reto": "<hex>"}` |
| `POST` | `/accion/estado` | Firma | `{"ok": true, "accesibilidad": bool, "nombre": "<dispositivo>"}` |
| `POST` | `/accion/<acción>` | Firma | `{"ok": true}` |

Acciones disponibles (`ACTIONS`): `copiar`, `pegar`, `seleccionar`, `enter`,
`notas`, `musica`, `playpausa`, `siguiente`, `anterior`.

### Certificado — `http://<ip>:8788`

| Método | Ruta | Respuesta |
|---|---|---|
| `GET` | `/` | Página de instrucciones con la huella de la CA |
| `GET` | `/panel.mobileconfig` | Perfil de configuración (`application/x-apple-aspen-config`) con la CA |
| `GET` | `/panel-ca.cer` | Certificado DER de la CA (`application/x-x509-ca-cert`) |

### Administración — `http://127.0.0.1:8789`

Requiere a la vez: origen `127.0.0.1`, `Host: 127.0.0.1:8789`, ausencia de
`Origin` y `X-Admin: <token>`. El token son 32 bytes aleatorios generados por la
app en cada arranque; nunca se escribe en disco.

| Método | Ruta | Cuerpo | Respuesta |
|---|---|---|---|
| `GET` | `/estado` | — | `{ip, puerto, puerto_cert, tls, accesibilidad, dispositivos: [{id, nombre, ip, visto_hace, conectado}]}` |
| `GET` | `/log?desde=<seq>` | — | `{eventos: [{seq, hora, texto}], ultimo}` |
| `POST` | `/dispositivos` | `{dispositivos: [{id, nombre, clave}]}` (máx. 64 KiB) | `{"ok": true}`; reemplaza la lista completa |

### Códigos de estado

| Código | Significado |
|---|---|
| 200 | Correcto |
| 400 | JSON inválido (administración) |
| 401 | Firma o reto inválidos |
| 403 | Red, host u origen no permitidos; token de administración inválido |
| 404 | Ruta o acción inexistente |
| 405 | Método no permitido |
| 413 | Cuerpo no esperado o demasiado grande |
| 429 | Bloqueado por intentos fallidos |
| 500 | La acción falló (normalmente falta un permiso de macOS) |

## Gestión de secretos y certificados

| Secreto | Dónde vive | Cómo llega al servidor |
|---|---|---|
| Claves de dispositivos | Llavero (`local.jordan.panel-de-atajos` / `secretos`) | stdin al arrancar; `POST /dispositivos` al cambiar |
| Clave privada y certificado de la CA | Llavero | La clave privada nunca; el certificado por stdin |
| Clave privada y certificado del servidor | Llavero | stdin |
| Token de administración | Memoria de la app | stdin |

Certificados (emitidos con `/usr/bin/openssl`, protegido por SIP):

| Certificado | Algoritmo | Vigencia | Extensiones relevantes |
|---|---|---|---|
| CA | ECDSA P-256 | 10 años | `CA:TRUE, pathlen:0`; `nameConstraints` críticas: `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`, `.local` |
| Servidor | ECDSA P-256 | 825 días | `serverAuth`; SAN con las IPs `en*` y `<LocalHostName>.local` |

El certificado del servidor se reemite con la misma CA cuando cambian las
direcciones locales o faltan menos de 60 días para que venza, así que los
dispositivos no tienen que reinstalar nada.

## Configuración

Parámetros al inicio de `panel/server.py`:

| Constante | Valor | Descripción |
|---|---|---|
| `PUERTO`, `PUERTO_CERT`, `PUERTO_ADMIN` | 8787, 8788, 8789 | Puertos |
| `RETO_TTL` | 30 s | Vigencia de un reto |
| `RETOS_MAX` / `RETOS_POR_IP` | 64 / 8 | Retos pendientes, total y por IP |
| `BLOQUEO` | 300 s | Duración del bloqueo |
| `FALLOS_IP` / `FALLOS_TOTAL` | 8 / 25 | Fallos antes de bloquear una IP o todo el panel |
| `CONECTADO` | 45 s | Tiempo sin latido para marcar un dispositivo como desconectado |
| `MAX_ADMIN` | 64 KiB | Tamaño máximo de una petición de administración |

Las preferencias de la app (ícono de la barra) se guardan en `UserDefaults`
(`local.jordan.panel-de-atajos`); la imagen propia, en
`~/Library/Application Support/Panel de atajos/`.

## Cómo extender la API

`http.server` no tiene enrutador: cada clase de manejador implementa
`do_GET`/`do_POST` y enruta comparando `self.path`.

### Nueva acción (recomendado)

Agrega una entrada a `ACTIONS`:

```python
"guardar": lambda: keystroke("s", cmd=True),
```

`POST /accion/guardar` queda disponible con autenticación, límites y registro.
Una acción devuelve `None` si tuvo éxito o un mensaje de error para el cliente.

### Nuevo endpoint

Agrega una rama en el manejador correspondiente, antes del 404 final:

```python
# Panel.do_GET
if self.path == "/hora":
    return self._json(200, {"hora": time.strftime("%H:%M:%S")})
```

Pautas:

- Usa siempre `_json`, `_error` o `_send`, que añaden las cabeceras de seguridad.
- Todo lo que cambie el estado de la Mac debe ser un `POST` firmado. Lo más
  sencillo es modelarlo como acción.
- No ejecutes datos recibidos: mapea entradas a funciones fijas.
- Después de cambiar algo: `./app/compilar.sh`, conceder permisos y `./pruebas.sh`.

## Decisiones de diseño

| Decisión | Motivo | Alternativa descartada |
|---|---|---|
| Biblioteca estándar de Python | Sin dependencias que mantener o auditar | Flask o FastAPI |
| HMAC con reto en lugar de sesiones o tokens | Sin estado de sesión; la clave no viaja; resistente a repetición | Cookies de sesión o tokens de portador |
| CA propia con restricción de nombres | HTTPS real en la LAN sin exponer el dispositivo a suplantación de sitios de internet | Certificado autofirmado sin restricciones; HTTP plano |
| Secretos por stdin | No aparecen en `ps`, en el entorno ni en disco | Variables de entorno o archivo de configuración |
| Servidor sellado con huellas en el binario | Un servidor modificado no puede aprovechar el permiso de Accesibilidad | Confiar en los archivos del disco |
| Servidor como proceso hijo de la app | macOS atribuye Accesibilidad a la app y no a Python o a Terminal | Lanzador de script o servicio de launchd |
| JavaScript ES5 | Compatibilidad con Safari de iOS 12 | ES2015+ con compilación previa |

### Limitaciones conocidas

- **Bloqueo global:** en una red hostil, un tercero puede agotar `FALLOS_TOTAL` y
  bloquear el panel durante 5 minutos (denegación de servicio, no compromiso).
- **Firma ad-hoc:** cada compilación exige volver a conceder los permisos.
- **Una sola Mac por instalación.**
- **Botones fijos:** cambiarlos requiere compilar.
