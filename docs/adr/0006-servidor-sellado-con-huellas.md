# ADR 0006: Servidor sellado con huellas SHA-256 en el binario

| Campo | Valor |
|---|---|
| Estado | Aceptada |
| Fecha | 2026-10-25 (registrada 2026-10-26) |

## Contexto

La app tiene el permiso de Accesibilidad y el servidor hereda ese poder. Si un
programa malicioso modificara `server.py`, podría controlar el teclado sin
pedir permisos. macOS solo protege con la firma el ejecutable principal.

## Decisión

`compilar.sh` copia el servidor dentro del paquete `.app` (solo lectura) y graba
sus SHA-256 en el binario (`Huellas.swift`). La app verifica las huellas antes
de cada arranque y se niega a encender si no coinciden. Python se ejecuta con
`-I -B` y un entorno limpio, y se usan `/usr/bin/python3` y `/usr/bin/openssl`,
protegidos por macOS.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Ejecutar el servidor desde la carpeta del proyecto | Cualquier proceso del usuario puede modificarlo |
| Confiar en la firma del paquete | macOS no revalida los recursos en cada ejecución |

## Consecuencias

- **Positivas:** un servidor alterado nunca se ejecuta con el permiso de la app (probado modificando el archivo).
- **Negativas:** cualquier cambio en el servidor exige recompilar y volver a conceder permisos.
- **Seguimiento:** `pruebas.sh` comprueba que la app lleve la última versión del código.
