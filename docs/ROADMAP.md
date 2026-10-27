# Roadmap

Plan de versiones. Cada versión tiene un hito en GitHub con sus issues. El
análisis que justifica el orden está en el [RFC 0001](rfc/0001-acceso-por-internet.md).

| Versión | Tema | Objetivo |
|---|---|---|
| ✅ 1.0.0 | Primera versión estable | Panel seguro para la red local |
| **1.1.0** | Endurecer la red local | Reducir la superficie expuesta y cerrar el vector de denegación de servicio |
| 1.2.0 | Mínimo privilegio | Botones configurables y permisos por dispositivo |
| 2.0.0 | Servidor de producción | Servidor en Swift dentro de la app, sin Python, API `/v1/` |
| 2.1.0 | Acceso remoto | Acceso fuera de casa mediante una red privada superpuesta (VPN) |

## 1.1.0: endurecer la red local

- **Redes de confianza:** el panel solo se enciende en redes Wi-Fi aprobadas y se apaga solo en las demás.
- **Retroceso exponencial por IP** en lugar del bloqueo global, que permite a un tercero bloquear el panel.
- **Modo emparejamiento:** el puerto 8788 (HTTP) solo se abre unos minutos al emparejar.
- **Versión visible** en la app y en `/estado`.
- **Pruebas de integración** del servidor en la CI.

## 1.2.0: mínimo privilegio

- Botones configurables desde la app, guardados en el Llavero (sin recompilar).
- Lista de acciones permitidas por dispositivo.

## 2.0.0: servidor de producción

- Servidor HTTPS en Swift (Network.framework) dentro de la app.
- Elimina la dependencia de Python y el proceso hijo.
- API versionada `/v1/` (cambio incompatible).

## 2.1.0: acceso remoto

- Soporte de Tailscale o WireGuard: rango `100.64.0.0/10` y dominio de la VPN en la CA y los filtros.
- Indicador «Visible desde internet: No».
- Guía de configuración.
- Requiere un dispositivo con iOS 15 o posterior.
