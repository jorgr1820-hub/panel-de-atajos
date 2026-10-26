# Historial de cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## [Sin publicar]

### Documentación
- README reescrito: requisitos, inicio rápido, uso, desarrollo y solución de problemas.
- `docs/ARQUITECTURA.md`: componentes, protocolo, referencia de la API y decisiones de diseño.
- Política de reporte de vulnerabilidades en `SEGURIDAD.md`.

## 2026-10-25

### Agregado
- Íconos de la barra de menú «23 en círculo», «23 en cuadro» y «Balón de básquet».
- Ícono personalizado con cualquier símbolo SF o con una imagen propia.
- Selector del ícono de la barra; la elección se guarda en las preferencias, sin recompilar.
- Arranque al iniciar sesión (`SMAppService`); al iniciar sesión arranca solo en la barra de menú.
- Renovación automática del certificado del servidor al cambiar de red o a 60 días del vencimiento.
- Aviso cuando faltan las herramientas de línea de comandos de Apple (Python).
- `pruebas.sh` con 23 comprobaciones de seguridad.

### Seguridad
- HTTPS con CA propia restringida a la red local (`nameConstraints`).
- Claves y certificados en el Llavero; migración automática desde `config.json` con borrado seguro.
- Secretos entregados al servidor por stdin en lugar de variables de entorno.
- Verificación de integridad del servidor mediante huellas SHA-256 compiladas en la app.
- Touch ID o contraseña para mostrar, crear o rotar claves.
- API de administración limitada a `127.0.0.1`.
- Retos ligados a la IP que los pidió y límite de retos pendientes por IP.

### Inicial
- App macOS con varios dispositivos, emparejamiento por QR, estado de conexión y registro en memoria.
- Servidor con autenticación reto-respuesta HMAC-SHA256 y 9 acciones.
