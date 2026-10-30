# ADR 0003: Autenticación reto-respuesta HMAC-SHA256

| Campo | Valor |
|---|---|
| Estado | Aceptada |
| Fecha | 2026-10-25 (registrada 2026-10-26) |

## Contexto

La primera versión enviaba un PIN de 6 dígitos en cada petición: se podía
capturar en la red y adivinar en un millón de intentos. El cliente es Safari de
iOS 12, sin `crypto.subtle` en páginas HTTP y con JavaScript ES5.

## Decisión

Cada dispositivo tiene una clave aleatoria de ~99 bits. Para cada acción el
cliente pide un reto aleatorio de un solo uso (30 s, ligado a su IP) y envía
`HMAC-SHA256(clave, reto + ":" + acción)`. El servidor prueba la firma contra
todas las claves en tiempo constante; la que coincide identifica al dispositivo.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Token o contraseña en cada petición | La credencial viaja; si se captura, se reutiliza |
| Cookies de sesión | Estado de sesión que gestionar; vulnerables a CSRF sin medidas extra |
| Firma con marca de tiempo | Depende de que los relojes estén sincronizados |
| mTLS (certificado de cliente) | Instalación compleja en iOS 12 y difícil de revocar para un usuario no técnico |

## Consecuencias

- **Positivas:** la clave nunca viaja; peticiones irrepetibles; firma ligada a la acción; revocar o rotar es inmediato.
- **Negativas:** dos peticiones por toque (reto + acción); implementación propia de SHA-256 en JS (verificada contra Python en las pruebas).
- **Seguimiento:** `tests/test_firma.py` compara la implementación JS con Python en CI.
