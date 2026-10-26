# Panel de atajos

Convierte un iPad (u otro dispositivo con Safari) en un panel de botones que
controla esta Mac: copiar, pegar, seleccionar todo, Enter, abrir Notas y
controlar la música. Funciona solo en la red de casa, por HTTPS y con una clave
por dispositivo. Los detalles de seguridad están en [SEGURIDAD.md](SEGURIDAD.md).

## Uso diario

- **Encender o apagar:** abre *Panel de atajos* (acceso directo en el Escritorio)
  y usa el interruptor, o el ícono ⌨️ de la barra de menú.
- **Agregar un dispositivo:** *Nueva conexión…* → en el dispositivo instala el
  certificado (`http://IP-de-la-Mac:8788`) → escanea el código QR.
- **Ver de nuevo la clave o cambiarla:** *Mostrar código* / *Nueva clave* (piden Touch ID).
- **Quitar el acceso a un dispositivo:** *Revocar*.

## Estructura

```
Panel de atajos.app     La app compilada (no se edita a mano).
app/PanelApp.swift      Interfaz, Llavero, certificados, Touch ID y arranque del servidor.
app/compilar.sh         Compila la app, sella el servidor dentro y la firma.
panel/server.py         Servidor: HTTPS, firmas, acciones, bloqueos, registro en memoria.
panel/index.html        Página de botones del dispositivo.
panel/app.js            Lógica de la página (ES5, compatible con iOS 12).
panel/firma.js          HMAC-SHA256 en JavaScript.
pruebas.sh              Pruebas de seguridad (23 comprobaciones).
SEGURIDAD.md            Modelo de amenazas y límites conocidos.
```

Las claves, el certificado y la CA no están en esta carpeta: viven en el
Llavero de macOS (elemento *Panel de atajos*).

## Agregar o cambiar un botón

1. **`panel/server.py`:** agrega la acción al diccionario `ACTIONS`, por ejemplo
   `"guardar": lambda: keystroke("s", cmd=True),`
2. **`panel/index.html`:** agrega el botón con el mismo nombre en `data-accion`:
   `<button class="btn texto" data-accion="guardar"><span>💾</span>Guardar</button>`
3. Compila y reinstala:
   ```bash
   ./app/compilar.sh
   ```
4. Cierra la app (menú ⌨️ → Salir) y ábrela otra vez.
5. macOS pedirá de nuevo **Llavero → Permitir siempre** y el permiso de
   **Accesibilidad** (borra la entrada vieja con − y agrega la nueva).
6. Comprueba que todo sigue protegido:
   ```bash
   ./pruebas.sh
   ```
7. Guarda el cambio en el historial:
   ```bash
   git commit -am "Botón Guardar"
   ```

### ¿Por qué hay que volver a dar permisos al compilar?

El código del servidor va **sellado** dentro de la app: sus huellas SHA-256 se
graban en el programa al compilar y la app se niega a arrancar si el servidor
cambia. Así, un programa malicioso no puede modificarlo para aprovechar el
permiso de Accesibilidad. Y macOS amarra los permisos de Accesibilidad y del
Llavero a la firma exacta del programa: un programa nuevo es, para macOS, una
app distinta que tiene que ganarse los permisos otra vez.

## Mantenimiento

- **Certificado del servidor:** dura 825 días y la app lo renueva sola cuando le
  quedan menos de 60, o si cambia la IP de la Mac. No hay que hacer nada.
- **CA del panel:** dura 10 años (hasta 2036). Si llega a renovarse, la app lo
  avisa y hay que reinstalar el perfil en los dispositivos.
- **Python:** el servidor usa el Python de las herramientas de línea de comandos
  de Apple. Si una actualización de macOS las quita, la app lo avisa; se
  reinstalan con `xcode-select --install`.
- **Si cambias de Mac:** no hay nada que respaldar. Copia esta carpeta, compila,
  y vuelve a emparejar los dispositivos.

## Puertos

| Puerto | Uso | Desde dónde |
|---|---|---|
| 8787 | Panel (HTTPS) | Red local |
| 8788 | Descarga del certificado (HTTP) | Red local |
| 8789 | Administración de la app | Solo esta Mac |
