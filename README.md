# Panel de atajos

Convierte un iPad (u otro dispositivo con Safari) en un panel de botones que
controla tu Mac por la red local: copiar, pegar, seleccionar todo, Enter, abrir
Notas y controlar la música.

Está pensado para reutilizar dispositivos viejos (funciona en un iPad Air de
2013 con iOS 12) sin sacrificar seguridad: HTTPS con una CA propia, una clave
por dispositivo, firmas HMAC de un solo uso y secretos guardados en el Llavero
de macOS.

> **Ámbito:** uso personal en una red de confianza. No está diseñado para
> exponerse a internet. Ver [Seguridad](#seguridad).

## Características

- **App nativa para macOS** (SwiftUI) con interruptor de encendido, ícono en la
  barra de menú y arranque al iniciar sesión.
- **Emparejamiento por código QR**, con varios dispositivos y estado de conexión
  en tiempo real.
- **Gestión de claves desde la app:** crear, mostrar, rotar y revocar, protegido
  con Touch ID o la contraseña de la Mac.
- **HTTPS con CA propia** restringida a la red local; el certificado del
  servidor se renueva solo.
- **Registro de actividad en memoria** que se borra al apagar el panel.
- **Verificación de integridad:** la app se niega a arrancar si el servidor fue
  modificado.
- **Pruebas de seguridad automatizadas** (`pruebas.sh`, 23 comprobaciones).

## Requisitos

| Componente | Versión |
|---|---|
| macOS | 14 Sonoma o posterior (Apple Silicon) |
| Herramientas de línea de comandos de Apple | Incluyen `swiftc` y Python 3 (`xcode-select --install`) |
| Dispositivo cliente | Safari en iOS/iPadOS 12 o posterior, o cualquier navegador moderno |
| Red | Mac y dispositivo en la misma red local |

No necesita dependencias externas: el servidor usa solo la biblioteca estándar
de Python y la app solo frameworks del sistema.

## Inicio rápido

```bash
git clone https://github.com/jorgr1820-hub/panel-de-atajos.git
cd panel-de-atajos
./app/compilar.sh
open "Panel de atajos.app"
```

La app es autocontenida: el servidor va dentro del paquete `.app`, así que
puedes moverla a cualquier carpeta después de compilarla.

En el primer arranque macOS pedirá:

1. **Llavero** → *Permitir siempre*.
2. **Accesibilidad** → *Ajustes del Sistema → Privacidad y seguridad →
   Accesibilidad* → activa *Panel de atajos*.

### Emparejar un dispositivo

1. En la app: **Nueva conexión…** → escribe un nombre → confirma con Touch ID.
2. En el dispositivo, abre `http://<IP-de-la-Mac>:8788` e instala el perfil del
   panel:
   - *Ajustes → Perfil descargado → Instalar*.
   - *Ajustes → General → Información → Ajustes de confianza de certificados* →
     activa **Panel de atajos CA**.
   - Comprueba que la huella SHA-256 coincide con la que muestra la app.
3. Escanea el código QR con la cámara del dispositivo.

## Uso

| Tarea | Dónde |
|---|---|
| Encender / apagar | Interruptor de la ventana o ícono de la barra de menú |
| Arranque automático | *Abrir al iniciar sesión* |
| Ver o rotar la clave de un dispositivo | *Mostrar código* / *Nueva clave* |
| Quitar acceso | *Revocar* |
| Cambiar el ícono de la barra | *Ícono de la barra* (incluye símbolo SF personalizado o imagen propia) |
| Renovar la CA | *Crear certificado nuevo…* (los dispositivos deben reinstalar el perfil) |

## Arquitectura

```
iPad (Safari)  ──HTTPS :8787──▶  server.py  ──▶  1 de 9 acciones fijas (AppleScript / open)
               ──HTTP  :8788──▶  descarga del perfil de la CA
App macOS      ──HTTP  127.0.0.1:8789──▶  administración (token por sesión)
```

La app arranca `server.py` como proceso hijo y le entrega los secretos por la
entrada estándar. Cada toque es un reto-respuesta HMAC-SHA256: la clave del
dispositivo nunca viaja por la red.

Detalle completo, referencia de la API y cómo agregar endpoints:
**[docs/ARQUITECTURA.md](docs/ARQUITECTURA.md)**.

## Estructura del proyecto

```
.
├── app/
│   ├── PanelApp.swift     App macOS: interfaz, Llavero, certificados, Touch ID, arranque del servidor
│   └── compilar.sh        Compila la app, sella el servidor (huellas SHA-256) y firma ad-hoc
├── panel/
│   ├── server.py          Servidor HTTPS y API (biblioteca estándar de Python)
│   ├── index.html         Página de botones del dispositivo
│   ├── app.js             Lógica del cliente (ES5, compatible con iOS 12)
│   └── firma.js           HMAC-SHA256 en JavaScript puro
├── docs/
│   └── ARQUITECTURA.md    Diseño, protocolo y referencia de la API
├── pruebas.sh             Pruebas de seguridad
├── SEGURIDAD.md           Modelo de amenazas y límites conocidos
└── CHANGELOG.md           Historial de cambios
```

`Panel de atajos.app` es un artefacto de compilación y no se versiona.

## Desarrollo

### Agregar un botón

1. Agrega la acción en `ACTIONS` (`panel/server.py`):
   ```python
   "guardar": lambda: keystroke("s", cmd=True),
   ```
2. Agrega el botón en `panel/index.html` con el mismo nombre:
   ```html
   <button class="btn texto" data-accion="guardar"><span>💾</span>Guardar</button>
   ```
3. Compila, vuelve a abrir la app y concede de nuevo los permisos:
   ```bash
   ./app/compilar.sh
   ```
4. Verifica y guarda:
   ```bash
   ./pruebas.sh
   git commit -am "feat: botón Guardar"
   ```

El endpoint `/accion/guardar` existe automáticamente, con autenticación y
límites incluidos.

### ¿Por qué cada compilación pide permisos otra vez?

El servidor va sellado dentro de la app: sus huellas SHA-256 se graban en el
binario y la app no arranca si cambian. macOS asocia Accesibilidad y Llavero a
la firma exacta del binario, y con firma ad-hoc cada compilación produce una
firma distinta. Es intencional: un binario modificado no hereda permisos. Una
firma de Apple Developer ID eliminaría esta fricción.

### Pruebas

Con el panel encendido:

```bash
./pruebas.sh
```

Comprueba cifrado, control de acceso, aislamiento de la administración, ausencia
de secretos en disco o en `ps` e integridad de la app. Cada ejecución suma dos
intentos fallidos a la IP de la Mac (el bloqueo es de 8 en 5 minutos).

## Seguridad

Resumen del modelo de amenazas (completo en **[SEGURIDAD.md](SEGURIDAD.md)**):

- **Protegido:** escucha y manipulación en la red, robo de la clave por
  inyección de código, repetición de peticiones, fuerza bruta, CSRF y DNS
  rebinding, ejecución de comandos arbitrarios, lectura de claves desde disco,
  modificación del servidor.
- **Riesgos aceptados:** un dispositivo emparejado y desbloqueado tiene acceso a
  los botones; en redes ajenas un tercero puede provocar un bloqueo temporal;
  malware con control total de la cuenta de usuario.

**No abras estos puertos en tu router.** Para acceso remoto usa una VPN.

## Mantenimiento

- **Certificado del servidor:** 825 días, renovación automática a 60 días del
  vencimiento o al cambiar de IP.
- **CA:** 10 años. Si se renueva, la app lo avisa y hay que reinstalar el perfil.
- **Python:** si una actualización de macOS elimina las herramientas de línea de
  comandos, la app lo indica; se reinstalan con `xcode-select --install`.
- **Migrar de Mac:** no hay nada que respaldar. Clona, compila y vuelve a
  emparejar.

## Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| "Falta permiso de Accesibilidad" | Entrada vieja tras recompilar | Borra todas las entradas de *Panel de atajos* en Accesibilidad y agrega la actual |
| El Llavero pide permiso en cada arranque | Se pulsó *Permitir* en vez de *Permitir siempre* | Pulsa *Permitir siempre* |
| El dispositivo no puede instalar el certificado | iOS 12 no descarga archivos | Usa el enlace *Instalar perfil del panel* en el puerto 8788 |
| No aparece el interruptor de confianza del certificado | El perfil no está instalado | *Ajustes → General → Perfiles* → instalar |
| "Clave incorrecta" | Clave rotada o revocada | *Mostrar código* y volver a emparejar |
| "Demasiados intentos" | Bloqueo por fallos | Espera 5 minutos |

## Licencia

Copyright © 2026 Jordan Guzman. Todos los derechos reservados.

El código es visible con fines de consulta. No se concede permiso para usarlo,
copiarlo, modificarlo ni distribuirlo sin autorización expresa del autor.
