# Historial de cambios

Todos los cambios relevantes del proyecto se documentan aquí.

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/);
el proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [Sin publicar]

### Agregado
- Pruebas unitarias del servidor (22) y verificación de `firma.js` contra Python.
- Integración continua en GitHub Actions: pruebas, compilación, verificación del sellado y escaneo de secretos.
- Dependabot para las acciones de GitHub.
- Archivo `VERSION` como única fuente de la versión; `compilar.sh` la aplica a la app.

### Documentación
- ADR 0001–0009: registro de las decisiones de arquitectura.
- RFC 0001: análisis del acceso por internet desde seguridad, arquitectura, desarrollo y usuario.
- `CONTRIBUTING.md`: flujo de ramas, commits convencionales, versionado y releases.
- `docs/ROADMAP.md` y plantillas de Pull Request e issues.

## [1.0.0] - 2026-10-25

Primera versión estable.

### Agregado
- App macOS (SwiftUI) con interruptor, ícono en la barra de menú (configurable, con símbolo SF o imagen propia) y arranque al iniciar sesión.
- Varios dispositivos con emparejamiento por QR, estado de conexión y registro de actividad en memoria.
- Gestión de claves desde la app: crear, mostrar, rotar y revocar.
- Renovación automática del certificado del servidor al cambiar de red o a 60 días del vencimiento.
- Aviso cuando faltan las herramientas de línea de comandos de Apple.
- `pruebas.sh` con 23 comprobaciones de seguridad.
- Documentación: README, arquitectura, modelo de amenazas.

### Seguridad
- HTTPS con CA propia restringida a la red local (`nameConstraints`).
- Autenticación reto-respuesta HMAC-SHA256 con una clave por dispositivo; retos de un solo uso ligados a la IP.
- Claves y certificados en el Llavero; secretos entregados al servidor por stdin.
- Touch ID o contraseña para mostrar, crear o rotar claves.
- Verificación de integridad del servidor con huellas SHA-256 compiladas en la app.
- API de administración limitada a `127.0.0.1`.
- Canal privado para reportar vulnerabilidades.

[Sin publicar]: https://github.com/jorgr1820-hub/panel-de-atajos/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jorgr1820-hub/panel-de-atajos/releases/tag/v1.0.0
