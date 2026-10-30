# ADR 0007: Servidor como proceso hijo de la app

| Campo | Valor |
|---|---|
| Estado | Aceptada |
| Fecha | 2026-10-25 (registrada 2026-10-26) |

## Contexto

macOS asigna el permiso de Accesibilidad al proceso «responsable». Los primeros
lanzadores (un `.command` en Terminal y luego un script que hacía `exec` de
Python) hacían que el permiso recayera en Terminal o en Python, lo que concedía
control del teclado a cualquier script.

## Decisión

La app SwiftUI arranca el servidor como proceso hijo y permanece como padre. El
servidor termina si la app muere (`vigilar_padre`). El arranque al iniciar
sesión usa `SMAppService.mainApp`.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Ejecutar desde Terminal | Concede Accesibilidad a Terminal: cualquier script podría usarla |
| Script que hace `exec` de Python | El permiso termina asignado a Python |
| Servicio de launchd independiente | El permiso no se atribuye a la app; más difícil de entender y apagar |

## Consecuencias

- **Positivas:** el permiso solo lo tiene «Panel de atajos»; un único punto para encender, apagar y ver el estado.
- **Negativas:** el panel solo funciona con una sesión de usuario iniciada.
- **Seguimiento:** en v2.0 el servidor se integrará en la propia app (sin proceso hijo).
