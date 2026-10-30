# Registros de decisiones de arquitectura (ADR)

Cada decisión importante se documenta en un ADR corto e inmutable: qué se
decidió, por qué y qué consecuencias tiene. Si una decisión cambia, se escribe un
ADR nuevo que *reemplaza* al anterior; el viejo no se borra.

Formato: [plantilla](0000-plantilla.md), basada en el modelo de Michael Nygard.

| # | Decisión | Estado |
|---|---|---|
| [0001](0001-registrar-decisiones.md) | Registrar las decisiones de arquitectura | Aceptada |
| [0002](0002-servidor-con-biblioteca-estandar.md) | Servidor con la biblioteca estándar de Python | Aceptada (se revisará en v2.0) |
| [0003](0003-autenticacion-hmac-con-reto.md) | Autenticación reto-respuesta HMAC-SHA256 | Aceptada |
| [0004](0004-ca-propia-con-restriccion-de-nombres.md) | HTTPS con CA propia restringida a la red local | Aceptada |
| [0005](0005-secretos-en-llavero-y-stdin.md) | Secretos en el Llavero y entrega por stdin | Aceptada |
| [0006](0006-servidor-sellado-con-huellas.md) | Servidor sellado con huellas SHA-256 en el binario | Aceptada |
| [0007](0007-servidor-como-proceso-hijo.md) | Servidor como proceso hijo de la app | Aceptada |
| [0008](0008-versionado-y-flujo-de-trabajo.md) | Versionado semántico y flujo con Pull Requests | Aceptada |
| [0009](0009-estrategia-de-acceso-por-internet.md) | Estrategia de acceso por internet | Propuesta |

Para decisiones grandes que necesitan análisis previo se escribe primero un
[RFC](../rfc/).
