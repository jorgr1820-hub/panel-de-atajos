# ADR 0002: Servidor con la biblioteca estándar de Python

| Campo | Valor |
|---|---|
| Estado | Aceptada (se revisará en v2.0, ver [RFC 0001](../rfc/0001-acceso-por-internet.md)) |
| Fecha | 2026-10-25 (registrada 2026-10-26) |

## Contexto

Se necesitaba un servidor HTTP(S) pequeño en la Mac, sin instalar nada adicional
y fácil de auditar. macOS incluye Python 3 con las herramientas de línea de
comandos de Apple.

## Decisión

El servidor (`panel/server.py`) usa solo la biblioteca estándar: `http.server`,
`ssl`, `hmac`, `secrets`. Sin dependencias de terceros.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Flask / FastAPI | Dependencias que instalar, actualizar y auditar (riesgo de cadena de suministro) |
| Node.js | No viene con macOS |
| Servidor en Swift desde el inicio | Más lento de construir; se planifica para v2.0 |

## Consecuencias

- **Positivas:** cero dependencias; un solo archivo legible; arranca en cualquier Mac con las herramientas de Apple.
- **Negativas:** `http.server` no es de grado de producción (su documentación lo advierte); depende de que Apple siga incluyendo Python.
- **Seguimiento:** aceptable solo en red local. Reemplazar antes de cualquier acceso remoto (v2.0).
