# ADR 0005: Secretos en el Llavero y entrega por stdin

| Campo | Valor |
|---|---|
| Estado | Aceptada |
| Fecha | 2026-10-25 (registrada 2026-10-26) |

## Contexto

Las claves estaban en `config.json` (legible por cualquier proceso del usuario)
y el token de administración en una variable de entorno, visible con `ps eww`.
Durante las pruebas se comprobó que el token podía leerse así.

## Decisión

Las claves, la CA y el certificado se guardan en un único elemento del Llavero
de macOS. La app los lee y se los entrega al servidor por la entrada estándar
al arrancarlo; el servidor los mantiene solo en memoria. Mostrar, crear o rotar
claves pide Touch ID o la contraseña.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Archivo de configuración con permisos 0600 | Legible por cualquier proceso del mismo usuario y por copias de seguridad |
| Variables de entorno | Visibles en `ps eww` |
| Argumentos de línea de comandos | Visibles en `ps` |
| Llavero moderno (data protection) | Requiere firma de Apple Developer ID |

## Consecuencias

- **Positivas:** nada sensible en disco, en `ps` ni en git; acceso al Llavero ligado a la firma de la app.
- **Negativas:** con firma ad-hoc se usa el Llavero clásico (no aplica `ThisDeviceOnly`) y cada compilación pide permiso de nuevo.
- **Seguimiento:** `pruebas.sh` verifica que no haya secretos en `ps` ni en archivos.
