# ADR 0001: Registrar las decisiones de arquitectura

| Campo | Valor |
|---|---|
| Estado | Aceptada |
| Fecha | 2026-10-26 |

## Contexto

El proyecto pasó de un script a una app con criptografía, certificados y
permisos del sistema. Muchas decisiones no son obvias leyendo el código (por
ejemplo, por qué los secretos van por stdin o por qué cada compilación pide
permisos). Sin registro, ese conocimiento se pierde y se repiten debates o se
deshacen protecciones por desconocimiento.

## Decisión

Documentaremos cada decisión significativa como un ADR en `docs/adr/`,
numerado e inmutable. Las decisiones grandes se analizan antes en un RFC en
`docs/rfc/`.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| Comentarios en el código | Explican el *cómo* local, no el *porqué* global ni las alternativas |
| Wiki de GitHub | No se versiona junto al código ni pasa por revisión en el PR |
| Nada | El conocimiento queda en conversaciones y se pierde |

## Consecuencias

- **Positivas:** cualquier persona (o tú en un año) entiende el diseño y sus límites.
- **Negativas:** pequeño costo de escribir cada ADR.
- **Seguimiento:** el checklist del Pull Request pregunta si el cambio necesita un ADR.
